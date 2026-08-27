begin;
select plan(4);

select tests.as_postgres();
select tests.create_user('claimer');

create temporary table ids as
select (select id from public.profiles where handle = 'claimer') as claimer;
grant select on ids to authenticated;

-- Before claiming, the user has no person row at all.
select is(
  (select count(*)::int from public.people
     where profile_id = (select claimer from ids)),
  0,
  'a fresh user has no person row'
);

-- Call it in its own statement. A volatile function inside a WHERE clause is
-- evaluated per candidate row and is exactly the fragility that broke an
-- assertion in Phase 1 -- assert the resulting state instead.
select public.rpc_claim_person((select claimer from ids), '+919220000001');

select is(
  (select profile_id from public.people
     where phone_e164_hash = private.phone_hash('+919220000001')),
  (select claimer from ids),
  'the wrapper links the profile to the person row for that number'
);

-- Claiming twice is the same row, not a second one. A user re-running
-- onboarding, or a retried request, must not fork their identity.
select is(
  public.rpc_claim_person((select claimer from ids), '+919220000001'),
  (select id from public.people
     where phone_e164_hash = private.phone_hash('+919220000001')),
  'claiming the same number twice returns the same person'
);

-- It is a machine door. A signed-in user must not be able to claim a number
-- they did not verify -- the Edge Function reads the phone from the JWT.
select tests.as_user((select claimer from ids));
select throws_ok(
  $$ select public.rpc_claim_person(
       (select auth.uid()), '+919220000099') $$,
  '42501',
  null,
  'a signed-in user cannot call the claim wrapper directly'
);

select * from finish();
rollback;
