begin;
select plan(8);

select has_table('public', 'orders', 'orders exists');
select has_table('public', 'address_access_log', 'address_access_log exists');

select tests.as_postgres();

-- Fixtures: a confirmed gift, one staff user, one normal user.
select tests.create_user('opsuser');
update public.profiles set is_staff = true where handle = 'opsuser';
select tests.create_user('normaluser');
select tests.create_user('buyer');
select private.claim_person((select id from public.profiles where handle = 'buyer'), '+919500000001');
-- R21 again: people.birthday is a date of birth and must be in the past.
select tests.create_person(
  '+919500000002', 'Recipient Rita', ((current_date + 2) - interval '28 years')::date);

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'buyer'),
  (select id from public.people where display_name = 'Recipient Rita'),
  'contacts'
);

insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 2, time '09:00', time '12:00', 5
from public.service_areas where name = 'Gurugram';

select private.create_gift(
  (select id from public.profiles where handle = 'buyer'),
  (select id from public.people where display_name = 'Recipient Rita'),
  (select id from public.products limit 1),
  (select id from public.delivery_slots where window_start = time '09:00'),
  current_date + 2,
  'Enjoy'
);

select private.mark_gift_paid((select id from public.gifts limit 1), 'pay_ops_1', 'evt_ops_1');

-- Staff cannot see an address before the recipient confirms.
select tests.as_user((select id from public.profiles where handle = 'opsuser'));
select throws_ok(
  $$ select * from public.ops_get_delivery_address((select id from public.gifts limit 1)) $$,
  '42501',
  null,
  'staff cannot read an address before confirmation'
);

-- Confirm, then staff can read it.
select tests.as_postgres();
select private.confirm_gift(
  (select confirm_token from public.gifts limit 1),
  '4 Tulip Street', null, 'Gurugram', '122003'
);

select tests.as_user((select id from public.profiles where handle = 'opsuser'));
select is(
  (select line1 from public.ops_get_delivery_address((select id from public.gifts limit 1))),
  '4 Tulip Street',
  'staff read the address once the gift is confirmed'
);

-- And the read was logged.
select is(
  (select count(*)::int from public.address_access_log),
  1,
  'every staff address read writes an audit row'
);

-- The migration says an audit trail its own subject can edit is not an audit
-- trail. R14 is the reason that claim gets an assertion instead of trust: staff
-- hold a SELECT policy and nothing else, so a delete must silently affect zero
-- rows rather than emptying the log.
with attempted as (
  delete from public.address_access_log returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'staff cannot delete their own audit trail'
);

-- A normal user cannot call the function at all.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'normaluser'));
select throws_ok(
  $$ select * from public.ops_get_delivery_address((select id from public.gifts limit 1)) $$,
  '42501',
  null,
  'a non-staff user cannot read a delivery address'
);

-- A normal user cannot read the ops tables.
select is(
  (select count(*)::int from public.orders),
  0,
  'a non-staff user reads no orders'
);

select * from finish();
rollback;
