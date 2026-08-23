-- Phone numbers that must never be imported again (spec §6 rule 6).
create table private.suppressions (
  phone_e164_hash text primary key,
  created_at timestamptz not null default now()
);

alter table private.suppressions enable row level security;
-- No policies, and the schema is not API-exposed: server-side access only.

create table public.people (
  id bigint generated always as identity primary key,
  phone_e164_hash text not null unique,
  profile_id uuid unique references public.profiles (id) on delete set null,
  display_name text not null,
  birthday date,
  created_at timestamptz not null default now(),
  constraint people_phone_hash_format check (phone_e164_hash ~ '^[0-9a-f]{64}$'),
  constraint people_birthday_sane check (
    birthday is null
    or (birthday > date '1900-01-01' and birthday <= current_date)
  )
);

create index people_profile_id_idx on public.people (profile_id);

alter table public.people enable row level security;

create table public.celebrations (
  id bigint generated always as identity primary key,
  celebrator_profile_id uuid not null references public.profiles (id) on delete cascade,
  person_id bigint not null references public.people (id) on delete cascade,
  nickname text,
  source text not null,
  created_at timestamptz not null default now(),
  constraint celebrations_source_valid check (source in ('contacts', 'search', 'manual')),
  constraint celebrations_unique_edge unique (celebrator_profile_id, person_id)
);

-- The unique constraint indexes (celebrator, person); person_id needs its own
-- index for the reverse lookup ("who celebrates me") and for cascades.
create index celebrations_person_id_idx on public.celebrations (person_id);

alter table public.celebrations enable row level security;

create table public.blocks (
  id bigint generated always as identity primary key,
  blocker_profile_id uuid not null references public.profiles (id) on delete cascade,
  blocked_profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocks_unique_pair unique (blocker_profile_id, blocked_profile_id),
  constraint blocks_not_self check (blocker_profile_id <> blocked_profile_id)
);

create index blocks_blocked_profile_id_idx on public.blocks (blocked_profile_id);

alter table public.blocks enable row level security;

-- ---------------------------------------------------------------- helpers

create or replace function private.my_person_id()
returns bigint
language sql
security definer
set search_path = ''
stable
as $$
  select p.id from public.people p where p.profile_id = (select auth.uid());
$$;

-- A person is visible if they are me, if I celebrate them, or if they
-- celebrate me. Nothing else. This is what keeps a stranger's birthday
-- undiscoverable (spec §6 rule 7).
create or replace function private.can_see_person(p_person_id bigint)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select
    p_person_id = private.my_person_id()
    or exists (
      select 1 from public.celebrations c
      where c.person_id = p_person_id
        and c.celebrator_profile_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.celebrations c
      join public.people p on p.profile_id = c.celebrator_profile_id
      where c.person_id = private.my_person_id()
        and p.id = p_person_id
    );
$$;

revoke execute on function private.my_person_id() from public, anon;
revoke execute on function private.can_see_person(bigint) from public, anon;

-- R16: the revokes above are not enough on their own — same trap as R12 in
-- 20260822000002. `authenticated` held EXECUTE only through the PUBLIC grant,
-- so revoking PUBLIC takes it away too, and people_select_visible then raises
-- "permission denied for function can_see_person" for every signed-in user
-- instead of filtering rows. These two are the only private helpers a policy
-- calls from this migration, so they are the only ones granted back.
grant execute on function private.my_person_id() to authenticated;
grant execute on function private.can_see_person(bigint) to authenticated;

-- ------------------------------------------------------- write functions

