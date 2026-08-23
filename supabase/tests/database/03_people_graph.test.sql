begin;
select plan(12);

select has_table('public', 'people', 'people exists');
select has_table('public', 'celebrations', 'celebrations exists');

select tests.as_postgres();

-- Two users import the same phone number: they must converge on one person.
select is(
  tests.create_person('+919000000001', 'Cousin Meera', date '1995-04-12'),
  tests.create_person('+919000000001', 'Meera', date '1995-04-12'),
  'the same phone number resolves to the same person row'
);

-- A suppressed number cannot be resurrected by a later import.
select private.suppress_person(
  tests.create_person('+919000000002', 'Nope', null)
);
select is(
  tests.create_person('+919000000002', 'Nope Again', null),
  null,
  'a suppressed number returns null instead of a new person'
);
select is(
  (select count(*)::int from public.people
   where phone_e164_hash = private.phone_hash('+919000000002')),
  0,
  'suppression hard-deleted the person row'
);

-- Graph fixtures: alice celebrates meera; bob does not.
select tests.create_user('alice');
select tests.create_user('bob');
select private.claim_person(
  (select id from public.profiles where handle = 'alice'),
  '+919000000010'
);

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'alice'),
  (select id from public.people where phone_e164_hash = private.phone_hash('+919000000001')),
  'contacts'
);

-- Alice sees the person she celebrates.
select tests.as_user((select id from public.profiles where handle = 'alice'));
select is(
  (select count(*)::int from public.people where display_name = 'Cousin Meera'),
  1,
  'alice can read the person she celebrates'
);

-- Bob, who celebrates nobody, sees nobody.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'bob'));
select is(
  (select count(*)::int from public.people),
  0,
  'bob cannot read any person he does not celebrate'
);

-- A phone number is never readable through the API surface.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'alice'));
select throws_ok(
  $$ select private.phone_hash('+919000000001') $$,
  '42501',
  null,
  'authenticated cannot call phone_hash'
);

-- Nobody may write to people directly.
select throws_ok(
  $$ insert into public.people (phone_e164_hash, display_name)
     values (repeat('a', 64), 'Injected') $$,
  '42501',
  null,
  'authenticated cannot insert into people'
);

-- Celebrating yourself is meaningless and blocked.
select throws_ok(
  $$ insert into public.celebrations (celebrator_profile_id, person_id, source)
     select (select auth.uid()), private.my_person_id(), 'manual' $$,
  'P0001',
  'you cannot celebrate yourself',
  'self-celebration is rejected'
);

-- Alice can drop a celebration she owns.
select lives_ok(
  $$ delete from public.celebrations
     where celebrator_profile_id = (select auth.uid()) $$,
  'alice can delete her own celebration edge'
);

-- Alice cannot forge an edge on bob's behalf.
select throws_ok(
  $$ insert into public.celebrations (celebrator_profile_id, person_id, source)
     values (
       (select id from public.profiles where handle = 'bob'),
       (select id from public.people where display_name = 'Cousin Meera'),
       'manual'
     ) $$,
  '42501',
  null,
  'alice cannot create an edge owned by bob'
);

select * from finish();
rollback;
