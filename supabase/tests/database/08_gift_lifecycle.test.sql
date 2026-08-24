begin;
select plan(14);

select tests.as_postgres();

-- Fixtures.
select tests.create_user('payer');
select private.claim_person((select id from public.profiles where handle = 'payer'), '+919300000001');
-- Their birthday falls in five days. Month and day are all a reminder needs;
-- the year is optional and omitted here.
select tests.create_person(
  '+919300000002', 'Unregistered Friend',
  extract(month from current_date + 5)::smallint,
  extract(day from current_date + 5)::smallint);

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'payer'),
  (select id from public.people where display_name = 'Unregistered Friend'),
  'contacts'
);

insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 5, time '14:00', time '17:00', 1
from public.service_areas where name = 'Gurugram';

-- Creating a gift holds the slot in the same short transaction.
select lives_ok(
  $$ select private.create_gift(
       (select id from public.profiles where handle = 'payer'),
       (select id from public.people where display_name = 'Unregistered Friend'),
       (select id from public.products limit 1),
       (select id from public.delivery_slots where window_start = time '14:00'),
       current_date + 5,
       'Many happy returns'
     ) $$,
  'create_gift succeeds'
);

select is(
  (select reserved from public.delivery_slots where window_start = time '14:00'),
  1,
  'create_gift reserved the slot'
);

select is(
  (select status::text from public.gifts limit 1),
  'draft',
  'a new gift starts as draft with the slot held'
);

-- The second buyer for the last slot is refused before any money moves.
select throws_ok(
  $$ select private.create_gift(
       (select id from public.profiles where handle = 'payer'),
       (select id from public.people where display_name = 'Unregistered Friend'),
       (select id from public.products limit 1),
       (select id from public.delivery_slots where window_start = time '14:00'),
       current_date + 5,
       'Second cake'
     ) $$,
  '23514',
  null,
  'a full slot is refused at gift creation, before payment'
);

-- Payment moves the gift on, and a duplicate webhook is a no-op.
select lives_ok(
  $$ select private.mark_gift_paid(
       (select id from public.gifts limit 1), 'pay_abc123', 'evt_001') $$,
  'mark_gift_paid advances the gift'
);

select is(
  (select status::text from public.gifts limit 1),
  'awaiting_confirm',
  'a paid gift is awaiting confirmation'
);

select lives_ok(
  $$ select private.mark_gift_paid(
       (select id from public.gifts limit 1), 'pay_abc123', 'evt_001') $$,
  'a replayed webhook event does not error'
);

select is(
  (select count(*)::int from public.gift_events where to_status = 'paid'),
  1,
  'a replayed webhook does not double-advance the gift'
);

-- Confirmation stores the address and reveals only the city to the sender.
select lives_ok(
  $$ select private.confirm_gift(
       (select confirm_token from public.gifts limit 1),
       '8 Marigold Road', null, 'Gurugram', '122002') $$,
  'confirm_gift accepts an address and slot'
);

select is(
  (select delivery_city from public.gifts limit 1),
  'Gurugram',
  'the gift carries the delivery city for the sender to see'
);

-- A used token cannot be replayed.
select throws_ok(
  $$ select private.confirm_gift(
       (select confirm_token from public.gifts limit 1),
       'Somewhere else', null, 'Gurugram', '122003') $$,
  'P0001',
  'this confirmation link has already been used',
  'the confirm token is single use'
);

-- ---------------------------------------------------------------- R3 + R20
-- The plan shipped expire_stale_gifts and refund_gift with no coverage at all.
-- This is the automatic money-back path: it runs unattended under pg_cron and
-- a silent failure costs a real refund, so it gets asserted here.

select tests.as_postgres();

insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 5, time '18:00', time '21:00', 1
from public.service_areas where name = 'Gurugram';

-- A hold of -1 minutes is already expired, so no clock manipulation is needed.
select private.create_gift(
  (select id from public.profiles where handle = 'payer'),
  (select id from public.people where display_name = 'Unregistered Friend'),
  (select id from public.products limit 1),
  (select id from public.delivery_slots where window_start = time '18:00'),
  current_date + 5,
  'Abandoned checkout',
  -1
);

select private.expire_stale_gifts();

select is(
  (select g.status::text || ' slot_reserved=' || s.reserved
     from public.gifts g
     join public.delivery_slots s on s.id = g.slot_id
    where g.message = 'Abandoned checkout'),
  'expired slot_reserved=0',
  'an abandoned draft expires and gives its slot back'
);

-- Paid but never confirmed, and the occasion has arrived: the sender's money
-- comes back without anyone filing a ticket.
insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date, time '09:00', time '12:00', 1
from public.service_areas where name = 'Gurugram';

select private.create_gift(
  (select id from public.profiles where handle = 'payer'),
  (select id from public.people where display_name = 'Unregistered Friend'),
  (select id from public.products limit 1),
  (select id from public.delivery_slots where window_start = time '09:00'),
  current_date,
  'Never confirmed'
);

select private.mark_gift_paid(
  (select id from public.gifts where message = 'Never confirmed'),
  'pay_stale', 'evt_stale');

select private.expire_stale_gifts();

select is(
  (select g.status::text || ' slot_reserved=' || s.reserved
     from public.gifts g
     join public.delivery_slots s on s.id = g.slot_id
    where g.message = 'Never confirmed'),
  'refunded slot_reserved=0',
  'a paid gift nobody confirmed is refunded automatically'
);

-- R20: confirming to a city we do not serve must REFUND, per spec 5 rule 5.
insert into public.delivery_slots (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 6, time '11:00', time '14:00', 1
from public.service_areas where name = 'Gurugram';

select private.create_gift(
  (select id from public.profiles where handle = 'payer'),
  (select id from public.people where display_name = 'Unregistered Friend'),
  (select id from public.products limit 1),
  (select id from public.delivery_slots where window_start = time '11:00'),
  current_date + 6,
  'Wrong city'
);

select private.mark_gift_paid(
  (select id from public.gifts where message = 'Wrong city'),
  'pay_area', 'evt_area');

do $$
begin
  perform private.confirm_gift(
    (select confirm_token from public.gifts where message = 'Wrong city'),
    '4 Elsewhere Street', null, 'Mumbai', '400001');
exception
  when others then null;
end
$$;

select is(
  (select g.status::text || ' slot_reserved=' || s.reserved
     from public.gifts g
     join public.delivery_slots s on s.id = g.slot_id
    where g.message = 'Wrong city'),
  'refunded slot_reserved=0',
  'an out-of-area confirmation refunds the sender and frees the slot'
);

select * from finish();
rollback;
