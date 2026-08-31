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

-- The signature changed from a single date to month/day/year. `create or
-- replace` cannot drop the old overload, and leaving it makes two-argument
-- calls ambiguous if seed.sql is re-run against an existing database.
drop function if exists tests.create_person(text, text, date);

create or replace function tests.create_person(
  p_phone text,
  p_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language sql
as $$
  select private.upsert_person(
    p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);
$$;

-- Opens two real connections and races them for the last unit of capacity on
-- the committed 'Race Test Area' slot. Returns whether the second connection
-- was made to wait, and the SQLSTATE it eventually failed with.
create or replace function tests.race_last_slot()
returns table (blocked boolean, loser_sqlstate text)
language plpgsql
as $$
declare
  -- R18: the plan's 'host=127.0.0.1 port=54322' cannot work, and the note telling
  -- you to re-read the port from `supabase status` points at the wrong thing.
  -- dblink dials from INSIDE the Postgres container, so (a) the port is 5432,
  -- not the 54322 host-side mapping, and (b) the host must be the container's
  -- own address, not loopback: pg_hba trusts 127.0.0.1, so no password is used
  -- and dblink refuses the connection outright for a non-superuser
  -- ("Non-superusers may only connect using credentials they provide").
  -- The container address falls under the 172.16.0.0/12 scram-sha-256 rule, so
  -- the password is genuinely exercised. inet_server_addr() keeps this correct
  -- if the docker subnet changes.
  v_host text := coalesce(host(inet_server_addr()), 'localhost');
  v_conn text := format(
    'dbname=postgres user=postgres password=postgres host=%s port=5432', v_host);
  v_slot bigint;
  v_blocked boolean;
  v_sqlstate text := null;
begin
  select s.id into v_slot
  from public.delivery_slots s
  join public.service_areas a on a.id = s.service_area_id
  where a.name = 'Race Test Area';

  perform extensions.dblink_connect('race_a', v_conn);
  perform extensions.dblink_connect('race_b', v_conn);

  -- Reset committed state so the test is repeatable without a db reset.
  perform extensions.dblink_exec(
    'race_a', format('update public.delivery_slots set reserved = 0 where id = %s', v_slot));

  -- Connection A takes the only unit and holds its transaction open.
  perform extensions.dblink_exec('race_a', 'begin');
  -- R19: dblink_exec refuses a statement that returns rows, and
  -- `select private.reserve_slot(...)` returns one (a void). Use dblink().
  perform * from extensions.dblink(
    'race_a', format('select private.reserve_slot(%s)', v_slot)) as t(r text);

  -- Connection B tries for the same unit and must wait on A's row lock.
  perform extensions.dblink_send_query('race_b', format('select private.reserve_slot(%s)', v_slot));
  perform pg_sleep(0.3);
  v_blocked := extensions.dblink_is_busy('race_b') = 1;

  -- A commits; B now re-evaluates the predicate and must lose.
  perform extensions.dblink_exec('race_a', 'commit');

  begin
    perform * from extensions.dblink_get_result('race_b') as r(result text);
  exception
    when others then
      v_sqlstate := sqlstate;
  end;

  -- Drain and close.
  begin
    perform * from extensions.dblink_get_result('race_b') as r(result text);
  exception
    when others then null;
  end;

  perform extensions.dblink_disconnect('race_a');
  perform extensions.dblink_disconnect('race_b');

  return query select v_blocked, v_sqlstate;
end;
$$;

-- R15: a test that switches from one user to another calls tests.as_user()
-- while it is already in the authenticated role, so the role it is switching
-- FROM needs to reach this schema. Without these grants every multi-user test
-- in Tasks 4-11 dies with "permission denied for schema tests" on its second
-- switch. Safe: seed.sql runs on `supabase db reset` only and is never applied
-- to a hosted environment.
grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;

-- Committed local fixtures. Task 7's concurrency test reserves against
-- 'Race Test Area' from separate connections, so this data must exist outside
-- any test transaction.
insert into public.service_areas (name)
values ('Gurugram'), ('Race Test Area')
on conflict (name) do nothing;

insert into public.products (service_area_id, name, flavour, size, price_minor)
select id, 'Classic Chocolate Truffle', 'chocolate', '500g', 84900
from public.service_areas where name = 'Gurugram'
on conflict do nothing;

insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 7, time '10:00', time '13:00', 1
from public.service_areas where name = 'Race Test Area'
on conflict (service_area_id, slot_date, window_start) do nothing;

-- Task 8 / Ruling F4: the local seed could not complete a gift at all.
-- 'Gurugram' (above) had a product and no slots, ever; 'Race Test Area' had
-- a slot and no products, so its picker was never reached -- and Task 6's
-- exact-date filter compounds it, since the picker shows only slots on the
-- recipient's OWN birthday, and one fixed seed date matches an arbitrary
-- birthday essentially never. Give Gurugram a slot on every one of the next
-- 60 days so any test contact whose birthday falls in that window reaches a
-- bookable one. 'Race Test Area' is untouched above, exactly as it was:
-- Task 7's concurrency test (tests.race_last_slot) reserves against it from
-- two separate connections and depends on it existing outside any test
-- transaction.
insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select a.id, d, time '10:00', time '13:00', 5
from public.service_areas a
cross join generate_series(current_date + 1, current_date + 60, interval '1 day') as d
where a.name = 'Gurugram'
on conflict (service_area_id, slot_date, window_start) do nothing;
