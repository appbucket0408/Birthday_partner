create or replace function private.is_blocked_with(p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_profile is not null and exists (
    select 1 from public.blocks b
    where (b.blocker_profile_id = (select auth.uid())
           and b.blocked_profile_id = p_profile)
       or (b.blocker_profile_id = p_profile
           and b.blocked_profile_id = (select auth.uid()))
  );
$$;

revoke execute on function private.is_blocked_with(uuid) from public, anon;
-- Called by wishes_select_visible and wishes_insert_own as the signed-in
-- user, so it joins the policy-helper allowlist in 01_private.test.sql.
grant execute on function private.is_blocked_with(uuid) to authenticated;

-- ------------------------------------------------------------ block effects

create or replace function private.apply_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.celebrations c
  using public.people p
  where p.id = c.person_id
    and (
      (c.celebrator_profile_id = new.blocker_profile_id
        and p.profile_id = new.blocked_profile_id)
      or (c.celebrator_profile_id = new.blocked_profile_id
        and p.profile_id = new.blocker_profile_id)
    );

  -- Reminders about each other, and wish notifications from one to the
  -- other, whether or not they were pushed yet: the Notifications screen
  -- reads this table, so a sent row is still on screen.
  delete from private.notification_outbox o
  using public.people p
  where p.id = o.subject_person_id
    and (
      (o.recipient_profile_id = new.blocker_profile_id
        and p.profile_id = new.blocked_profile_id)
      or (o.recipient_profile_id = new.blocked_profile_id
        and p.profile_id = new.blocker_profile_id)
    );

  delete from private.notification_outbox o
  using public.wishes w
  where w.id = o.wish_id
    and (
      (o.recipient_profile_id = new.blocker_profile_id
        and w.author_profile_id = new.blocked_profile_id)
      or (o.recipient_profile_id = new.blocked_profile_id
        and w.author_profile_id = new.blocker_profile_id)
    );

  return new;
end;
$$;

revoke execute on function private.apply_block() from public, anon, authenticated;

create trigger blocks_apply
  after insert on public.blocks
  for each row execute function private.apply_block();

-- Same function as M0's, plus the blocker -> blocked direction. Without it
-- the blocker could re-celebrate the person they blocked and wish them,
-- which reaches the blocked person's wall the block was meant to close.
create or replace function private.guard_celebration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target_profile uuid;
begin
  if new.person_id = private.my_person_id() then
    raise exception 'you cannot celebrate yourself';
  end if;

  select p.profile_id into v_target_profile
  from public.people p where p.id = new.person_id;

  if v_target_profile is not null and exists (
    select 1 from public.blocks b
    where b.blocker_profile_id = v_target_profile
      and b.blocked_profile_id = new.celebrator_profile_id
  ) then
    raise exception 'this person has blocked you';
  end if;

  if v_target_profile is not null and exists (
    select 1 from public.blocks b
    where b.blocker_profile_id = new.celebrator_profile_id
      and b.blocked_profile_id = v_target_profile
  ) then
    raise exception 'you have blocked this person';
  end if;

  return new;
end;
$$;

-- ------------------------------------------------------------------ reports

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_profile_id uuid not null references public.profiles (id) on delete cascade,
  -- Null for a report about a person rather than one post. Set null, not
  -- cascade, when staff remove the wish: the report is the record of why.
  wish_id bigint references public.wishes (id) on delete set null,
  reported_profile_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  note text,
  -- Copied from the wish at report time, so removing the wish keeps the
  -- evidence. Null for a person report.
  wish_body text,
  wish_photo_path text,
  status text not null default 'open',
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint reports_reason_valid
    check (reason in ('spam', 'harassment', 'inappropriate', 'hate', 'other')),
  constraint reports_note_length check (note is null or length(note) <= 500),
  constraint reports_status_valid check (status in ('open', 'removed', 'dismissed')),
  constraint reports_not_self check (reporter_profile_id <> reported_profile_id)
);

