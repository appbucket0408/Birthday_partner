begin;
select plan(6);

select tests.as_postgres();
select tests.create_user('picker');
select private.claim_person(
  (select id from public.profiles where handle = 'picker'), '+919230000001');

create temporary table ids as
select (select id from public.profiles where handle = 'picker') as picker;

-- Picking a contact mints the person AND the edge together.
select isnt(
  private.add_celebration((select picker from ids), '+919230000002',
    'Picked Friend', 4::smallint, 1::smallint, null::smallint),
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
-- double tap must not error and must not fork the graph.
select lives_ok(
  $$ select private.add_celebration((select picker from ids), '+919230000002',
       'Picked Friend', 4::smallint, 1::smallint, null::smallint) $$,
  'picking the same contact twice does not error'
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

-- Celebrating yourself is meaningless. M0's guard trigger raises P0001.
select throws_ok(
  $$ select private.add_celebration((select picker from ids), '+919230000001',
       'Me', null::smallint, null::smallint, null::smallint) $$,
  'P0001',
  'you cannot celebrate yourself',
  'picking your own number is rejected'
);

select * from finish();
rollback;
