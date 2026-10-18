begin;
select plan(9);

select has_schema('private', 'private schema exists');
select has_table('private', 'config', 'private.config exists');

-- The pepper must be seeded, or hashing silently returns null.
select isnt(
  (select value from private.config where key = 'phone_pepper'),
  null,
  'phone_pepper is seeded'
);

-- Hashing is deterministic and shaped like sha256 hex.
select matches(
  private.phone_hash('+919876543210'),
  '^[0-9a-f]{64}$',
  'phone_hash returns 64 hex chars'
);

select is(
  private.phone_hash('+919876543210'),
  private.phone_hash('+919876543210'),
  'phone_hash is deterministic'
);

select isnt(
  private.phone_hash('+919876543210'),
  private.phone_hash('+919876543211'),
  'different numbers hash differently'
);

-- R10: a policy calling a private helper is evaluated as the CALLING role, so
-- `authenticated` needs USAGE on the schema as well as EXECUTE on the function.
-- These two assertions together ARE the private-schema boundary: the door is
-- open for is_staff() and shut for phone_hash(). tests.as_user does not exist
-- until Task 3's seed.sql, so set the role directly.
set local role authenticated;

select is(
  (select private.is_staff()),
  false,
  'authenticated can call private.is_staff() and gets false'
);

select throws_ok(
  $$ select private.phone_hash('+919876543210') $$,
  '42501',
  null,
  'authenticated cannot call private.phone_hash()'
);

reset role;

-- R13: the standing guard on the schema boundary. A new private function added
-- without its own revoke is PUBLIC-executable by default, and default
-- privileges cannot prevent that on PG17 — so this assertion is what catches it.
-- The expected list is the ALLOWLIST: a helper belongs here only because an RLS
-- policy calls it as the signed-in user. Growing this list is a security
-- decision, so it must be a deliberate edit, never a convenience one.
select is(
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  -- is_public_wish_photo: wish_photos_select_public_feed (20261018000002)
  -- calls it as the signed-in user, so a member can load the photo on a
  -- public feed post. It answers one yes/no about one storage path.
  'can_see_person,is_public_wish_photo,is_staff,my_person_id',
  'only the policy helpers are executable by authenticated'
);

select * from finish();
rollback;
