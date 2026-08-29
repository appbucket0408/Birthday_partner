begin;
select plan(7);

select tests.as_postgres();
select tests.create_user('editor');
select tests.create_user('stranger');
select tests.create_user('claimant');

create temporary table ids as
select
  (select id from public.profiles where handle = 'editor')    as editor,
  (select id from public.profiles where handle = 'stranger')  as stranger,
  (select id from public.profiles where handle = 'claimant')  as claimant,
  tests.create_person('+919999111101', 'Unclaimed Friend')    as unclaimed,
  tests.create_person('+919999111102', 'Claimed Friend')      as claimed;
grant select on ids to authenticated;

-- The editor celebrates both people. Edges are minted by the RPC in real use;
-- here we are setting up the precondition, not testing the mint.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select editor, unclaimed, 'contacts' from ids;
insert into public.celebrations (celebrator_profile_id, person_id, source)
select editor, claimed, 'contacts' from ids;

-- The second person has claimed their own profile, so their own birthday wins.
update public.people set profile_id = (select claimant from ids)
where id = (select claimed from ids);

-- 1. The happy path: a celebrator fills in a birthday their address book lacked.
select tests.as_user((select editor from ids));
select lives_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 4::smallint, 15::smallint, null::smallint) $$,
  'a celebrator can set the birthday of an unclaimed person they celebrate'
);

select is(
  (select birth_month || '/' || birth_day from public.people
     where id = (select unclaimed from ids)),
  '4/15',
  'the birthday is actually written'
);

-- 2. A year-less birthday is the common case from a device address book, and
--    overwriting it with a year must work too.
select lives_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 4::smallint, 15::smallint, 1991::smallint) $$,
  'the year can be added later'
);

-- 3. The edge is the authorisation. people.id is a sequential bigint, so
--    without this check it is an open write target for any authenticated user.
select tests.as_user((select stranger from ids));
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 1::smallint, 1::smallint, null::smallint) $$,
  '45002',
  null,
  'a non-celebrator cannot edit the birthday'
);

-- 4. A claimed user owns their own date of birth. Without this, any celebrator
--    could rewrite a real user's DOB.
select tests.as_user((select editor from ids));
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       (select claimed from ids), 1::smallint, 1::smallint, null::smallint) $$,
  '45003',
  null,
  'a claimed person''s birthday cannot be edited by a celebrator'
);

-- 5. The table's own check constraints still apply through the RPC. April has
--    30 days; security definer must not become a way around data integrity.
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 4::smallint, 31::smallint, null::smallint) $$,
  '23514',
  null,
  'an impossible date is still rejected by the check constraint'
);

-- 6. It is an authenticated door.
select tests.as_anon();
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       1::bigint, 1::smallint, 1::smallint, null::smallint) $$,
  '42501',
  null,
  'anon cannot execute the function'
);

select * from finish();
rollback;
