-- Three new outbox kinds, all on the existing pipeline:
--   joined  -> each celebrator of a new member: "Priya joined. Birthday: 4 March"
--   welcome -> the new member: "3 people already celebrate you"
--   wall    -> a member 7 days before their own birthday: share your wall

-- ------------------------------------------------------------- outbox

-- welcome's count, snapshotted when queued.
alter table private.notification_outbox add column subject_count int;

alter table private.notification_outbox
  drop constraint notification_outbox_kind_valid,
  drop constraint notification_outbox_kind_shape;

alter table private.notification_outbox
  add constraint notification_outbox_kind_valid
    check (kind in ('reminder', 'wish', 'celebration', 'joined', 'welcome', 'wall')),
  add constraint notification_outbox_kind_shape check (
    (kind = 'reminder'
      and offset_days in (7, 1, 0)
      and occasion_date is not null
      and wish_id is null
      and celebration_id is null
      and subject_count is null)
    or
    (kind = 'wish'
      and wish_id is not null
      and celebration_id is null
      and offset_days is null
      and occasion_date is null
      and subject_count is null)
    or
    (kind = 'celebration'
      and celebration_id is not null
      and wish_id is null
      and offset_days is null
      and occasion_date is null
      and subject_count is null)
    or
    (kind = 'joined'
      and occasion_date is not null
      and offset_days is null
      and wish_id is null
      and celebration_id is null
      and subject_count is null)
    or
    (kind = 'welcome'
      and subject_count > 0
      and occasion_date is null
      and offset_days is null
      and wish_id is null
      and celebration_id is null)
    or
    (kind = 'wall'
      and offset_days = 7
      and occasion_date is not null
      and wish_id is null
      and celebration_id is null
      and subject_count is null)
  );

create unique index notification_outbox_one_joined
  on private.notification_outbox (recipient_profile_id, subject_person_id)
  where kind = 'joined';

create unique index notification_outbox_one_welcome
  on private.notification_outbox (recipient_profile_id)
  where kind = 'welcome';

-- ------------------------------------------------------------- helpers

-- Feb 29 falls on Feb 28 in non-leap years, as in enqueue_reminders.
create function private.next_birthday(p_month smallint, p_day smallint, p_from date)
returns date
language sql
immutable
set search_path = ''
as $$
  with y(yr) as (values (extract(year from p_from)::int), (extract(year from p_from)::int + 1)),
  d as (
    select make_date(
      yr, p_month,
      case
        when p_month = 2 and p_day = 29
          and not (yr % 4 = 0 and (yr % 100 <> 0 or yr % 400 = 0))
        then 28
        else p_day
      end
    ) as dt
    from y
  )
  select min(dt) from d where dt >= p_from;
$$;

revoke execute on function private.next_birthday(smallint, smallint, date)
  from public, anon, authenticated;

-- ------------------------------------------------------------- joined + welcome

-- Fires once, when sign-up sets the birthday for the first time.
create function private.enqueue_join_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person bigint;
  v_count int;
begin
  select p.id into v_person from public.people p where p.profile_id = new.id;
  if v_person is null then
    return null;
  end if;

  insert into private.notification_outbox (
    recipient_profile_id, subject_person_id, kind, occasion_date
  )
  select c.celebrator_profile_id, v_person, 'joined',
         private.next_birthday(new.birth_month, new.birth_day, current_date)
  from public.celebrations c
  join public.profiles r on r.id = c.celebrator_profile_id
  where c.person_id = v_person
    and c.celebrator_profile_id <> new.id
    and r.reminders_enabled
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_profile_id = c.celebrator_profile_id and b.blocked_profile_id = new.id)
         or (b.blocker_profile_id = new.id and b.blocked_profile_id = c.celebrator_profile_id)
    )
  on conflict (recipient_profile_id, subject_person_id) where kind = 'joined' do nothing;

  if new.wish_notifications_enabled then
    select count(*)::int into v_count
    from public.celebrations c
    where c.person_id = v_person
      and c.celebrator_profile_id <> new.id
      and not exists (
        select 1 from public.blocks b
        where b.blocker_profile_id = new.id
          and b.blocked_profile_id = c.celebrator_profile_id
      );

    if v_count > 0 then
      insert into private.notification_outbox (
        recipient_profile_id, subject_person_id, kind, subject_count
      ) values (new.id, v_person, 'welcome', v_count)
      on conflict (recipient_profile_id) where kind = 'welcome' do nothing;
    end if;
  end if;

  return null;
end;
$$;

revoke execute on function private.enqueue_join_notifications()
  from public, anon, authenticated;

create trigger profiles_enqueue_join_notifications
  after update of birth_month on public.profiles
  for each row
  when (old.birth_month is null and new.birth_month is not null)
  execute function private.enqueue_join_notifications();

-- ------------------------------------------------------------- wall

create function private.enqueue_wall_prompts(p_today date default current_date)
returns int
language sql
security definer
set search_path = ''
as $$
  with due as (
    insert into private.notification_outbox (
      recipient_profile_id, subject_person_id, kind, offset_days, occasion_date
    )
    select r.id, p.id, 'wall', 7, p_today + 7
    from public.profiles r
    join public.people p on p.profile_id = r.id
    where r.birth_month is not null
      and r.reminders_enabled
      and private.next_birthday(r.birth_month, r.birth_day, p_today) = p_today + 7
    on conflict on constraint notification_outbox_once do nothing
    returning 1
  )
  select count(*)::int from due;
$$;

revoke execute on function private.enqueue_wall_prompts(date)
  from public, anon, authenticated;

select cron.unschedule('wall-prompt-fanout')
where exists (select 1 from cron.job where jobname = 'wall-prompt-fanout');

-- Same time as birthday-reminder-fanout (08:30 IST).
select cron.schedule(
  'wall-prompt-fanout',
  '0 3 * * *',
  $$ select private.enqueue_wall_prompts(); $$
);

-- ------------------------------------------------------------- the batch

-- Same as 20261018000003 plus subject_count, appended. Drop takes the ACL,
-- so the grants below are mandatory (32_batch_person_id.test.sql).
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
  wish_id bigint,
  subject_count int
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
              o.offset_days, o.occasion_date, o.kind, o.wish_id,
              o.subject_count
  )
  select cl.id, d.token, d.platform, p.display_name, cl.subject_person_id,
         cl.offset_days, cl.occasion_date, cl.kind,
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
         cl.wish_id,
         cl.subject_count
  from claimed cl
  join public.people p on p.id = cl.subject_person_id
  left join public.wishes w on w.id = cl.wish_id
  left join public.people ap on ap.profile_id = w.author_profile_id
  left join public.profiles apr on apr.id = w.author_profile_id
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
  wish_id bigint,
  subject_count int
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

-- ------------------------------------------------------------- the inbox

-- Same as 20261018000006 plus subject_count, appended.
drop function public.my_notifications(timestamptz, int);

create function public.my_notifications(
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
  occasion_date date,
  subject_count int
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
         o.offset_days, o.occasion_date, o.subject_count
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
