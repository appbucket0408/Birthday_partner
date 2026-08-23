begin;
select plan(7);

select has_table('public', 'addresses', 'addresses exists');

select is(
  (select relrowsecurity from pg_class where oid = 'public.addresses'::regclass),
  true,
  'RLS is enabled on addresses'
);

select tests.as_postgres();
select tests.create_user('sender');
select tests.create_user('recipient');
select private.claim_person(
  (select id from public.profiles where handle = 'sender'), '+919100000001'
);
select private.claim_person(
  (select id from public.profiles where handle = 'recipient'), '+919100000002'
);

-- The recipient has a home address.
select private.set_address_for_person(
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'recipient')),
  'Home', '12 Rose Lane', null, 'Gurugram', '122001'
);

-- The sender celebrates the recipient, which is the maximum relationship the
-- app allows, and still sees nothing.
insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'sender'),
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'recipient')),
  'contacts'
);

select tests.as_user((select id from public.profiles where handle = 'sender'));

-- THE test. Not "an error" — zero rows.
select is(
  (select count(*)::int from public.addresses),
  0,
  'a sender selecting addresses gets zero rows'
);

select is(
  (select count(*)::int from public.addresses where city = 'Gurugram'),
  0,
  'a sender cannot find the address by filtering on city'
);

select is(
  (select count(*)::int from public.addresses where line1 like '%Rose%'),
  0,
  'a sender cannot probe the address by pattern'
);

-- The owner reads their own address.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'recipient'));
select is(
  (select line1 from public.addresses),
  '12 Rose Lane',
  'the owner reads their own address'
);

-- A sender cannot reassign an address to themselves.
select tests.as_postgres();
select tests.as_user((select id from public.profiles where handle = 'sender'));
-- R17: a data-modifying statement is only legal inside a WITH clause, never in
-- a FROM subquery, so the plan's `from (update ...) u` is a syntax error.
with attempted as (
  update public.addresses
  set owner_person_id = private.my_person_id()
  returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'a sender updating addresses affects zero rows'
);

select * from finish();
rollback;
