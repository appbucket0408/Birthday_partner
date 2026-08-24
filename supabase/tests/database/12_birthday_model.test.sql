begin;
select plan(18);

select has_column('public', 'people', 'birth_month', 'people.birth_month exists');
select has_column('public', 'people', 'birth_day', 'people.birth_day exists');
select has_column('public', 'people', 'birth_year', 'people.birth_year exists');
select hasnt_column('public', 'people', 'birthday', 'the old people.birthday is gone');
select hasnt_column('public', 'profiles', 'date_of_birth', 'the old profiles.date_of_birth is gone');

select tests.as_postgres();

-- A year-less birthday is the common case from a device address book.
select lives_ok(
  $$ select tests.create_person('+919600000001', 'No Year', 3::smallint, 15::smallint) $$,
  'a birthday with no year is accepted'
);

select is(
  (select birth_month || '-' || birth_day || ' year=' || coalesce(birth_year::text, 'null')
     from public.people where display_name = 'No Year'),
  '3-15 year=null',
  'month and day are stored without a year'
);

-- Feb 29 must be storable with no year: it is a real birthday.
select lives_ok(
  $$ select tests.create_person('+919600000002', 'Leap Baby', 2::smallint, 29::smallint) $$,
  'Feb 29 is accepted with no year'
);

-- ...but not paired with a non-leap year.
select throws_ok(
  $$ select tests.create_person('+919600000003', 'Bad Leap', 2::smallint, 29::smallint, 2001::smallint) $$,
  '23514',
  null,
  'Feb 29 with a non-leap year is rejected'
);

-- 2000 is a leap year because it is divisible by 400; 1900 is not because it is
-- divisible by 100 but not 400. This is the half of the rule that gets written
-- wrong.
select lives_ok(
  $$ select tests.create_person('+919600000006', 'Century Leap', 2::smallint, 29::smallint, 2000::smallint) $$,
  'Feb 29 with 2000 is accepted'
);

select throws_ok(
  $$ select tests.create_person('+919600000007', 'Century Common', 2::smallint, 29::smallint, 1900::smallint) $$,
  '23514',
  null,
  'Feb 29 with 1900 is rejected'
);

-- Days must be valid for their month.
select throws_ok(
  $$ select tests.create_person('+919600000004', 'No Such Day', 4::smallint, 31::smallint) $$,
  '23514',
  null,
  'April 31 is rejected'
);

-- Month and day travel together.
select throws_ok(
  $$ insert into public.people (phone_e164_hash, display_name, birth_month)
     values (repeat('b', 64), 'Half A Date', 5::smallint) $$,
  '23514',
  null,
  'a month without a day is rejected at the table'
);

select throws_ok(
  $$ select tests.create_person('+919600000005', 'Half Again', 5::smallint) $$,
  '23514',
  'a birthday needs both a month and a day, or neither',
  'upsert_person rejects a half-known date with a readable message'
);

-- R14 recurs: dropping date_of_birth drops its column grant with it, so the new
-- columns need their own. Without this a user cannot edit their own birthday.
select is(
  (select has_column_privilege('authenticated', 'public.profiles', 'birth_month', 'UPDATE')::text
       || has_column_privilege('authenticated', 'public.profiles', 'birth_day', 'UPDATE')::text
       || has_column_privilege('authenticated', 'public.profiles', 'birth_year', 'UPDATE')::text),
  'truetruetrue',
  'a user may update their own birthday columns'
);

-- The sync trigger's `update of` list gained two columns in this task. A column
-- missing from that list is silent staleness, not an error, so assert the
-- propagation rather than just the write.
select tests.create_user('syncer');
select private.claim_person(
  (select id from public.profiles where handle = 'syncer'), '+919600000010');

update public.profiles
set birth_month = 7::smallint, birth_day = 4::smallint, birth_year = 1990::smallint
where handle = 'syncer';

-- Second update touches ONLY birth_day. An `update of` trigger fires when any
-- listed column is touched and NEW carries every column, so updating all three
-- at once would still pass with birth_day missing from the trigger's list.
-- Changing one column alone is what actually detects that.
update public.profiles
set birth_day = 5::smallint
where handle = 'syncer';

select is(
  (select p.birth_month || '-' || p.birth_day || '-' || p.birth_year
     from public.people p
    where p.profile_id = (select id from public.profiles where handle = 'syncer')),
  '7-5-1990',
  'a single-column birthday edit propagates to the person row'
);

-- F1: the sync trigger must treat the birthday as ONE value. Coalescing
-- month/day/year independently against a stale person row can synthesise a
-- combination nobody wrote -- (2,29) from the profile against a lingering
-- 1985 from the person -- which then fails people_birth_leap_valid and
-- aborts the user's own legal edit.
select tests.create_user('f1_leap_swap');
select private.claim_person(
  (select id from public.profiles where handle = 'f1_leap_swap'), '+919600000011');

update public.people
set birth_month = 3::smallint, birth_day = 15::smallint, birth_year = 1985::smallint
where profile_id = (select id from public.profiles where handle = 'f1_leap_swap');

select lives_ok(
  $$ update public.profiles
     set birth_month = 2::smallint, birth_day = 29::smallint, birth_year = null
     where handle = 'f1_leap_swap' $$,
  'replacing the birthday wholesale with a year-less Feb 29 does not abort on a stale year'
);

select is(
  (select p.birth_month || '-' || p.birth_day || '-' || coalesce(p.birth_year::text, 'null')
     from public.people p
    where p.profile_id = (select id from public.profiles where handle = 'f1_leap_swap')),
  '2-29-null',
  'the person row ends up year-less Feb 29, not the stale 1985 combined with the new month/day'
);

select * from finish();
rollback;
