begin;
select plan(12);

select has_table('public', 'people', 'people exists');
select has_table('public', 'celebrations', 'celebrations exists');

select tests.as_postgres();

-- Two users import the same phone number: they must converge on one person.
select is(
  tests.create_person('+919000000001', 'Cousin Meera', 4::smallint, 12::smallint, 1995::smallint),
  tests.create_person('+919000000001', 'Meera', 4::smallint, 12::smallint, 1995::smallint),
  'the same phone number resolves to the same person row'
);

-- A suppressed number cannot be resurrected by a later import.
select private.suppress_person(
  tests.create_person('+919000000002', 'Nope')
);
select is(
  tests.create_person('+919000000002', 'Nope Again'),
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

-- B1 (20260827000006): `authenticated` has no INSERT path into celebrations
-- at all any more, so this no longer reaches private.guard_celebration and
-- no longer raises P0001. That is the point: celebrations_insert_own let the
-- caller choose person_id freely, which turned a sequential bigint into a
-- directory of every user's real name and date of birth. Edges are now minted
-- only by private.add_celebration, which resolves the person from a PHONE
-- NUMBER the caller supplied.
--
-- The self-celebration guard has NOT been weakened, only moved off this
-- path: it is asserted on the add_celebration route in
-- 21_add_celebration.test.sql, and the BEFORE UPDATE half of the guard is
-- asserted in 24_celebrations_write_lockdown.test.sql.
--
-- The assertion is deliberately aimed at the caller's OWN person id -- the
-- most sympathetic possible insert -- so it proves "no insert at all" rather
-- than "no insert at somebody else's row".
select throws_ok(
  $$ insert into public.celebrations (celebrator_profile_id, person_id, source)
     select (select auth.uid()), private.my_person_id(), 'manual' $$,
  '42501',
  null,
  'authenticated cannot insert a celebration edge, not even one it would own'
);

-- Alice can drop a celebration she owns.
select lives_ok(
  $$ delete from public.celebrations
     where celebrator_profile_id = (select auth.uid()) $$,
  'alice can delete her own celebration edge'
);

-- Alice cannot forge an edge on bob's behalf either. Same SQLSTATE as above
-- and now for the same underlying reason (no INSERT privilege and no INSERT
-- policy) rather than because of celebrations_insert_own's `with check`, but
-- the rule this pins -- one user cannot manufacture another user's edges --
-- is what a future migration must not regress.
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
