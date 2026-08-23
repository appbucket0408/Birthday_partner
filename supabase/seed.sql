-- Test-only helpers. Local development and CI only; seed.sql is not applied
-- to hosted environments by `supabase db push`.
create schema if not exists tests;

create or replace function tests.as_user(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  execute 'set local role authenticated';
end;
$$;

create or replace function tests.as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  execute 'set local role anon';
end;
$$;

create or replace function tests.as_postgres()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  execute 'set local role postgres';
end;
$$;

-- Creates an auth user and returns its id. The profiles row is created by the
-- on_auth_user_created trigger; this then sets a predictable handle.
create or replace function tests.create_user(p_handle text)
returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  ) values (
    v_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    p_handle || '@example.test',
    '',
    now(), now(), now()
  );

  update public.profiles
  set handle = p_handle,
      display_name = initcap(p_handle)
  where id = v_id;

  return v_id;
end;
$$;

create or replace function tests.create_person(
  p_phone text,
  p_name text,
  p_birthday date default null
)
returns bigint
language sql
as $$
  select private.upsert_person(p_phone, p_name, p_birthday);
$$;

-- R15: a test that switches from one user to another calls tests.as_user()
-- while it is already in the authenticated role, so the role it is switching
-- FROM needs to reach this schema. Without these grants every multi-user test
-- in Tasks 4-11 dies with "permission denied for schema tests" on its second
-- switch. Safe: seed.sql runs on `supabase db reset` only and is never applied
-- to a hosted environment.
grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;
