begin;
select plan(5);

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

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000099']) $$,
  'an unknown number resolves to nothing'
);

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000002']) $$,
  'a suppressed number never resolves, even though a hash once existed'
);

-- The whole point: resolving is read-only.
select is(
  (select count(*)::int from public.people),
  1,
  'resolving unknown numbers creates no people rows'
);

select * from finish();
rollback;
