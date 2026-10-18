-- A member is told when someone leaves a wish on their wall: "Asha left you
-- a birthday wish." It rides the reminder pipeline end to end -- the same
-- outbox, claim, lease, retry cap, release and drain -- rather than a second
-- one, so every guarantee already proven for reminders holds here too.

-- ------------------------------------------------------------- the outbox

-- The table was written for reminders: offset_days and occasion_date were
-- NOT NULL and the offset check applied to every row. A wish has neither.
-- They become nullable, and one check states each kind's whole shape, so a
-- row can never be half one kind and half the other.
alter table private.notification_outbox
  add column wish_id bigint references public.wishes (id) on delete cascade;

alter table private.notification_outbox
  alter column offset_days drop not null,
  alter column occasion_date drop not null;

alter table private.notification_outbox
  drop constraint notification_outbox_kind_valid,
  drop constraint notification_outbox_offset_valid;

alter table private.notification_outbox
  add constraint notification_outbox_kind_valid
    check (kind in ('reminder', 'wish')),
  add constraint notification_outbox_kind_shape check (
    (kind = 'reminder'
      and offset_days in (7, 1, 0)
      and occasion_date is not null
      and wish_id is null)
    or
    (kind = 'wish'
      and wish_id is not null
      and offset_days is null
      and occasion_date is null)
  );

-- THE no-double-send guarantee for wishes, as a constraint like the
-- reminders' notification_outbox_once. That key cannot do this job: a wish
-- row's occasion_date and offset_days are null, and NULLs never collide in a
-- unique constraint, so it would admit any number of rows for one wish.
-- One wish has exactly one recipient (its subject's profile), so the wish id
-- alone is the key. Partial, so reminder rows (wish_id null) are untouched.
-- It is also the index 11_rls_coverage requires on the wish_id foreign key.
create unique index notification_outbox_one_per_wish
  on private.notification_outbox (wish_id)
  where wish_id is not null;

-- ------------------------------------------------------------- preference

-- Separate from reminders_enabled: "tell me before birthdays" and "tell me
-- when someone wishes me" are different asks, and folding them into one
-- switch would make turning off the noisier one cost the other. Defaults on
-- for the same reason reminders do.
alter table public.profiles
  add column wish_notifications_enabled boolean not null default true;

-- R14, as for reminders_enabled (20260827000001): profiles has no
-- table-level update grant, so a new column is not client-writable until it
-- is named here, and the failure is a loud "permission denied", not a no-op.
grant update (wish_notifications_enabled) on public.profiles to authenticated;

-- ------------------------------------------------------------- enqueue

-- AFTER INSERT, so it sees only wishes that actually committed past
-- wishes_insert_own and every check constraint. Security definer because the
-- author cannot read the recipient's profile (profiles_select_own) nor write
-- the private outbox at all.
create or replace function private.enqueue_wish_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
begin
  -- A cake is posted by the gift pipeline (private.post_cake_wish) and has
  -- its own moment; this is about someone writing to you.
  if new.kind <> 'message' then
    return null;
  end if;

  select p.profile_id into v_recipient
  from public.people p
  where p.id = new.subject_person_id;

  -- An unclaimed person is an imported contact: nobody to notify.
  if v_recipient is null then
    return null;
  end if;

  -- Writing on your own wall is not news to you.
  if v_recipient = new.author_profile_id then
    return null;
  end if;

  -- The Settings switch.
  if not exists (
    select 1 from public.profiles r
    where r.id = v_recipient and r.wish_notifications_enabled
  ) then
    return null;
  end if;

  -- The same filter enqueue_reminders applies: a block does not delete
  -- edges, so without it a blocked person could still reach the user who
  -- blocked them, by name, on their lock screen.
  if exists (
    select 1 from public.blocks b
    where b.blocker_profile_id = v_recipient
      and b.blocked_profile_id = new.author_profile_id
  ) then
    return null;
  end if;

  insert into private.notification_outbox (
    recipient_profile_id, subject_person_id, kind, wish_id
  ) values (
    v_recipient, new.subject_person_id, 'wish', new.id
  )
  on conflict (wish_id) where wish_id is not null do nothing;

  return null;
end;
$$;

revoke execute on function private.enqueue_wish_notification()
  from public, anon, authenticated;

create trigger wishes_enqueue_notification
  after insert on public.wishes
  for each row execute function private.enqueue_wish_notification();

-- ------------------------------------------------------------- the batch

-- Extended in place rather than a second batch function, so one claim
-- serves both kinds: the lease, skip-locked claiming, the five-attempt cap,
-- the five-device bound and release_reminder_claims all apply unchanged.
-- New columns are APPENDED, so the drain's existing fields keep their
-- meaning and position.
--
-- `create or replace` cannot change a `returns table` shape, so both
-- functions are dropped and recreated -- and DROP TAKES THE ACL WITH IT
-- (see 20260927000001). Every revoke and grant below is mandatory;
-- 32_batch_person_id.test.sql asserts them.
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
  occasion_date date,
  kind text,
  author_name text,
  wish_id bigint
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
              o.offset_days, o.occasion_date, o.kind, o.wish_id
  )
  select cl.id, d.token, d.platform, p.display_name, cl.subject_person_id,
         cl.offset_days, cl.occasion_date, cl.kind,
         -- The name the recipient would see for this author in the app,
         -- chosen by feed_page's rule (20261018000002): the author's people
         -- row when the recipient can see it, otherwise the name the author
         -- chose on their own profile. feed_page asks private.can_see_person,
         -- which reads auth.uid() -- null here, where the drain runs as
         -- service_role -- so its three branches are restated for the
         -- RECIPIENT. A wish row's subject is always the recipient's own
         -- person (the trigger only queues for a claimed subject), so
         -- cl.subject_person_id stands in for private.my_person_id().
         case when cl.kind = 'wish' then
           case
             when ap.id is not null and (
               ap.id = cl.subject_person_id
               or exists (
                 select 1 from public.celebrations c
                 where c.person_id = ap.id
                   and c.celebrator_profile_id = cl.recipient_profile_id
               )
               or exists (
                 select 1 from public.celebrations c
                 where c.person_id = cl.subject_person_id
                   and c.celebrator_profile_id = ap.profile_id
               )
             ) then ap.display_name
             else apr.display_name
           end
         end,
         cl.wish_id
  from claimed cl
  join public.people p on p.id = cl.subject_person_id
  left join public.wishes w on w.id = cl.wish_id
  left join public.people ap on ap.profile_id = w.author_profile_id
  left join public.profiles apr on apr.id = w.author_profile_id
  -- At most five devices per notification. A user may register unlimited
  -- tokens and this join is per-token, so without a bound one notification
  -- becomes an unbounded number of FCM calls at the user's own discretion.
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
  occasion_date date,
  kind text,
  author_name text,
  wish_id bigint
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