-- One report per reporter per post, and one open report per reporter per
-- person: tapping Report twice is one signal, not two.
create unique index reports_once_per_wish
  on public.reports (reporter_profile_id, wish_id)
  where wish_id is not null;
create unique index reports_once_per_person
  on public.reports (reporter_profile_id, reported_profile_id)
  where wish_id is null and status = 'open';

create index reports_wish_id_idx on public.reports (wish_id);
create index reports_reported_profile_id_idx on public.reports (reported_profile_id);
create index reports_reviewed_by_idx on public.reports (reviewed_by);
create index reports_open_idx on public.reports (created_at) where status = 'open';

alter table public.reports enable row level security;

-- Staff read the queue directly; nobody writes except through the
-- functions below. A reporter cannot read reports at all, not even their
-- own: there is nothing in one they need back.
create policy reports_staff_select
  on public.reports
  for select
  to authenticated
  using ((select private.is_staff()));

revoke insert, update, delete on public.reports from anon, authenticated;

-- Whether the caller has reported this wish. Used by the wall and feed
-- filters below; definer because the reporter cannot read reports.
create or replace function private.i_reported_wish(p_wish_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.reports r
    where r.wish_id = p_wish_id
      and r.reporter_profile_id = (select auth.uid())
  );
$$;

revoke execute on function private.i_reported_wish(bigint) from public, anon;
-- Called by wishes_select_visible as the signed-in user.
grant execute on function private.i_reported_wish(bigint) to authenticated;

