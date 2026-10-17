begin;
select plan(7);

select tests.as_postgres();
select tests.create_user('cb_me');
select tests.create_user('cb_fan');
select tests.create_user('cb_stranger');
select private.claim_person(
  (select id from public.profiles where handle = 'cb_me'), '+919240000001');
select private.claim_person(
  (select id from public.profiles where handle = 'cb_fan'), '+919240000002');
select private.claim_person(
  (select id from public.profiles where handle = 'cb_stranger'), '+919240000003');

create temporary table ids as
select
  (select id from public.profiles where handle = 'cb_me') as me,
  (select id from public.people where phone_e164_hash =
     private.phone_hash('+919240000002')) as fan_person,
  (select id from public.people where phone_e164_hash =
     private.phone_hash('+919240000003')) as stranger_person,
  (select id from public.people where phone_e164_hash =
     private.phone_hash('+919240000001')) as me_person;
grant select on ids to authenticated;

-- The fan celebrates me. The stranger does not.
select private.add_celebration(
  (select id from public.profiles where handle = 'cb_fan'),
  '+919240000001', 'Me');

select tests.as_user((select me from ids));

select lives_ok(
  $$ select public.rpc_celebrate_back((select fan_person from ids)) $$,
  'I can celebrate back someone who celebrates me'
);

select is(
  (select source from public.celebrations
    where celebrator_profile_id = (select me from ids)
      and person_id = (select fan_person from ids)),
  'manual',
  'the edge exists, marked as not from an address book'
);

select lives_ok(
  $$ select public.rpc_celebrate_back((select fan_person from ids)) $$,
  'celebrating back twice is a no-op, not an error'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select me from ids)),
  1,
  'and does not create a second edge'
);

-- THE privacy assertion: a person id alone must not reach a stranger.
select throws_ok(
  $$ select public.rpc_celebrate_back((select stranger_person from ids)) $$,
  '45006',
  null,
  'someone who does not celebrate me cannot be added by id'
);

select throws_ok(
  $$ select public.rpc_celebrate_back((select me_person from ids)) $$,
  '45006',
  null,
  'nor can I celebrate myself this way'
);

select tests.as_anon();
select throws_ok(
  $$ select public.rpc_celebrate_back(1) $$,
  '42501',
  null,
  'anon cannot call it at all'
);

reset role;
select * from finish();
rollback;
