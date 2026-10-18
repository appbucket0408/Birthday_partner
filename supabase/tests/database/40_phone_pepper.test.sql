begin;
select plan(7);

-- After a reset, migrations remove the public placeholder (nothing is hashed
-- yet) and seed.sql sets the local pepper. If the placeholder were still the
-- value, the migration's removal would not be doing its job.
select isnt(
  (select value from private.config where key = 'phone_pepper'),
  'dev-pepper-replace-in-production',
  'the public placeholder is not the pepper'
);

-- Replacing the function must not have widened who can call it.
select ok(
  not has_function_privilege('authenticated', 'private.phone_hash(text)', 'execute'),
  'authenticated still cannot call phone_hash');
select ok(
  not has_function_privilege('anon', 'private.phone_hash(text)', 'execute'),
  'anon still cannot call phone_hash');

select is(
  private.phone_hash('+919876543210') ~ '^[0-9a-f]{64}$',
  true,
  'with a pepper set, a phone hashes to 64 hex characters as before'
);

-- Fail closed. Everything below runs inside this test's transaction and is
-- rolled back.
delete from private.config where key = 'phone_pepper';

select throws_ok(
  $$ select private.phone_hash('+919876543210') $$,
  'P0001',
  'phone_pepper is not configured',
  'with no pepper, hashing refuses instead of returning NULL'
);

-- The paths that hash on a user's behalf fail with the same named error,
-- not a not-null violation on people.phone_e164_hash far from the cause.
select throws_ok(
  $$ select private.upsert_person('+919400000999', 'No Pepper') $$,
  'P0001',
  'phone_pepper is not configured',
  'creating a person without a pepper fails with the named error'
);

insert into private.config (key, value) values ('phone_pepper', '');
select throws_ok(
  $$ select private.phone_hash('+919876543210') $$,
  'P0001',
  'phone_pepper is not configured',
  'an empty pepper counts as not configured'
);

select * from finish();
rollback;
