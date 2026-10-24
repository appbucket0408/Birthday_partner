-- UGC moderation: report a wish or a person (queued for staff review), block
-- a person (hides their wishes both ways, stops new ones), and let a wall
-- owner delete any wish on their wall.
--
-- Errors (docs/db.md: unassigned class 45):
--   45009  daily report limit reached.
--   45010  that wish or person cannot be reported by the caller.

-- ------------------------------------------------------------- blocks

create function private.is_blocked_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks b
    where (b.blocker_profile_id = (select auth.uid()) and b.blocked_profile_id = p_other)
       or (b.blocker_profile_id = p_other and b.blocked_profile_id = (select auth.uid()))
  );
$$;

revoke execute on function private.is_blocked_with(uuid) from public, anon;
-- Policies call it as the signed-in user.
grant execute on function private.is_blocked_with(uuid) to authenticated;

-- Blocked list with names: profiles are owner-only, so names come from here.
create function public.my_blocked_people()
returns table (profile_id uuid, display_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select b.blocked_profile_id, pr.display_name, b.created_at
  from public.blocks b
  join public.profiles pr on pr.id = b.blocked_profile_id
  where b.blocker_profile_id = (select auth.uid())
  order by b.created_at desc;
$$;

revoke execute on function public.my_blocked_people() from public, anon;
grant execute on function public.my_blocked_people() to authenticated;

-- ------------------------------------------------------------- wishes RLS

-- Own wishes stay visible to their author; others hide across a block.
drop policy wishes_select_visible on public.wishes;

create policy wishes_select_visible
  on public.wishes
  for select
  to authenticated
  using (
    author_profile_id = (select auth.uid())
    or (
      (select private.can_see_person(wishes.subject_person_id))
      and not private.is_blocked_with(wishes.author_profile_id)
    )
  );

-- A block keeps old celebration edges, so the edge alone no longer suffices.
drop policy wishes_insert_own on public.wishes;

create policy wishes_insert_own
  on public.wishes
  for insert
  to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and exists (
      select 1 from public.celebrations c
      where c.person_id = wishes.subject_person_id
        and c.celebrator_profile_id = (select auth.uid())
    )
    and not exists (
      select 1
      from public.people sp
      join public.blocks b on b.blocker_profile_id = sp.profile_id
      where sp.id = wishes.subject_person_id
        and b.blocked_profile_id = (select auth.uid())
    )
  );

create policy wishes_delete_on_own_wall
  on public.wishes
  for delete
  to authenticated
  using (subject_person_id = (select private.my_person_id()));

-- ------------------------------------------------------------- reports

-- Staff review queue. No client policies: written only by the rpcs below,
-- read by the admin panel with elevated access.
create table public.reports (
  id bigint generated always as identity primary key,
  reporter_profile_id uuid not null references public.profiles (id) on delete cascade,
  reported_profile_id uuid references public.profiles (id) on delete set null,
  target text not null,
  wish_id bigint references public.wishes (id) on delete set null,
  reason text not null,
  note text,
  -- Snapshot, so the report survives the wish being deleted.
  wish_body text,
  wish_photo_path text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint reports_target_valid check (target in ('wish', 'person')),
  constraint reports_reason_valid
    check (reason in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other')),
  constraint reports_status_valid
    check (status in ('pending', 'removed', 'dismissed')),
  constraint reports_note_length check (note is null or length(note) <= 500)
);

alter table public.reports enable row level security;
revoke all on table public.reports from anon, authenticated;

create index reports_status_created_idx on public.reports (status, created_at);
create index reports_reporter_created_idx on public.reports (reporter_profile_id, created_at);
create index reports_reported_profile_idx on public.reports (reported_profile_id);
create index reports_wish_idx on public.reports (wish_id);

-- One open report per reporter per wish / per person. Keyed on target, not
-- wish_id, so a deleted wish (wish_id -> null) can't collide with a person report.
create unique index reports_one_open_per_wish
  on public.reports (reporter_profile_id, wish_id)
  where status = 'pending' and target = 'wish';
create unique index reports_one_open_per_person
  on public.reports (reporter_profile_id, reported_profile_id)
  where status = 'pending' and target = 'person';

create function private.assert_report_quota()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
    select count(*) from public.reports r
    where r.reporter_profile_id = (select auth.uid())
      and r.created_at > now() - interval '1 day'
  ) >= 20 then
    raise exception 'daily report limit reached' using errcode = '45009';
  end if;
end;
$$;

revoke execute on function private.assert_report_quota()
  from public, anon, authenticated;

-- Visibility mirrors feed_page: a claimed wall, own wish, or a visible subject.
create function public.rpc_report_wish(
  p_wish_id bigint,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_wish public.wishes%rowtype;
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select w.* into v_wish
  from public.wishes w
  join public.people sp on sp.id = w.subject_person_id
  where w.id = p_wish_id
    and w.author_profile_id <> v_me
    and (sp.profile_id is not null or private.can_see_person(sp.id));
  if not found then
    raise exception 'that wish cannot be reported' using errcode = '45010';
  end if;

  perform private.assert_report_quota();

  insert into public.reports (
    reporter_profile_id, reported_profile_id, target, wish_id, reason, note,
    wish_body, wish_photo_path
  ) values (
    v_me, v_wish.author_profile_id, 'wish', v_wish.id, p_reason, nullif(btrim(p_note), ''),
    v_wish.body, v_wish.photo_path
  )
  on conflict (reporter_profile_id, wish_id)
    where status = 'pending' and target = 'wish'
    do nothing;
end;
$$;

revoke execute on function public.rpc_report_wish(bigint, text, text) from public, anon;
grant execute on function public.rpc_report_wish(bigint, text, text) to authenticated;

create function public.rpc_report_person(
  p_person_id bigint,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_profile uuid;
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select p.profile_id into v_profile
  from public.people p
  where p.id = p_person_id
    and p.profile_id is not null
    and p.profile_id <> v_me
    and (private.can_see_person(p.id) or private.is_discoverable(p.id));
  if v_profile is null then
    raise exception 'that person cannot be reported' using errcode = '45010';
  end if;

  perform private.assert_report_quota();

  insert into public.reports (reporter_profile_id, reported_profile_id, target, reason, note)
  values (v_me, v_profile, 'person', p_reason, nullif(btrim(p_note), ''))
  on conflict (reporter_profile_id, reported_profile_id)
    where status = 'pending' and target = 'person'
    do nothing;
end;
$$;

revoke execute on function public.rpc_report_person(bigint, text, text) from public, anon;
grant execute on function public.rpc_report_person(bigint, text, text) to authenticated;

-- ------------------------------------------------------------- feed

-- Same rows as 20261024120000 minus blocked authors/walls, plus can_delete.
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
  author_person_id bigint,
  can_delete boolean
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
    ap.id,
    sp.profile_id = (select auth.uid())
      or (w.author_profile_id = (select auth.uid()) and w.kind = 'message')
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
    and not private.is_blocked_with(w.author_profile_id)
    and (sp.profile_id is null or not private.is_blocked_with(sp.profile_id))
  order by w.created_at desc, w.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.feed_page(timestamptz, int)
  from public, anon;
grant execute on function public.feed_page(timestamptz, int) to authenticated;
