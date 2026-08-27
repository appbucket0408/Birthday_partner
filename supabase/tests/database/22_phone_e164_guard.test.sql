-- private.phone_hash is a bare HMAC with zero normalisation, so any
-- deviation in phone format (missing '+', stray spaces, garbage) hashes to a
-- DIFFERENT value and therefore mints a DIFFERENT public.people row. That
-- silently forks one human into several rows AND defeats
-- add_celebration's self-celebration guard, because the guard compares
-- hashes and a caller who sends their own number in a non-canonical form
-- hashes to something that does not match their already-claimed row.
--
-- private.assert_e164 (20260827000004) closes this at every write path.
-- This file proves the guard itself, and separately proves the exploit it
-- closes: claim a number, then try to self-import it via an unnormalised
-- form.
begin;
select plan(12);

select tests.as_postgres();

-- ---- assert_e164 rejects every non-canonical shape ------------------------

select throws_ok(
  $$ select private.upsert_person('919999000002', 'No Plus') $$,
  '22023',
  null,
  'upsert_person rejects a phone missing the leading +'
);

select throws_ok(
  $$ select private.upsert_person('+91 99990 00002', 'Spaced') $$,
  '22023',
  null,
  'upsert_person rejects a phone with internal spaces'
);

select throws_ok(
  $$ select private.upsert_person('', 'Empty') $$,
  '22023',
  null,
  'upsert_person rejects an empty phone'
);

select throws_ok(
  $$ select private.upsert_person('not-a-phone', 'Garbage') $$,
  '22023',
  null,
  'upsert_person rejects a non-numeric phone'
);

select isnt(
  private.upsert_person('+919330000099', 'Canonical Friend'),
  null,
  'upsert_person still accepts a canonical E.164 number'
);

-- claim_person is the other direct write path onto public.people; it needs
-- its own coverage rather than relying on upsert_person's.
select tests.create_user('e164claimer');

select throws_ok(
  format(
    $$ select private.claim_person(%L::uuid, 'not-a-phone') $$,
    (select id from public.profiles where handle = 'e164claimer')
  ),
  '22023',
  null,
  'claim_person rejects a malformed phone'
);

-- ---- the bypass: claim a number, then self-import it in a bad shape -------

select tests.create_user('selfguard');
select private.claim_person(
  (select id from public.profiles where handle = 'selfguard'),
  '+919330000001'
);

-- Before the guard, both of these created a real, distinct self-edge instead
-- of raising -- the exact hole the reviewer reproduced. Now assert_e164
-- rejects the input before add_celebration's self-check (or upsert_person)
-- ever runs.
select throws_ok(
  format(
    $$ select private.add_celebration(%L::uuid, '919330000001', 'Me',
         null::smallint, null::smallint, null::smallint) $$,
    (select id from public.profiles where handle = 'selfguard')
  ),
  '22023',
  null,
  'self-import via an unprefixed form of your own number now raises'
);

select throws_ok(
  format(
    $$ select private.add_celebration(%L::uuid, '+91 93300 00001', 'Me',
         null::smallint, null::smallint, null::smallint) $$,
    (select id from public.profiles where handle = 'selfguard')
  ),
  '22023',
  null,
  'self-import via a spaced form of your own number now raises'
);

-- The exploit's actual damage, proven closed: no self-edge, and no forked
-- person row for the same human under a second hash.
select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id =
      (select id from public.profiles where handle = 'selfguard')),
  0,
  'no self-edge was created by any unnormalised bypass attempt'
);

-- Count the rows a fork would ACTUALLY leave behind. An earlier form of this
-- assertion matched on `profile_id = selfguard or phone_e164_hash =
-- phone_hash('+919330000001')` and was vacuous: a row forked from
-- '919330000001' carries a different hash AND a null profile_id, so it
-- satisfied neither arm and the count read 1 whether or not the guard worked.
-- The bypass attempts all pass display_name 'Me', so any row they minted is
-- exactly what this counts.
select is(
  (select count(*)::int from public.people where display_name = 'Me'),
  0,
  'no forked people row was minted by any unnormalised bypass attempt'
);

-- The guard is revoked from client roles like every other private helper.
select is(
  has_function_privilege(
    'authenticated', 'private.assert_e164(text)', 'EXECUTE'),
  false,
  'authenticated cannot call private.assert_e164() directly'
);

-- ---- resolve_contacts is deliberately exempt: it's a read-only lookup over
-- a whole address book, and a malformed entry must fail to match, not raise
-- and kill everyone else's resolution in the same batch.
select is_empty(
  $$ select phone from private.resolve_contacts(
       array['not-a-phone', '919999000002', '']) $$,
  'resolve_contacts tolerates malformed phones without raising'
);

select * from finish();
rollback;
