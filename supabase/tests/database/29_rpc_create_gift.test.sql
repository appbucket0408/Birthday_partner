begin;
select plan(7);

select tests.as_postgres();
select tests.create_user('sender');
select tests.create_user('stranger');

create temporary table gift_ids as
select
  (select id from public.profiles where handle = 'sender')   as sender,
  (select id from public.profiles where handle = 'stranger') as stranger,
  tests.create_person('+919999556001', 'Gift Friend')        as friend;
grant select on gift_ids to authenticated;

insert into public.service_areas (name) values ('Gift Test Area');
insert into public.products (service_area_id, name, price_minor)
select id, 'Gift Cake', 50000 from public.service_areas where name = 'Gift Test Area';
insert into public.delivery_slots
  (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 7, '09:00', '11:00', 1
from public.service_areas where name = 'Gift Test Area';

-- Scoped by the fixture's OWN area, not by slot_date: Task 8 seeds Gurugram
-- with a slot on every one of the next 60 days (F4), so `current_date + 7`
-- is no longer a date only this fixture occupies -- a plain slot_date
-- filter here would join against Gurugram's own product too and this
-- temporary table would hold more than one row.
create temporary table gift_catalog as
select s.id as slot_id, p.id as product_id
from public.delivery_slots s
join public.products p on p.service_area_id = s.service_area_id
where s.service_area_id =
  (select id from public.service_areas where name = 'Gift Test Area');
grant select on gift_catalog to authenticated;

-- The sender celebrates the friend. The stranger does not.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select sender, friend, 'contacts' from gift_ids;

-- 1. The happy path.
select tests.as_user((select sender from gift_ids));
select lives_ok(
  $$ select public.rpc_create_gift(
       (select friend from gift_ids),
       (select product_id from gift_catalog),
       (select slot_id from gift_catalog),
       current_date + 7,
       'Happy birthday!') $$,
  'a sender can draft a gift for someone they celebrate'
);

-- 2. THE PRODUCT'S CORE PROMISE. delivery_city is written only at
--    confirmation, so a sender looking at their own gift sees no city yet.
select is(
  (select delivery_city from public.gifts
     where sender_profile_id = (select sender from gift_ids)),
  null,
  'a draft carries no city -- it is written only at confirmation'
);

-- 3. THE PRODUCT'S CORE PROMISE, genuinely exercised. Whole-branch review §8
--    should-fix 3: the original version of this assertion counted
--    public.addresses with the table holding ZERO rows, so it passed with
--    every RLS policy on addresses dropped -- it proved nothing. Fixed by
--    creating a REAL address for the gift's own recipient (the friend, not
--    an unrelated person -- this must be the exact row a real gift points
--    at, not merely some address existing) and asserting as the sender that
--    it is still invisible. Same pattern as 04_addresses.test.sql:42-58
--    (zero rows, then a city-filter probe) -- not invented here.
select tests.as_postgres();
select private.set_address_for_person(
  (select friend from gift_ids), 'Home', '1 Test Lane', null, 'Giftville', '110001'
);

select tests.as_user((select sender from gift_ids));
select is(
  (select count(*)::int from public.addresses),
  0,
  'a sender selecting addresses gets zero rows even though the recipient has a real one'
);

select is(
  (select count(*)::int from public.addresses where city = 'Giftville'),
  0,
  'a sender cannot find the recipient''s address by filtering on city'
);

-- 4. THE GUARD THIS TASK ADDS. people.id is a sequential bigint, so without
--    it a caller aims a gift at a stranger by guessing, and learns the id
--    exists.
select tests.as_user((select stranger from gift_ids));
select throws_ok(
  $$ select public.rpc_create_gift(
       (select friend from gift_ids),
       (select product_id from gift_catalog),
       (select slot_id from gift_catalog),
       current_date + 7,
       null) $$,
  '45005',
  null,
  'a caller who does not celebrate the recipient cannot draft a gift'
);

-- 5. The oversold path. Capacity is 1 and assertion 1 took it. Two users
--    racing for the last slot is a legitimate outcome, and 23514 is how the
--    UI learns to say "that slot just filled" rather than "something went
--    wrong".
select tests.as_postgres();
insert into public.celebrations (celebrator_profile_id, person_id, source)
select stranger, friend, 'contacts' from gift_ids;

select tests.as_user((select stranger from gift_ids));
select throws_ok(
  $$ select public.rpc_create_gift(
       (select friend from gift_ids),
       (select product_id from gift_catalog),
       (select slot_id from gift_catalog),
       current_date + 7,
       null) $$,
  '23514',
  null,
  'a full slot refuses with the oversold constraint, not a generic error'
);

-- 6. It is an authenticated door.
select tests.as_anon();
select throws_ok(
  $$ select public.rpc_create_gift(1::bigint, 1::bigint, 1::bigint,
       current_date, null) $$,
  '42501',
  null,
  'anon cannot execute the function'
);

select * from finish();
rollback;
