-- A tapped reminder routes to /person/:personId, and the batch did not carry
-- the id -- it returned the display_name but not the row it came from, even
-- though notification_outbox has subject_person_id.
--
-- `create or replace` CANNOT do this: changing a `returns table` shape raises
-- "cannot change return type of existing function". Both the private function
-- and its public wrapper must be dropped and recreated.
--
-- DROP TAKES THE ACL WITH IT. A freshly created function is executable by
-- `public`. Every revoke/grant below is therefore mandatory, not decorative:
-- omitting them exposes a security definer function that reads every user's
-- device tokens to anon. 32_batch_person_id.test.sql asserts exactly this.
drop function if exists public.rpc_next_reminder_batch(int);
drop function if exists private.next_reminder_batch(int);

create function private.next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  subject_person_id bigint,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  with claimed as (
    update private.notification_outbox o
    set claimed_at = now(), attempts = o.attempts + 1
    where o.id in (
      select c.id
      from private.notification_outbox c
      where c.sent_at is null
        and c.attempts < 5
        and (c.claimed_at is null or c.claimed_at < now() - interval '10 minutes')
        and exists (
          select 1 from public.device_tokens d
          where d.profile_id = c.recipient_profile_id
        )
      order by c.id
      limit p_limit
      for update skip locked
    )
    returning o.id, o.recipient_profile_id, o.subject_person_id,
              o.offset_days, o.occasion_date
  )
  select cl.id, d.token, d.platform, p.display_name, cl.subject_person_id,
         cl.offset_days, cl.occasion_date
  from claimed cl
  join public.people p on p.id = cl.subject_person_id
  -- At most five devices per reminder. A user may register unlimited tokens
  -- and this join is per-token, so without a bound one reminder becomes an
  -- unbounded number of FCM calls at the user's own discretion.
  cross join lateral (
    select d2.token, d2.platform
    from public.device_tokens d2
    where d2.profile_id = cl.recipient_profile_id
    order by d2.last_seen_at desc, d2.id desc
    limit 5
  ) d
  order by cl.id;
$$;

revoke execute on function private.next_reminder_batch(int)
  from public, anon, authenticated;

create function public.rpc_next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  subject_person_id bigint,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  select * from private.next_reminder_batch(p_limit);
$$;

revoke execute on function public.rpc_next_reminder_batch(int)
  from public, anon, authenticated;
grant execute on function public.rpc_next_reminder_batch(int) to service_role;
