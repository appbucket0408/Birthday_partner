begin;
select plan(12);

select has_table('public', 'gifts', 'gifts exists');
select has_table('public', 'gift_events', 'gift_events exists');

select tests.as_postgres();

-- Fixtures: a sender, a recipient, a product and a slot.
select tests.create_user('giver');
select tests.create_user('honoree');
select tests.create_user('stranger');
select private.claim_person((select id from public.profiles where handle = 'giver'), '+919200000001');
select private.claim_person((select id from public.profiles where handle = 'honoree'), '+919200000002');
select private.claim_person((select id from public.profiles where handle = 'stranger'), '+919200000003');

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'giver'),
  (select id from public.people where profile_id = (select id from public.profiles where handle = 'honoree')),
  'contacts'
);

insert into public.gifts (
  sender_profile_id, recipient_person_id, product_id, service_area_id,
  occasion_date, amount_minor, message
)
values (
  (select id from public.profiles where handle = 'giver'),
  (select id from public.people where profile_id = (select id from public.profiles where handle = 'honoree')),
  (select id from public.products limit 1),
  (select service_area_id from public.products limit 1),
  current_date + 7,
  84900,
  'Happy birthday!'
);

-- Legal transitions walk the happy path.
select lives_ok(
  $$ select private.gift_transition((select id from public.gifts limit 1), 'paid') $$,
  'draft to paid is legal'
);
select lives_ok(
  $$ select private.gift_transition((select id from public.gifts limit 1), 'awaiting_confirm') $$,
  'paid to awaiting_confirm is legal'
);

-- Illegal transitions are rejected, not silently applied.
select throws_ok(
  $$ select private.gift_transition((select id from public.gifts limit 1), 'delivered') $$,
  '23514',
  null,
  'awaiting_confirm straight to delivered is rejected'
);

select is(
  (select status::text from public.gifts limit 1),
  'awaiting_confirm',
  'a rejected transition leaves the status untouched'
);

-- Every transition is recorded.
select is(
  (select count(*)::int from public.gift_events),
  2,
  'each successful transition appends one gift_events row'
);

-- The guard trigger blocks status writes that bypass the state machine, even
-- for a role that bypasses RLS.
select throws_ok(
  $$ update public.gifts set status = 'delivered' $$,
  'P0001',
  'gift status must change through private.gift_transition',
  'a direct status update is blocked by the guard trigger'
);

-- Visibility: the sender sees their gift.
select tests.as_user((select id from public.profiles where handle = 'giver'));
select is(
  (select count(*)::int from public.gifts),
  1,
  'the sender sees their own gift'
);

-- The recipient sees the gift addressed to them.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'honoree'));
select is(
  (select count(*)::int from public.gifts),
  1,
  'the recipient sees the gift addressed to them'
);

-- An unrelated user sees nothing.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'stranger'));
select is(
  (select count(*)::int from public.gifts),
  0,
  'an unrelated user sees no gifts'
);

-- No client may write gifts at all (spec §5 rule 1).
select tests.as_user((select id from public.profiles where handle = 'giver'));
select throws_ok(
  $$ insert into public.gifts (
       sender_profile_id, recipient_person_id, product_id, service_area_id,
       occasion_date, amount_minor
     ) values (
       (select auth.uid()),
       (select id from public.people limit 1),
       (select id from public.products limit 1),
       (select service_area_id from public.products limit 1),
       current_date + 1, 1
     ) $$,
  '42501',
  null,
  'a client cannot insert a gift'
);

select * from finish();
rollback;
