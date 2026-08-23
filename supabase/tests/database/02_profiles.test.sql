begin;
select plan(8);

select has_table('public', 'profiles', 'profiles exists');

-- RLS must be on.
select is(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  true,
  'RLS is enabled on profiles'
);

-- Signing up creates a profile.
select tests.as_postgres();
select lives_ok(
  $$ select tests.create_user('alice') $$,
  'creating an auth user creates a profile'
);
select tests.create_user('bob');

select is(
  (select count(*)::int from public.profiles where handle = 'alice'),
  1,
  'alice has exactly one profile'
);

-- Two profiles exist; alice must see exactly one.
select tests.as_user((select id from public.profiles where handle = 'alice'));
select is(
  (select count(*)::int from public.profiles),
  1,
  'alice sees only her own profile row, not both'
);

-- A user cannot read someone else's row.
select is(
  (select count(*)::int from public.profiles where handle = 'bob'),
  0,
  'alice cannot read bob''s profile'
);

-- A user cannot promote themselves to staff.
select tests.as_user((select id from public.profiles where handle = 'alice'));
select is(
  (select private.is_staff()),
  false,
  'a fresh user is not staff'
);

-- R14: and she must not be able to BECOME staff. profiles_update_own lets her
-- write her own row, so the only thing standing between a user and the ops
-- console is the column privilege on is_staff. Assert the write is refused
-- rather than trusting the grant list to be right.
select throws_ok(
  $$ update public.profiles set is_staff = true where id = (select auth.uid()) $$,
  '42501',
  null,
  'alice cannot promote herself to staff'
);

select * from finish();
rollback;
