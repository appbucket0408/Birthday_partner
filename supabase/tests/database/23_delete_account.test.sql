-- delete_account (Task 7) is a database cascade wearing an Edge Function's
-- clothes: the function's only real work is calling auth.admin.deleteUser,
-- and everything that follows is `on delete` behaviour already declared on
-- the schema. The Edge Function's own proof of that (a shell script with
-- before/after row counts) evaporates the moment the terminal scrolls away.
-- This file pins the documented cascade table for good:
--
--   cascades away: profiles, their outgoing celebrations, wishes they
--     authored, their device_tokens, their blocks (both directions),
--     their queued notification_outbox rows (as a recipient)
--   survives, but SCRUBBED (20260827000005): their own people row --
--     id and phone_e164_hash unchanged, profile_id set NULL, display_name
--     replaced with a placeholder, birth_month/day/year nulled, any
--     reminder already queued about them (as a subject) deleted, their own
--     delivery address deleted -- and every OTHER profile's celebration
--     edge still pointing at that now-unclaimed, now-scrubbed row
--
-- auth.admin.deleteUser ultimately does one thing at the SQL level: delete
-- the auth.users row. That is what actually drives every FK below, so that
-- is what this test performs directly rather than re-implementing the HTTP
-- call the Edge Function makes.
begin;
select plan(27);

select tests.as_postgres();

select tests.create_user('deleter');
select tests.create_user('bystander');

create temporary table ids as
select
  (select id from public.profiles where handle = 'deleter') as deleter,
  (select id from public.profiles where handle = 'bystander') as bystander;

-- A real signed-up user sets their own name and birthday during onboarding.
-- Set them here so this test can prove the post-delete SCRUB, not merely
-- assert against blanks tests.create_user would otherwise leave behind.
update public.profiles
set display_name = 'Self Entered Name',
    birth_month = 4, birth_day = 15, birth_year = 1990
where id = (select deleter from ids);

-- The deleter claims their own number (which copies the name/birthday just
-- set above onto the people row -- private.claim_person overwrites, it does
-- not merge), celebrates a contact (minting that contact's person row),
-- authors a wish, registers a device, and blocks the bystander. A bystander,
-- separately, celebrates the deleter's own number -- that edge belongs to
-- the bystander, not the deleter, and must not move -- and later blocks the
-- deleter right back, exercising blocks' OTHER foreign key.
create temporary table setup as
select
  private.claim_person((select deleter from ids), '+919280000099') as deleter_person,
  private.add_celebration((select deleter from ids), '+919280000001',
    'Cascade Contact', null::smallint, null::smallint, null::smallint) as contact_person;

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
select (select deleter from ids), (select contact_person from setup),
  'happy birthday!', 2026;

insert into public.device_tokens (profile_id, token, platform)
select (select deleter from ids), 'expo-token-delete-account-test', 'ios';

insert into private.notification_outbox
  (recipient_profile_id, subject_person_id, offset_days, occasion_date)
select (select deleter from ids), (select contact_person from setup), 7, current_date + 7;

-- A reminder queued about the DELETER's birthday, owed to someone else. This
-- is the row the scrub trigger has to delete on subject_person_id, not the
-- one above (which cascades on recipient_profile_id regardless of the scrub).
insert into private.notification_outbox
  (recipient_profile_id, subject_person_id, offset_days, occasion_date)
select (select bystander from ids), (select deleter_person from setup), 7, current_date + 7;

-- Must happen BEFORE the block below: guard_celebration rejects an insert
-- where the target profile has blocked the inserting celebrator, and the
-- block row that follows names exactly this pair.
select private.add_celebration((select bystander from ids), '+919280000099',
  'The Deleter', null::smallint, null::smallint, null::smallint);

insert into public.blocks (blocker_profile_id, blocked_profile_id)
select (select deleter from ids), (select bystander from ids);

-- The reverse direction: someone else blocks the deleter. Exercises
-- blocks.blocked_profile_id's OWN cascade, distinct from blocker_profile_id's.
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select (select bystander from ids), (select deleter from ids);

-- ---------------------------------------------------------------- before

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select deleter from ids)),
  1,
  'before: the deleter has one outgoing celebration edge'
);

select is(
  (select count(*)::int from public.wishes
    where author_profile_id = (select deleter from ids)),
  1,
  'before: the deleter authored one wish'
);

select is(
  (select count(*)::int from public.device_tokens
    where profile_id = (select deleter from ids)),
  1,
  'before: the deleter has one device token'
);

select is(
  (select count(*)::int from public.blocks
    where blocker_profile_id = (select deleter from ids)),
  1,
  'before: the deleter has one block row as blocker'
);

select is(
  (select count(*)::int from public.blocks
    where blocked_profile_id = (select deleter from ids)),
  1,
  'before: the deleter has one block row as the blocked party'
);

select is(
  (select count(*)::int from private.notification_outbox
    where recipient_profile_id = (select deleter from ids)),
  1,
  'before: the deleter has one queued notification as recipient'
);

select is(
  (select count(*)::int from private.notification_outbox
    where subject_person_id = (select deleter_person from setup)),
  1,
  'before: someone else has one queued notification about the deleter as subject'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select bystander from ids)
      and person_id = (select deleter_person from setup)),
  1,
  'before: the bystander already celebrates the deleter''s person row'
);

