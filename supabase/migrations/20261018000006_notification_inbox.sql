-- The in-app Notifications screen: every birthday reminder and wish
-- notification the outbox queued for you, newest first, with an unread count
-- for the bell.
--
-- It reads the outbox itself rather than a second copy. A row exists there
-- the moment the reminder or wish is queued, whether or not a push ever
-- reaches a phone -- so the screen still shows everything when pushes are
-- blocked on the device, which is exactly when it is needed most.
--
-- The outbox stays in `private`, unreachable through the API. These three
-- functions are the only way in, each scoped to auth.uid(): nobody can list,
-- count or mark anyone else's notifications.

-- When the recipient opened the Notifications screen with this row on it.
-- Distinct from sent_at, which records the push, not the person.
alter table private.notification_outbox add column seen_at timestamptz;

-- The name a recipient sees for a wish's author: the author's people row
-- when the recipient can see it, otherwise the name the author chose on
-- their profile -- feed_page's rule (20261018000002), restated for an
-- explicit recipient because the drain has no auth.uid(). The batch
-- (20261018000003) inlines the same three branches; it is left as is rather
-- than dropped and recreated a third time.
create or replace function private.author_name_for(
  p_recipient uuid,
  p_recipient_person bigint,
  p_author uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when ap.id is not null and (
      ap.id = p_recipient_person
      or exists (
        select 1 from public.celebrations c
        where c.person_id = ap.id and c.celebrator_profile_id = p_recipient
      )
      or exists (
        select 1 from public.celebrations c
        where c.person_id = p_recipient_person
          and c.celebrator_profile_id = ap.profile_id
      )
    ) then ap.display_name
    else apr.display_name
  end
  from public.profiles apr
  left join public.people ap on ap.profile_id = apr.id
  where apr.id = p_author;
$$;

revoke execute on function private.author_name_for(uuid, bigint, uuid)
  from public, anon, authenticated;

create or replace function public.my_notifications(
  p_before timestamptz default null,
  p_limit int default 50
)
returns table (
  id bigint,
  kind text,
  created_at timestamptz,
  seen boolean,
  person_id bigint,
  wish_id bigint,
  subject_name text,
  author_name text,
  offset_days smallint,
  occasion_date date
)
language sql
stable
security definer
set search_path = ''
as $$
  select o.id, o.kind, o.created_at, o.seen_at is not null,
         o.subject_person_id, o.wish_id, p.display_name,
         case when o.kind = 'wish' then
           private.author_name_for(
             o.recipient_profile_id, o.subject_person_id, w.author_profile_id)
         end,
         o.offset_days, o.occasion_date
  from private.notification_outbox o
  join public.people p on p.id = o.subject_person_id
  left join public.wishes w on w.id = o.wish_id
  where o.recipient_profile_id = (select auth.uid())
    and (p_before is null or o.created_at < p_before)
  order by o.created_at desc, o.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

revoke execute on function public.my_notifications(timestamptz, int)
  from public, anon;
grant execute on function public.my_notifications(timestamptz, int)
  to authenticated;

create or replace function public.my_unseen_notification_count()
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
  from private.notification_outbox o
  where o.recipient_profile_id = (select auth.uid())
    and o.seen_at is null;
$$;

revoke execute on function public.my_unseen_notification_count()
  from public, anon;
grant execute on function public.my_unseen_notification_count()
  to authenticated;

-- All at once, when the screen opens: the bell counts what you have not
-- looked at, and opening the list is looking at all of it.
create or replace function public.mark_notifications_seen()
returns int
language sql
security definer
set search_path = ''
as $$
  with seen as (
    update private.notification_outbox
    set seen_at = now()
    where recipient_profile_id = (select auth.uid())
      and seen_at is null
    returning 1
  )
  select count(*)::int from seen;
$$;

revoke execute on function public.mark_notifications_seen()
  from public, anon;
grant execute on function public.mark_notifications_seen() to authenticated;
