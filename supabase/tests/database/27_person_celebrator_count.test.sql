begin;
select plan(6);

select tests.as_postgres();
select tests.create_user('counter');
select tests.create_user('stranger');
select tests.create_user('blocker');

create temporary table ids as
select
  (select id from public.profiles where handle = 'counter')   as counter,
  (select id from public.profiles where handle = 'stranger')  as stranger,
  (select id from public.profiles where handle = 'blocker')   as blocker,
  tests.create_person('+919999444401', 'Popular Person')      as popular;
grant select on ids to authenticated;

-- The counter celebrates Popular, so can_see_person lets them look.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select counter, popular, 'contacts' from ids;

-- Two more celebrators, neither of whom the counter can see by name.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select stranger, popular, 'contacts' from ids;
insert into public.celebrations (celebrator_profile_id, person_id, source)
select blocker, popular, 'contacts' from ids;

-- 1. The happy path: three edges point at Popular.
select tests.as_user((select counter from ids));
select is(
  public.person_celebrator_count((select popular from ids)),
  3,
  'counts every celebrator of a person the caller can see'
);

-- 2. A block in either direction removes that celebrator from the count.
--    Deliberately BOTH directions, unlike my_celebrates() which excludes only
--    celebrators the viewer blocked: this is a number shown to both parties,
--    and a blocked relationship should contribute to neither side's total.
select tests.as_postgres();
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select blocker, counter from ids;

select tests.as_user((select counter from ids));
select is(
  public.person_celebrator_count((select popular from ids)),
  2,
  'a celebrator who blocked the caller is not counted'
);

select tests.as_postgres();
delete from public.blocks;
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select counter, blocker from ids;

select tests.as_user((select counter from ids));
select is(
  public.person_celebrator_count((select popular from ids)),
  2,
  'a celebrator the caller blocked is not counted either'
);

-- 3. The visibility gate. people.id is a sequential bigint, so without this
--    anyone could walk the id space and count any user's followers.
select tests.as_user((select stranger from ids));
select lives_ok(
  $$ select public.person_celebrator_count(
       (select popular from ids)) $$,
  'a celebrator of the person can call it'
);

select tests.as_postgres();
select tests.create_user('outsider');
select tests.as_user((select id from public.profiles where handle = 'outsider'));
select throws_ok(
  $$ select public.person_celebrator_count(
       (select popular from ids)) $$,
  '45004',
  null,
  'someone with no connection to the person cannot count their celebrators'
);

-- 4. It is an authenticated door.
select tests.as_anon();
select throws_ok(
  $$ select public.person_celebrator_count(1::bigint) $$,
  '42501',
  null,
  'anon cannot execute the function'
);

select * from finish();
rollback;
