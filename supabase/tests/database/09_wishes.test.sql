begin;
select plan(8);

select has_table('public', 'wishes', 'wishes exists');

select tests.as_postgres();
select tests.create_user('wisher');
select tests.create_user('birthday_kid');
select tests.create_user('outsider');
select private.claim_person((select id from public.profiles where handle = 'wisher'), '+919400000001');
select private.claim_person((select id from public.profiles where handle = 'birthday_kid'), '+919400000002');
select private.claim_person((select id from public.profiles where handle = 'outsider'), '+919400000003');

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'wisher'),
  (select id from public.people where profile_id = (select id from public.profiles where handle = 'birthday_kid')),
  'contacts'
);

-- R22: resolve every id while still postgres. The plan's test looks the subject
-- up through public.profiles from inside an authenticated session, but Task 3's
-- profiles_select_own deliberately hides other users' profiles — public identity
-- lives on public.people — so the subquery returns NULL, subject_person_id is
-- NULL, and wishes_insert_own rejects a post that should have been allowed.
-- The policy is right; the lookup was not. A real client already knows the
-- person_id from the list of people it celebrates.
create temporary table ids as
select
  (select id from public.profiles where handle = 'wisher')       as wisher,
  (select id from public.profiles where handle = 'birthday_kid') as kid,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'birthday_kid')) as kid_person;
grant select on ids to authenticated;

-- Someone who celebrates you can post.
select tests.as_user((select id from public.profiles where handle = 'wisher'));
select lives_ok(
  $$ insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
     values (
       (select auth.uid()),
       (select kid_person from ids),
       'Have the best one yet',
       extract(year from current_date)::int
     ) $$,
  'a celebrator can post a wish'
);

-- One wish per person per year.
select throws_ok(
  $$ insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
     values (
       (select auth.uid()),
       (select kid_person from ids),
       'Again!',
       extract(year from current_date)::int
     ) $$,
  '23505',
  null,
  'a second wish in the same year is rejected'
);

-- Someone who does not celebrate you cannot post.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'outsider'));
select throws_ok(
  $$ insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
     values (
       (select auth.uid()),
       (select kid_person from ids),
       'Who are you',
       extract(year from current_date)::int
     ) $$,
  '42501',
  null,
  'a stranger cannot post to a wall'
);

-- The stranger cannot read the wall either.
select is(
  (select count(*)::int from public.wishes),
  0,
  'a stranger reads no wishes'
);

-- The subject reads their own wall.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'birthday_kid'));
select is(
  (select count(*)::int from public.wishes),
  1,
  'the birthday person reads their own wall'
);

-- A delivered gift posts itself to the wall.
select tests.as_postgres();

insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 4, time '11:00', time '14:00', 3
from public.service_areas where name = 'Gurugram';

select private.create_gift(
  (select id from public.profiles where handle = 'wisher'),
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'birthday_kid')),
  (select id from public.products limit 1),
  (select id from public.delivery_slots where window_start = time '11:00'),
  current_date + 4,
  'On its way'
);

select private.mark_gift_paid((select id from public.gifts limit 1), 'pay_wish_1', 'evt_wish_1');
select private.confirm_gift(
  (select confirm_token from public.gifts limit 1),
  '1 Cake Street', null, 'Gurugram', '122004'
);
select private.gift_transition((select id from public.gifts limit 1), 'placed');
select private.gift_transition((select id from public.gifts limit 1), 'out_for_delivery');
select private.gift_transition((select id from public.gifts limit 1), 'delivered');

select is(
  (select count(*)::int from public.wishes where kind = 'cake'),
  1,
  'delivery posts a cake wish to the wall'
);

select is(
  (select author_profile_id from public.wishes where kind = 'cake'),
  (select id from public.profiles where handle = 'wisher'),
  'the cake post is attributed to the sender'
);

select * from finish();
rollback;
