begin;
select plan(10);

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

-- "On Birthday" means a member: a person row someone CLAIMED. A row that
-- exists only because another user imported the number is not one.
select is(
  (select is_member from private.resolve_contacts(array['+919120000001'])),
  false,
  'an imported-only person is not reported as a member'
);

select tests.create_user('rc_member');
select private.claim_person(
  (select id from public.profiles where handle = 'rc_member'), '+919120000003');
select is(
  (select is_member from private.resolve_contacts(array['+919120000003'])),
  true,
  'a person who claimed their row is reported as a member'
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

select is(
  (select count(*)::int from public.people
     where phone_e164_hash in (
       private.phone_hash('+919120000001'),
       private.phone_hash('+919120000002'),
       private.phone_hash('+919120000099')
     )),
  1,
  'resolving unknown numbers creates no people rows'
);

insert into public.people (phone_e164_hash, display_name)
values (private.phone_hash('+919120000002'), 'Resurfaced');

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000002']) $$,
  'a suppressed number stays unresolvable even when a person row exists again'
);

select * from finish();
rollback;
