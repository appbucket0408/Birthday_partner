begin;
select plan(9);

select has_table('public', 'service_areas', 'service_areas exists');
select has_table('public', 'products', 'products exists');
select has_table('public', 'delivery_slots', 'delivery_slots exists');

select tests.as_postgres();

insert into public.service_areas (name) values ('Gurugram Test');

insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
values (
  (select id from public.service_areas where name = 'Gurugram Test'),
  current_date + 3, time '10:00', time '13:00', 2
);

-- Capacity is honoured exactly.
select lives_ok(
  $$ select private.reserve_slot(
       (select id from public.delivery_slots
        where service_area_id = (select id from public.service_areas where name = 'Gurugram Test'))) $$,
  'first reservation succeeds'
);

select lives_ok(
  $$ select private.reserve_slot(
       (select id from public.delivery_slots
        where service_area_id = (select id from public.service_areas where name = 'Gurugram Test'))) $$,
  'second reservation succeeds'
);

select throws_ok(
  $$ select private.reserve_slot(
       (select id from public.delivery_slots
        where service_area_id = (select id from public.service_areas where name = 'Gurugram Test'))) $$,
  '23514',
  null,
  'a third reservation on a capacity-2 slot is rejected'
);

-- Releasing frees capacity again.
select lives_ok(
  $$ select private.release_slot(
       (select id from public.delivery_slots
        where service_area_id = (select id from public.service_areas where name = 'Gurugram Test'))) $$,
  'release frees one unit of capacity'
);

-- The constraint is a backstop even against a direct write.
select throws_ok(
  $$ update public.delivery_slots set reserved = capacity + 1
     where service_area_id = (select id from public.service_areas where name = 'Gurugram Test') $$,
  '23514',
  null,
  'the not-oversold check constraint rejects a direct overwrite'
);

-- Clients read the catalog but never write it.
select tests.create_user('shopper');
select tests.as_user((select id from public.profiles where handle = 'shopper'));
select throws_ok(
  $$ insert into public.products (service_area_id, name, price_minor)
     values ((select id from public.service_areas limit 1), 'Free cake', 1) $$,
  '42501',
  null,
  'a normal user cannot insert products'
);

select * from finish();
rollback;
