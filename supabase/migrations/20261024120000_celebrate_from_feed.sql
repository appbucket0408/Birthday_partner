-- Celebrate a member found on the public feed, and tell anyone who is
-- celebrated by hand ("X started celebrating you").
--
-- Errors (docs/db.md: unassigned class 45):
--   45007  that person is not on the app, or not on the public feed.
--   45008  daily limit of new people celebrated from the feed reached.

-- ------------------------------------------------------------- discovery

-- A member the caller may reach without a connection: someone who appears on
-- the public feed. Keeps sequential person ids from being walked.
create function private.is_discoverable(p_person_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.people p
    where p.id = p_person_id
      and p.profile_id is not null
      and exists (
        select 1
        from public.wishes w
        join public.people sp on sp.id = w.subject_person_id
        where sp.profile_id is not null
          and (w.subject_person_id = p.id or w.author_profile_id = p.profile_id)
      )
  );
$$;

revoke execute on function private.is_discoverable(bigint)
  from public, anon, authenticated;

-- What a stranger may see before celebrating: no birthday.
create function public.member_preview(p_person_id bigint)
returns table (id bigint, display_name text, celebrator_count int)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    pr.display_name,
    (select count(*)::int from public.celebrations c where c.person_id = p.id)
  from public.people p
  join public.profiles pr on pr.id = p.profile_id
  where (select auth.uid()) is not null
    and p.id = p_person_id
    and private.is_discoverable(p.id);
$$;

revoke execute on function public.member_preview(bigint) from public, anon;
grant execute on function public.member_preview(bigint) to authenticated;

-- ------------------------------------------------------------- celebrate

create function public.rpc_celebrate(p_person_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.celebrations c
    where c.celebrator_profile_id = v_me and c.person_id = p_person_id
  ) then
    return p_person_id;
  end if;

  if not (
    private.can_see_person(p_person_id)
    or private.is_discoverable(p_person_id)
  ) then
    raise exception 'that person is not on the app' using errcode = '45007';
  end if;

  if (
    select count(*) from public.celebrations c
    where c.celebrator_profile_id = v_me
      and c.source = 'search'
      and c.created_at > now() - interval '1 day'
  ) >= 30 then
    raise exception 'daily celebrate limit reached' using errcode = '45008';
  end if;

  -- celebrations_guard still refuses self and anyone who blocked the caller.
  insert into public.celebrations (celebrator_profile_id, person_id, source)
  values (v_me, p_person_id, 'search')
  on conflict on constraint celebrations_unique_edge do nothing;

  return p_person_id;
end;
$$;

revoke execute on function public.rpc_celebrate(bigint) from public, anon;
grant execute on function public.rpc_celebrate(bigint) to authenticated;

-- ------------------------------------------------------------- notify

alter table private.notification_outbox
  add column celebration_id bigint
    references public.celebrations (id) on delete cascade;

alter table private.notification_outbox
  drop constraint notification_outbox_kind_valid,
  drop constraint notification_outbox_kind_shape;

alter table private.notification_outbox
  add constraint notification_outbox_kind_valid
    check (kind in ('reminder', 'wish', 'celebration')),
  add constraint notification_outbox_kind_shape check (
    (kind = 'reminder'
      and offset_days in (7, 1, 0)
      and occasion_date is not null
      and wish_id is null
      and celebration_id is null)
    or
    (kind = 'wish'
      and wish_id is not null
      and celebration_id is null
      and offset_days is null
      and occasion_date is null)
    or
    (kind = 'celebration'
      and celebration_id is not null
      and wish_id is null
      and offset_days is null
      and occasion_date is null)
  );

-- One notification per edge; also the index the celebration_id FK needs.
create unique index notification_outbox_one_per_celebration
  on private.notification_outbox (celebration_id)
  where celebration_id is not null;

-- Subject is the celebrator's own person row, so the inbox, the push and the
-- tap all show and open them -- where Celebrate back waits.
create function private.enqueue_celebration_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_celebrator_person bigint;
begin
  -- Contact imports would flood people; only someone choosing you counts.
  if new.source not in ('manual', 'search') then
    return null;
  end if;

  select p.profile_id into v_recipient
  from public.people p where p.id = new.person_id;
  if v_recipient is null or v_recipient = new.celebrator_profile_id then
    return null;
  end if;

  select p.id into v_celebrator_person
  from public.people p where p.profile_id = new.celebrator_profile_id;
  if v_celebrator_person is null then
    return null;
  end if;

  -- Same switch as wishes: both are "someone reached out to you".
  if not exists (
    select 1 from public.profiles r
    where r.id = v_recipient and r.wish_notifications_enabled
  ) then
    return null;
  end if;

  if exists (
    select 1 from public.blocks b
    where b.blocker_profile_id = v_recipient
      and b.blocked_profile_id = new.celebrator_profile_id
  ) then
    return null;
  end if;

  insert into private.notification_outbox (
    recipient_profile_id, subject_person_id, kind, celebration_id
  ) values (
    v_recipient, v_celebrator_person, 'celebration', new.id
  )
  on conflict (celebration_id) where celebration_id is not null do nothing;

  return null;
end;
$$;

revoke execute on function private.enqueue_celebration_notification()
  from public, anon, authenticated;

create trigger celebrations_enqueue_notification
  after insert on public.celebrations
  for each row execute function private.enqueue_celebration_notification();

-- ------------------------------------------------------------- feed

-- Adds author_person_id so an author's name can open their page too.
-- Same rows and visibility as 20261018000002; only the new column differs.
drop function public.feed_page(timestamptz, int);

create function public.feed_page(
  p_before timestamptz default null,
  p_limit int default 20
)
returns table (
  id bigint,
  author_profile_id uuid,
  subject_person_id bigint,
  body text,
  kind text,
  occasion_year int,
  created_at timestamptz,
  photo_path text,
  author_name text,
  subject_name text,
  can_open_subject boolean,
  author_person_id bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    w.id,
    w.author_profile_id,
    w.subject_person_id,
    w.body,
    w.kind,
    w.occasion_year,
    w.created_at,
    w.photo_path,
    case
      when ap.id is not null and private.can_see_person(ap.id)
        then ap.display_name
      else apr.display_name
    end,
    case
      when private.can_see_person(sp.id) then sp.display_name
      else spr.display_name
    end,
    private.can_see_person(sp.id),
    ap.id
  from public.wishes w
  join public.people sp on sp.id = w.subject_person_id
  left join public.profiles spr on spr.id = sp.profile_id
  left join public.people ap on ap.profile_id = w.author_profile_id
  left join public.profiles apr on apr.id = w.author_profile_id
  where (select auth.uid()) is not null
    and (p_before is null or w.created_at < p_before)
    and (
      sp.profile_id is not null
      or w.author_profile_id = (select auth.uid())
      or private.can_see_person(sp.id)
    )
  order by w.created_at desc, w.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.feed_page(timestamptz, int)
  from public, anon;
grant execute on function public.feed_page(timestamptz, int) to authenticated;
