begin;
select plan(9);

select tests.as_postgres();
select tests.create_user('picker');
select private.claim_person(
  (select id from public.profiles where handle = 'picker'), '+919230000001');

create temporary table ids as
select (select id from public.profiles where handle = 'picker') as picker;

-- Capture the first pick's person id so the idempotency check below can
-- assert the retry returns the SAME id, not merely that it does not error.
create temporary table picks as
select private.add_celebration((select picker from ids), '+919230000002',
  'Picked Friend', 4::smallint, 1::smallint, null::smallint) as friend_id;

-- Picking a contact mints the person AND the edge together.
select isnt(
  (select friend_id from picks),
  null,
  'picking a contact returns a person id'
);

select is(
  (select count(*)::int from public.celebrations c
     join public.people p on p.id = c.person_id
    where c.celebrator_profile_id = (select picker from ids)
      and p.display_name = 'Picked Friend'),
  1,
  'the celebration edge is created alongside the person'
);

-- Picking the same contact twice is idempotent — a retried request or a
-- double tap must not error, must not fork the graph, and must return the
-- SAME person id. A regression that returns null on the retry path would
-- read to the app as "this contact is suppressed, skip it" — a real bug a
-- mere lives_ok would not catch.
select is(
  private.add_celebration((select picker from ids), '+919230000002',
    'Picked Friend', 4::smallint, 1::smallint, null::smallint),
  (select friend_id from picks),
  'picking the same contact twice returns the same person id'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select picker from ids)),
  1,
  'and does not create a second edge'
);

-- A suppressed number returns null and creates nothing. Someone who asked to
-- be removed must not be re-added by the next person who imports their phone.
select private.suppress_person(
  tests.create_person('+919230000003', 'Opted Out'));
select is(
  private.add_celebration((select picker from ids), '+919230000003',
    'Opted Out', null::smallint, null::smallint, null::smallint),
  null,
  'a suppressed number returns null instead of a person'
);

select is(
  (select count(*)::int from public.celebrations c
     join public.people p on p.id = c.person_id
    where p.display_name = 'Opted Out'),
  0,
  'a suppressed contact creates no edge, not just a null return'
);

-- The wrapper is the only surface production can reach, and three of its six
-- parameters are same-typed smallints — exactly where a transposition hides.
select public.rpc_add_celebration((select picker from ids), '+919230000004',
  'Wrapper Friend', 3::smallint, 25::smallint, null::smallint);

select is(
  (select p.birth_month || '-' || p.birth_day
     from public.people p where p.display_name = 'Wrapper Friend'),
  '3-25',
  'the service_role wrapper passes month and day through in the right order'
);

-- Celebrating yourself is meaningless. The trigger from M0 is inert here
-- (it reads auth.uid() from a session, and there is none under service_role)
-- so the check lives inside add_celebration itself. It carries a stable
-- SQLSTATE (P0002, not the generic P0001 every other unhandled exception
-- also carries) so the Edge Function can tell "you tried to celebrate
-- yourself" apart from a database fault — see 22_phone_e164_guard.test.sql
-- for the migration that added it.
select throws_ok(
  $$ select private.add_celebration((select picker from ids), '+919230000001',
       'Me', null::smallint, null::smallint, null::smallint) $$,
  'P0002',
  'you cannot celebrate yourself',
  'picking your own number is rejected, with a stable SQLSTATE'
);

-- The claim-time cleanup. A user who imports contacts BEFORE claiming their own
-- person row can pick their own number: add_celebration cannot detect that,
-- because an unclaimed row carries no profile_id and the phone lives in
-- auth.users. claim_person is the first moment both facts are known, so it
-- removes any edge that has just become a self-edge. celebrations_guard cannot
-- help — it is BEFORE INSERT only, and inert under service_role anyway.
select tests.as_postgres();
select tests.create_user('lateclaimer');

select private.add_celebration(
  (select id from public.profiles where handle = 'lateclaimer'),
  '+919230000009', 'Actually Me', null::smallint, null::smallint, null::smallint);

select private.claim_person(
  (select id from public.profiles where handle = 'lateclaimer'), '+919230000009');

select is(
  (select count(*)::int
     from public.celebrations c
     join public.people p on p.id = c.person_id
    where c.celebrator_profile_id = p.profile_id),
  0,
  'claiming a number removes an edge that just became a self-edge'
);

select * from finish();
rollback;
