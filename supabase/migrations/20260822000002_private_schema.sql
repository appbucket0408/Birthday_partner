create schema if not exists private;

-- Nothing outside the database may touch this schema.
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

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
