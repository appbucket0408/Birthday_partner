begin;
select plan(3);

select tests.as_postgres();
select tests.create_user('date_sender');

create temporary table date_gift_ids as
select
  (select id from public.profiles where handle = 'date_sender') as sender,
  tests.create_person('+919999557001', 'Date Test Friend')      as friend;
grant select on date_gift_ids to authenticated;

insert into public.service_areas (name) values ('Occasion Date Test Area');
insert into public.products (service_area_id, name, price_minor)
select id, 'Occasion Date Cake', 50000
from public.service_areas where name = 'Occasion Date Test Area';

-- Two slots, ample capacity each, on different dates in the same service
-- area -- so assertions 2 and 3 do not share (and cannot exhaust) a slot,
-- and so a failure can never be a capacity collision wearing a date
-- rejection's costume (the exact confusion Phase 1a's Task 2 hit with this
-- same SQLSTATE).
insert into public.delivery_slots
  (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 10, '09:00', '11:00', 10
from public.service_areas where name = 'Occasion Date Test Area';
insert into public.delivery_slots
  (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 11, '09:00', '11:00', 10
from public.service_areas where name = 'Occasion Date Test Area';

create temporary table date_gift_slots as
select
  (select id from public.delivery_slots
     where slot_date = current_date + 10
       and service_area_id = (select id from public.service_areas
                                 where name = 'Occasion Date Test Area')) as same_day,
  (select id from public.delivery_slots
     where slot_date = current_date + 11
       and service_area_id = (select id from public.service_areas
                                 where name = 'Occasion Date Test Area')) as next_day;
grant select on date_gift_slots to authenticated;

insert into public.celebrations (celebrator_profile_id, person_id, source)
select sender, friend, 'contacts' from date_gift_ids;

-- 1. The happy path: the slot's date equals the occasion date. Without this
--    assertion, deleting the whole feature would still pass this file.
select lives_ok(
  $$ select private.create_gift(
       (select sender from date_gift_ids),
       (select friend from date_gift_ids),
       (select id from public.products where name = 'Occasion Date Cake'),
       (select same_day from date_gift_slots),
       current_date + 10,
       'On the day'
     ) $$,
  'a gift whose slot date matches the occasion date is created'
);

-- 2. The slot is one day AFTER the occasion date.
select throws_ok(
  $$ select private.create_gift(
       (select sender from date_gift_ids),
       (select friend from date_gift_ids),
       (select id from public.products where name = 'Occasion Date Cake'),
       (select next_day from date_gift_slots),
       current_date + 10,
       'Slot too late'
     ) $$,
  '23514',
  null,
  'a slot one day after the occasion date is refused'
);

-- 3. The slot is one day BEFORE the occasion date. Both directions are
--    asserted separately because a >= or <= typo in the check would pass
--    one of these and fail the other.
select throws_ok(
  $$ select private.create_gift(
       (select sender from date_gift_ids),
       (select friend from date_gift_ids),
       (select id from public.products where name = 'Occasion Date Cake'),
       (select same_day from date_gift_slots),
       current_date + 11,
       'Slot too early'
     ) $$,
  '23514',
  null,
  'a slot one day before the occasion date is refused'
);

select * from finish();
rollback;
