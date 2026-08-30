begin;
select plan(5);

select tests.as_postgres();

-- 1. The job exists and is scheduled. Without this the sweep never runs and an
--    abandoned draft holds a delivery slot forever.
select is(
  (select count(*)::int from cron.job where jobname = 'gift-hold-sweep'),
  1,
  'the gift-hold sweep is scheduled exactly once'
);

select is(
  (select command from cron.job where jobname = 'gift-hold-sweep'),
  ' select private.expire_stale_gifts(); ',
  'the job calls expire_stale_gifts'
);

-- Build a real draft holding a real slot, then age it past its hold.
select tests.create_user('gifter');

create temporary table sweep_ids as
select
  (select id from public.profiles where handle = 'gifter') as gifter,
  tests.create_person('+919999555001', 'Slot Holder')      as recipient;

insert into public.service_areas (name) values ('Sweep Test Area');

insert into public.products (service_area_id, name, price_minor)
select id, 'Sweep Cake', 50000 from public.service_areas
where name = 'Sweep Test Area';

insert into public.delivery_slots
  (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 7, '09:00', '11:00', 1
from public.service_areas where name = 'Sweep Test Area';

create temporary table sweep_slot as
select s.id as slot_id, p.id as product_id
from public.delivery_slots s
join public.products p on p.service_area_id = s.service_area_id
where s.slot_date = current_date + 7;

select private.create_gift(
  (select gifter from sweep_ids),
  (select recipient from sweep_ids),
  (select product_id from sweep_slot),
  (select slot_id from sweep_slot),
  current_date + 7
);

-- 2. Reserving is what makes the sweep matter: the slot is now full.
select is(
  (select reserved from public.delivery_slots
     where id = (select slot_id from sweep_slot)),
  1,
  'creating a draft reserves the slot'
);

-- Age the hold past expiry, then sweep.
update public.gifts set slot_hold_expires_at = now() - interval '1 minute'
where slot_id = (select slot_id from sweep_slot);

select private.expire_stale_gifts();

-- 3. THE POINT OF THIS TASK. Not "the function ran" -- the capacity came back.
select is(
  (select reserved from public.delivery_slots
     where id = (select slot_id from sweep_slot)),
  0,
  'the sweep releases the slot an abandoned draft was holding'
);

select is(
  (select status::text from public.gifts
     where slot_id = (select slot_id from sweep_slot)),
  'expired',
  'the abandoned draft is marked expired'
);

select * from finish();
rollback;