-- Resolve a phone number to a person, creating the row if needed. Returns
-- null when the number is suppressed, which callers must treat as "skip this
-- contact", not as an error.
create or replace function private.upsert_person(
  p_phone text,
  p_display_name text,
  p_birthday date default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := private.phone_hash(p_phone);
  v_id bigint;
begin
  if exists (select 1 from private.suppressions s where s.phone_e164_hash = v_hash) then
    return null;
  end if;

  select p.id into v_id from public.people p where p.phone_e164_hash = v_hash;

  if v_id is not null then
    -- Never overwrite a name or birthday the person set themselves; only fill
    -- blanks left by earlier imports.
    update public.people
    set birthday = coalesce(birthday, p_birthday)
    where id = v_id and profile_id is null;
    return v_id;
  end if;

  insert into public.people (phone_e164_hash, display_name, birthday)
  values (v_hash, p_display_name, p_birthday)
  returning id into v_id;

  return v_id;
end;
$$;

-- Link a signed-up profile to its person row, creating the row if this number
-- was never imported by anyone.
create or replace function private.claim_person(
  p_profile_id uuid,
  p_phone text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := private.phone_hash(p_phone);
  v_id bigint;
  v_name text;
  v_dob date;
begin
  select p.display_name, p.date_of_birth into v_name, v_dob
  from public.profiles p where p.id = p_profile_id;

  insert into public.people (phone_e164_hash, display_name, birthday, profile_id)
  values (v_hash, coalesce(v_name, 'New user'), v_dob, p_profile_id)
  on conflict (phone_e164_hash) do update
    set profile_id = p_profile_id,
        display_name = coalesce(v_name, public.people.display_name),
        birthday = coalesce(v_dob, public.people.birthday)
  returning id into v_id;

  return v_id;
end;
$$;

-- The "not me / remove me" path. Hard-deletes the person and every edge
-- pointing at them, then records the hash so a re-import cannot resurrect it.
create or replace function private.suppress_person(p_person_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
begin
  select p.phone_e164_hash into v_hash from public.people p where p.id = p_person_id;

  if v_hash is null then
    raise exception 'person % not found', p_person_id;
  end if;

  insert into private.suppressions (phone_e164_hash)
  values (v_hash)
  on conflict (phone_e164_hash) do nothing;

  delete from public.people where id = p_person_id;
end;
$$;

revoke execute on function private.upsert_person(text, text, date) from public, anon, authenticated;
revoke execute on function private.claim_person(uuid, text) from public, anon, authenticated;
revoke execute on function private.suppress_person(bigint) from public, anon, authenticated;

-- Keep a claimed person's public identity in step with their profile.
create or replace function private.sync_person_from_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.people
  set display_name = new.display_name,
      birthday = coalesce(new.date_of_birth, birthday)
  where profile_id = new.id;
  return new;
end;
$$;

create trigger profiles_sync_person
  after update of display_name, date_of_birth on public.profiles
  for each row execute function private.sync_person_from_profile();

-- R13: trigger functions are private helpers too, and are PUBLIC-executable
-- by default.
revoke execute on function private.sync_person_from_profile()
  from public, anon, authenticated;

-- ------------------------------------------------------------- policies

create policy people_select_visible
  on public.people
  for select
  to authenticated
  using ((select private.can_see_person(people.id)));

-- No insert/update/delete policies on people: writes go through
-- private.upsert_person and private.claim_person, called by Edge Functions
-- with the service role.

create policy celebrations_select_own
  on public.celebrations
  for select
  to authenticated
  using (celebrator_profile_id = (select auth.uid()));

create policy celebrations_insert_own
  on public.celebrations
  for insert
  to authenticated
  with check (celebrator_profile_id = (select auth.uid()));

create policy celebrations_update_own
  on public.celebrations
  for update
  to authenticated
  using (celebrator_profile_id = (select auth.uid()))
  with check (celebrator_profile_id = (select auth.uid()));

create policy celebrations_delete_own
  on public.celebrations
  for delete
  to authenticated
  using (celebrator_profile_id = (select auth.uid()));

create policy blocks_all_own
  on public.blocks
  for all
  to authenticated
  using (blocker_profile_id = (select auth.uid()))
  with check (blocker_profile_id = (select auth.uid()));

-- A celebration edge must not point at yourself, and must respect a block.
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

  return new;
end;
$$;

create trigger celebrations_guard
  before insert on public.celebrations
  for each row execute function private.guard_celebration();

-- R13: as above.
revoke execute on function private.guard_celebration()
  from public, anon, authenticated;
