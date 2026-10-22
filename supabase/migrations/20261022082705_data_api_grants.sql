-- Table and sequence privileges for the API roles, stated explicitly.
--
-- Every earlier migration relied on Supabase's DEFAULT privileges to give
-- anon, authenticated and service_role full access to new public tables,
-- leaving RLS to decide which rows each caller sees. The local stack still
-- has those defaults. Newer hosted projects do not: their default ACL for
-- tables created by `postgres` grants only TRUNCATE/REFERENCES/TRIGGER/
-- MAINTAIN, and nothing on sequences. On candlewish_dev that left every
-- table unreadable to signed-in users (GET /rest/v1/profiles -> 403, so the
-- app hung after OTP) and to service_role (0 of 16 tables).
--
-- This migration reproduces the local end state exactly, and is a no-op
-- locally. It must NOT be a blanket `grant all`: three tables were narrowed
-- on purpose, and a table-level grant would quietly undo that.
--   profiles       table-wide UPDATE revoked (20260822000003); edits go
--                  through the per-column grants only.
--   celebrations   INSERT and UPDATE revoked (20260827000006); writes go
--                  through SECURITY DEFINER RPCs only.
--   gift_interest  its own explicit grants (20261017000007); left alone.
-- Revoking here is not an option either: REVOKE at table level also removes
-- every column-level grant on that table.
--
-- RLS stays enabled on every table; these grants only let a query reach it.

grant select, insert, update, delete
  on all tables in schema public to service_role;

do $$
declare
  t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public'
      and tablename not in ('profiles', 'celebrations', 'gift_interest')
  loop
    execute format(
      'grant select, insert, update, delete on public.%I to anon, authenticated',
      t
    );
  end loop;
end
$$;

grant select, insert, delete on public.profiles to anon, authenticated;
grant select, delete on public.celebrations to anon, authenticated;

grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;

-- Future tables and sequences get what the local stack gives them, so the
-- next migration does not work locally and 403 on hosted. A migration that
-- wants less still revokes, as the three above did.
alter default privileges for role postgres in schema public
  grant select, insert, update, delete on tables
  to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant usage, select on sequences
  to anon, authenticated, service_role;
