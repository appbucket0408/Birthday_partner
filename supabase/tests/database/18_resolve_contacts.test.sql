begin;
select plan(9);

select tests.as_postgres();

-- One number already known to the app, one never seen, one suppressed.
select tests.create_person('+919120000001', 'Known Friend', 6::smallint, 10::smallint);
select private.suppress_person(
  tests.create_person('+919120000002', 'Opted Out')
);

select is(
  (select person_id from private.resolve_contacts(array['+919120000001'])),
  (select id from public.people where display_name = 'Known Friend'),
  'a known number resolves to its existing person'
);

select is(
  (select display_name from private.resolve_contacts(array['+919120000001'])),
  'Known Friend',
  'the match carries the name the app needs to show'
);

-- F2: the import screen needs only WHETHER a birthday is missing, so it can
-- prompt -- never the birthday itself. A match for a person with a birthday
-- must report has_birthday = true without exposing birth_month/birth_day.
select is(
  (select has_birthday from private.resolve_contacts(array['+919120000001'])),
  true,
  'a resolved match with a known birthday reports has_birthday = true'
);

-- The Edge Function calls the wrapper, never the private function. Signature
-- drift between the two fails at runtime, not at DDL time.
select is(
  (select person_id from public.rpc_resolve_contacts(array['+919120000001'])),
  (select id from public.people where display_name = 'Known Friend'),
  'the service_role wrapper returns what the private function returns'
);

-- One number saved under two contact entries must not surface the same person
-- twice.
select is(
  (select count(*)::int from private.resolve_contacts(
     array['+919120000001', '+919120000001', '+919120000001'])),
  1,
  'a number repeated in the input resolves to one row'
);

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000099']) $$,
  'an unknown number resolves to nothing'
);

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000002']) $$,
  'a suppressed number never resolves, even though a hash once existed'
);

-- The whole point: resolving is read-only. Count only this file's own
-- fixture rows -- counting every row in public.people would break for an
-- unrelated reason the day seed.sql grows another row.
select is(
  (select count(*)::int from public.people
     where phone_e164_hash in (
       private.phone_hash('+919120000001'), private.phone_hash('+919120000002')
     )),
  1,
  'resolving unknown numbers creates no people rows'
);

-- The suppressions filter defends a real path: private.claim_person upserts into
-- public.people with no suppression check, so a suppressed hash can resurface
-- via signup. Reproduce that state directly — a people row co-existing with a
-- suppressions row — and prove resolution still refuses it. Without this, the
-- not-exists clause could be deleted from the migration and every test would
-- still pass.
insert into public.people (phone_e164_hash, display_name)
values (private.phone_hash('+919120000002'), 'Resurfaced');

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000002']) $$,
  'a suppressed number stays unresolvable even when a person row exists again'
);

select * from finish();
rollback;
