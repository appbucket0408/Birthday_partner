begin;
select plan(6);

select tests.as_postgres();
select tests.create_user('gi_me');
select tests.create_user('gi_other');
select private.claim_person(
  (select id from public.profiles where handle = 'gi_me'), '+919250000001');
select private.add_celebration(
  (select id from public.profiles where handle = 'gi_me'),
  '+919250000002', 'Friend');
select tests.create_person('+919250000003', 'Stranger');

create temporary table ids as
select
  (select id from public.profiles where handle = 'gi_me') as me,
  (select id from public.profiles where handle = 'gi_other') as other,
  (select id from public.people where display_name = 'Friend') as friend,
  (select id from public.people where display_name = 'Stranger') as stranger;
grant select on ids to authenticated;

select tests.as_user((select me from ids));

select lives_ok(
  $$ insert into public.gift_interest (recipient_person_id)
     values ((select friend from ids)) $$,
  'I can register interest in a cake for someone I celebrate'
);

select is(
  (select profile_id from public.gift_interest
    where recipient_person_id = (select friend from ids)),
  (select me from ids),
  'the row is mine, filled in from the session'
);

select throws_ok(
  $$ insert into public.gift_interest (recipient_person_id)
     values ((select friend from ids)) $$,
  '23505',
  null,
  'registering twice for the same person is one signal, not two'
);

select throws_ok(
  $$ insert into public.gift_interest (recipient_person_id)
     values ((select stranger from ids)) $$,
  '42501',
  null,
  'not for someone I do not celebrate'
);

select throws_ok(
  $$ insert into public.gift_interest (profile_id, recipient_person_id)
     values ((select other from ids), (select friend from ids)) $$,
  '42501',
  null,
  'nor in someone else''s name'
);

select tests.as_user((select other from ids));
select is(
  (select count(*)::int from public.gift_interest),
  0,
  'another user sees none of my interest'
);

reset role;
select * from finish();
rollback;