-- Report a wish the caller can currently see: on a wall they can open, or
-- in their public feed. Anything else is "not found", never a hint that a
-- wish with that id exists.
create or replace function public.rpc_report_wish(
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
  v_subject_profile uuid;
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select w.* into v_wish from public.wishes w where w.id = p_wish_id;
  select p.profile_id into v_subject_profile
  from public.people p where p.id = v_wish.subject_person_id;

  -- feed_page's visibility rule: a member's wall is public, anyone else's
  -- only inside their graph.
  if v_wish.id is null
     or v_wish.author_profile_id = v_me
     or not (
       v_subject_profile is not null
       or private.can_see_person(v_wish.subject_person_id)
     ) then
    raise exception 'wish not found' using errcode = 'P0002';
  end if;

  insert into public.reports (
    reporter_profile_id, wish_id, reported_profile_id, reason, note,
    wish_body, wish_photo_path
  ) values (
    v_me, v_wish.id, v_wish.author_profile_id, p_reason,
    nullif(btrim(p_note), ''), v_wish.body, v_wish.photo_path
  )
  on conflict (reporter_profile_id, wish_id) where wish_id is not null
  do nothing;
end;
$$;

revoke execute on function public.rpc_report_wish(bigint, text, text) from public, anon;
grant execute on function public.rpc_report_wish(bigint, text, text) to authenticated;

-- Report a person by profile. Only someone the caller can actually reach:
-- a person they can see, or the author of a wish they can see.
create or replace function public.rpc_report_user(
  p_profile_id uuid,
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
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  if p_profile_id is null or p_profile_id = v_me or not exists (
    select 1 from public.profiles pr where pr.id = p_profile_id
  ) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  insert into public.reports (reporter_profile_id, reported_profile_id, reason, note)
  values (v_me, p_profile_id, p_reason, nullif(btrim(p_note), ''))
  on conflict (reporter_profile_id, reported_profile_id)
    where wish_id is null and status = 'open'
  do nothing;
end;
$$;

revoke execute on function public.rpc_report_user(uuid, text, text) from public, anon;
grant execute on function public.rpc_report_user(uuid, text, text) to authenticated;

create or replace function public.my_blocked_users()
returns table (profile_id uuid, display_name text, blocked_at timestamptz)
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

revoke execute on function public.my_blocked_users() from public, anon;
grant execute on function public.my_blocked_users() to authenticated;

-- ------------------------------------------------------------ wall + feed

drop policy wishes_select_visible on public.wishes;

create policy wishes_select_visible
  on public.wishes
  for select
  to authenticated
  using (
    author_profile_id = (select auth.uid())
    or (
      (select private.can_see_person(wishes.subject_person_id))
      and not (select private.is_blocked_with(wishes.author_profile_id))
      and not (select private.i_reported_wish(wishes.id))
    )
  );

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
    and not (select private.is_blocked_with(
      (select p.profile_id from public.people p
        where p.id = wishes.subject_person_id)
    ))
  );

create or replace function public.feed_page(
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
  can_open_subject boolean
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
    private.can_see_person(sp.id)
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
    -- A block hides both the posts they write and the posts about them.
    and not private.is_blocked_with(w.author_profile_id)
    and not private.is_blocked_with(sp.profile_id)
    and not private.i_reported_wish(w.id)
  order by w.created_at desc, w.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function public.ops_open_reports()
returns table (
  id bigint,
  created_at timestamptz,
  reason text,
  note text,
  wish_id bigint,
  wish_body text,
  wish_photo_path text,
  wish_still_exists boolean,
  reported_profile_id uuid,
  reported_name text,
  reporter_name text,
  report_count int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_staff() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  return query
  select
    r.id,
    r.created_at,
    r.reason,
    r.note,
    r.wish_id,
    coalesce(w.body, r.wish_body),
    coalesce(w.photo_path, r.wish_photo_path),
    w.id is not null,
    r.reported_profile_id,
    rp.display_name,
    rr.display_name,
    (select count(*)::int from public.reports r2
      where r2.status = 'open'
        and r2.reported_profile_id = r.reported_profile_id
        and r2.wish_id is not distinct from r.wish_id)
  from public.reports r
  left join public.wishes w on w.id = r.wish_id
  join public.profiles rp on rp.id = r.reported_profile_id
  join public.profiles rr on rr.id = r.reporter_profile_id
  where r.status = 'open'
  order by r.created_at desc, r.id desc;
end;
$$;

revoke execute on function public.ops_open_reports() from public, anon;
grant execute on function public.ops_open_reports() to authenticated;

-- Close a report. 'remove' deletes the reported wish and closes every open
-- report about it; 'dismiss' closes every open report on the same target.
-- Returns the removed wish's photo path, if any, for the console to delete
-- from Storage -- SQL cannot remove a Storage object itself.
create or replace function public.ops_resolve_report(
  p_report_id bigint,
  p_action text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.reports%rowtype;
  v_photo text;
begin
  if not private.is_staff() then
    raise exception 'not authorised' using errcode = '42501';
  end if;
  if p_action not in ('remove', 'dismiss') then
    raise exception 'unknown action %', p_action using errcode = '22023';
  end if;

  select * into v_report from public.reports where id = p_report_id;
  if v_report.id is null then
    raise exception 'report not found' using errcode = 'P0002';
  end if;
  if p_action = 'remove' and v_report.wish_id is null then
    raise exception 'a person report has no post to remove' using errcode = '22023';
  end if;

  update public.reports
  set status = case p_action when 'remove' then 'removed' else 'dismissed' end,
      reviewed_by = (select auth.uid()),
      reviewed_at = now()
  where status = 'open'
    and reported_profile_id = v_report.reported_profile_id
    and wish_id is not distinct from v_report.wish_id;

  if p_action = 'remove' then
    delete from public.wishes where id = v_report.wish_id
    returning photo_path into v_photo;
  end if;

  return v_photo;
end;
$$;

revoke execute on function public.ops_resolve_report(bigint, text) from public, anon;
grant execute on function public.ops_resolve_report(bigint, text) to authenticated;

-- Staff need to see a reported photo to judge it, and to delete it once the
-- wish is removed. Paths are '<author uid>/<millis>.<ext>'.
create policy wish_photos_select_staff
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'wish_photos' and (select private.is_staff()));

create policy wish_photos_delete_staff
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'wish_photos' and (select private.is_staff()));
