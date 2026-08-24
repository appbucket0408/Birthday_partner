begin;
select plan(4);

select tests.as_postgres();
select tests.create_user('starkid');
select tests.create_user('fanone');
select tests.create_user('fantwo');
select private.claim_person((select id from public.profiles where handle = 'starkid'), '+919700000001');
select private.claim_person((select id from public.profiles where handle = 'fanone'), '+919700000002');
select private.claim_person((select id from public.profiles where handle = 'fantwo'), '+919700000003');

-- Both fans celebrate the star. The star celebrates nobody.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select p.id,
       (select id from public.people where profile_id =
          (select id from public.profiles where handle = 'starkid')),
       'contacts'
from public.profiles p where p.handle in ('fanone', 'fantwo');

-- R22: resolve ids while still postgres. profiles_select_own hides other
-- users' rows from an authenticated session, so a lookup by handle from inside
-- one returns NULL.
create temporary table ids as
select
  (select id from public.profiles where handle = 'starkid') as star,
  (select id from public.profiles where handle = 'fanone')  as fan_one,
  (select id from public.profiles where handle = 'fantwo')  as fan_two;
grant select on ids to authenticated;

select tests.as_user((select star from ids));

select is(
  (select count(*)::int from public.celebrations),
  2,
  'the star sees both people who celebrate them'
);

-- A fan sees only their own outgoing edge, never the other fan's.
select tests.as_postgres();
select tests.as_user((select fan_one from ids));
select is(
  (select count(*)::int from public.celebrations),
  1,
  'a fan sees only their own outgoing edge'
);

-- Blocking removes a celebrator from the list.
select tests.as_postgres();
insert into public.blocks (blocker_profile_id, blocked_profile_id)
values ((select star from ids), (select fan_two from ids));

select tests.as_user((select star from ids));
select is(
  (select count(*)::int from public.celebrations),
  1,
  'a blocked celebrator drops out of the Celebrates list'
);

-- And the surviving row is the one that was not blocked.
select is(
  (select celebrator_profile_id from public.celebrations),
  (select fan_one from ids),
  'the remaining celebrator is the unblocked fan'
);

select * from finish();
rollback;