-- The surviving row, pre-scrub: it carries the deleter's REAL self-entered
-- name and birthday, copied in by claim_person -- not some bystander's
-- address-book guess.
select is(
  (select display_name || '|' || birth_month || '|' || birth_day || '|' || birth_year
     from public.people where id = (select deleter_person from setup)),
  'Self Entered Name|4|15|1990',
  'before: the surviving person row carries the deleter''s real self-entered name and birthday'
);

-- ---------------------------------------------------------------- the delete

-- This is the one statement that stands in for auth.admin.deleteUser: GoTrue
-- ultimately deletes this row, and public.profiles.id references it
-- ON DELETE CASCADE, which is what drives everything below (including the
-- BEFORE DELETE scrub trigger from 20260827000005, which runs first).
delete from auth.users where id = (select deleter from ids);

-- ---------------------------------------------------------------- after

select is(
  (select count(*)::int from public.profiles
    where id = (select deleter from ids)),
  0,
  'after: the profile is gone'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select deleter from ids)),
  0,
  'after: the deleter''s outgoing celebrations are gone'
);

select is(
  (select count(*)::int from public.wishes
    where author_profile_id = (select deleter from ids)),
  0,
  'after: the wish they authored is gone'
);

select is(
  (select count(*)::int from public.device_tokens
    where profile_id = (select deleter from ids)),
  0,
  'after: their device token is gone'
);

select is(
  (select count(*)::int from public.blocks
    where blocker_profile_id = (select deleter from ids)),
  0,
  'after: their block row as blocker is gone'
);

select is(
  (select count(*)::int from public.blocks
    where blocked_profile_id = (select deleter from ids)),
  0,
  'after: their block row as the blocked party is gone too'
);

select is(
  (select count(*)::int from private.notification_outbox
    where recipient_profile_id = (select deleter from ids)),
  0,
  'after: their queued notification as recipient is gone'
);

select is(
  (select count(*)::int from private.notification_outbox
    where subject_person_id = (select deleter_person from setup)),
  0,
  'after: the reminder someone else had queued about them is gone too'
);

-- The person row itself is the whole point: it must survive, unclaimed.
select is(
  (select count(*)::int from public.people
    where id = (select deleter_person from setup)),
  1,
  'after: the deleter''s own person row survives'
);

-- F4: a plain `is(profile_id, null)` also passes if the row does not exist
-- at all, so it would not have caught the row vanishing. Assert existence
-- and null-ness together against the same count.
select is(
  (select count(*)::int from public.people
    where id = (select deleter_person from setup) and profile_id is null),
  1,
  'after: that surviving person row exists and is now unclaimed'
);

-- The scrub itself: real data replaced with a placeholder, not real data
-- left sitting in an unclaimed row.
select is(
  (select display_name || '|' || coalesce(birth_month::text, 'NULL') || '|' ||
          coalesce(birth_day::text, 'NULL') || '|' || coalesce(birth_year::text, 'NULL')
     from public.people where id = (select deleter_person from setup)),
  'Deleted user|NULL|NULL|NULL',
  'after: the surviving person row is scrubbed to a placeholder name with no birthday'
);

-- The harm this whole migration exists to stop: with birth_month nulled,
-- enqueue_reminders must never queue a fresh reminder about this person
-- again, for anyone. Anchor p_today so an offset lands exactly on the
-- birthday that used to be on file (April 15) and prove nothing appears.
select private.enqueue_reminders('2026-04-15'::date);

select is(
  (select count(*)::int from private.notification_outbox
    where subject_person_id = (select deleter_person from setup)),
  0,
  'after: enqueue_reminders queues nothing for the scrubbed person even on their old birthday'
);

-- The bystander's edge is someone ELSE's row, not the deleter's: it must
-- survive untouched and keep pointing at the same (now-unclaimed, now-
-- scrubbed) person.
select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select bystander from ids)
      and person_id = (select deleter_person from setup)),
  1,
  'after: the bystander''s edge to that person survives'
);

-- A person row unrelated to the deleter -- the contact they imported -- is
-- untouched by any of this; only the deleter's own data cascades or scrubs.
select is(
  (select count(*)::int from public.people
    where id = (select contact_person from setup)),
  1,
  'after: an unrelated person row (the deleter''s own contact) is untouched'
);

select is(
  (select display_name from public.people
     where id = (select contact_person from setup)),
  'Cascade Contact',
  'after: that unrelated person row keeps its own real name -- only the deleter''s row was scrubbed'
);

-- ------------------------------------------ F5: pin the FK catalog for the
-- three profiles-referencing foreign keys M1 cannot exercise behaviourally
-- (all three need a gift, and M1 ships none). A future migration changing
-- any of these delete actions should fail a test, not surprise M3.
select is(
  (select confdeltype from pg_constraint
    where conname = 'gifts_sender_profile_id_fkey'),
  'r',
  'catalog: gifts.sender_profile_id is still ON DELETE RESTRICT'
);

select is(
  (select confdeltype from pg_constraint
    where conname = 'address_access_log_staff_profile_id_fkey'),
  'r',
  'catalog: address_access_log.staff_profile_id is still ON DELETE RESTRICT (immutable audit trail, no reassign/anonymise escape)'
);

select is(
  (select confdeltype from pg_constraint
    where conname = 'gift_events_actor_profile_id_fkey'),
  'n',
  'catalog: gift_events.actor_profile_id is still ON DELETE SET NULL'
);

select * from finish();
rollback;
