create schema if not exists private;

-- Nothing outside the database may touch this schema.
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- R10: RLS policies are evaluated as the CALLING role, so every policy that
-- calls a private helper needs `authenticated` to hold schema USAGE. Without
-- this, Tasks 4, 6, 8, 10 and 11 raise permission-denied for ordinary signed-in
-- users instead of returning a boolean. USAGE alone grants nothing: EXECUTE is
-- revoked from public below and granted back one function at a time, so the
-- per-function grant list stays the real boundary.
grant usage on schema private to authenticated;

-- R13: there is no default-privileges guard here on purpose. `alter default
-- privileges ... revoke execute on functions from public` is a NO-OP on this
-- Postgres 17 — a private function created afterwards still comes out
-- PUBLIC-executable (verified: pg_proc.proacl is null and
-- has_function_privilege('authenticated', ...) is true). The guarantee is
-- enforced by 01_private.test.sql instead, which asserts is_staff() is the ONLY
-- private function authenticated may execute. Every new private function must
-- therefore carry its own explicit revoke, and the suite fails loudly if one
-- does not.

create table private.config (
  key text primary key,
  value text not null
);

alter table private.config enable row level security;
-- No policies: anon and authenticated get nothing. service_role bypasses RLS,
-- which is why the pepper must never be handed to a browser client.

-- Local/dev pepper. Production sets its own value out of band; rotating it
-- invalidates every stored people.phone_e164_hash, so it is set once at launch.
insert into private.config (key, value)
values ('phone_pepper', 'dev-pepper-replace-in-production')
on conflict (key) do nothing;

create or replace function private.phone_hash(p_phone text)
returns text
language sql
security definer
set search_path = ''
stable
as $$
  select encode(
    extensions.hmac(
      p_phone,
      (select value from private.config where key = 'phone_pepper'),
      'sha256'
    ),
    'hex'
  );
$$;

revoke execute on function private.phone_hash(text) from public;
revoke execute on function private.phone_hash(text) from anon, authenticated;

-- is_staff is referenced by ops policies in Task 11. It reads profiles, which
-- Task 3 creates, so the body is deliberately tolerant of that table not
-- existing yet during this migration's own transaction.
create or replace function private.is_staff()
returns boolean
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_is_staff boolean;
begin
  select p.is_staff into v_is_staff
  from public.profiles p
  where p.id = (select auth.uid());
  return coalesce(v_is_staff, false);
exception
  when undefined_table then
    return false;
end;
$$;

revoke execute on function private.is_staff() from public;
revoke execute on function private.is_staff() from anon;

-- R12: the revoke above removes the PUBLIC grant that was authenticated's only
-- route to EXECUTE, so the grant it is meant to keep has to be explicit. This
-- is the one private function policies may call.
grant execute on function private.is_staff() to authenticated;
