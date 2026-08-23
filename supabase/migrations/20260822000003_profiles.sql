create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique,
  display_name text not null,
  date_of_birth date,
  city text,
  avatar_url text,
  is_staff boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- 40 chars, not 20: the signup trigger below generates a handle from the
  -- user's uuid, which is 33 characters until onboarding sets a real one.
  constraint profiles_handle_format check (handle ~ '^[a-z0-9_]{3,40}$'),
  constraint profiles_dob_sane check (
    date_of_birth is null
    or (date_of_birth > date '1900-01-01' and date_of_birth <= current_date)
  )
);

alter table public.profiles enable row level security;

-- A profile is readable and writable only by the person it belongs to.
-- Other users never read this table: public identity lives on public.people,
-- which Task 4 creates. That keeps a user's city and date of birth private by
-- default rather than by remembering to filter columns.
create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()));

create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No insert policy: profiles are created by the trigger below, not by clients.
-- No delete policy: account deletion cascades from auth.users.

-- is_staff is set by a database administrator only, and profiles_update_own
-- otherwise lets a user write every column of their own row — so this grant is
-- the only thing between a user and the ops console.
--
-- R14: a column-level `revoke update (is_staff)` does NOT work here, even
-- though it reads like it should. Supabase's default privileges hand
-- `authenticated` table-level UPDATE on every new public table, and in Postgres
-- a table-level grant permits writing every column regardless of column-level
-- revokes. Proved: with the revoke alone, `update public.profiles set
-- is_staff = true where id = auth.uid()` succeeded. The table-level grant has
-- to come off first, then the writable columns go back one at a time.
revoke update on public.profiles from anon, authenticated;
grant update (handle, display_name, date_of_birth, city, avatar_url)
  on public.profiles to authenticated;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, handle, display_name)
  values (
    new.id,
    'u' || replace(new.id::text, '-', '')::text,
    coalesce(new.raw_user_meta_data ->> 'display_name', 'New user')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- R13: every private function carries its own revoke — a new one is
-- PUBLIC-executable by default and default privileges cannot prevent that on
-- PG17. Caught by 01_private.test.sql's boundary assertion.
revoke execute on function private.handle_new_user() from public, anon, authenticated;
