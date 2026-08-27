-- delete_account (Task 7) is a database cascade wearing an Edge Function's
-- clothes: the function's only real work is calling auth.admin.deleteUser,
-- and everything that follows is `on delete` behaviour already declared on
-- the schema. The Edge Function's own proof of that (a shell script with
-- before/after row counts) evaporates the moment the terminal scrolls away.
-- This file pins the documented cascade table for good:
--
--   cascades away: profiles, their outgoing celebrations, wishes they
--     authored, their device_tokens, their blocks, their queued
--     notification_outbox rows
--   survives: their own people row (profile_id set NULL), and every OTHER
--     profile's celebration edge still pointing at that now-unclaimed row
--
-- auth.admin.deleteUser ultimately does one thing at the SQL level: delete
-- the auth.users row. That is what actually drives every FK below, so that
-- is what this test performs directly rather than re-implementing the HTTP
-- call the Edge Function makes.
begin;
select plan(16);

select tests.as_postgres();

select tests.create_user('deleter');
select tests.create_user('bystander');

create temporary table ids as
select
  (select id from public.profiles where handle = 'deleter') as deleter,
  (select id from public.profiles where handle = 'bystander') as bystander;

-- The deleter claims their own number, celebrates a contact (minting that
-- contact's person row), authors a wish, registers a device, and blocks the
-- bystander. A bystander, separately, celebrates the deleter's own number --
-- that edge belongs to the bystander, not the deleter, and must not move.
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

-- Must happen BEFORE the block below: guard_celebration rejects an insert
-- where the target profile has blocked the inserting celebrator, and the
-- block row that follows names exactly this pair.
select private.add_celebration((select bystander from ids), '+919280000099',
  'The Deleter', null::smallint, null::smallint, null::smallint);

insert into public.blocks (blocker_profile_id, blocked_profile_id)
select (select deleter from ids), (select bystander from ids);

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
  'before: the deleter has one block row'
);

select is(
  (select count(*)::int from private.notification_outbox
    where recipient_profile_id = (select deleter from ids)),
  1,
  'before: the deleter has one queued notification'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select bystander from ids)
      and person_id = (select deleter_person from setup)),
  1,
  'before: the bystander already celebrates the deleter''s person row'
);

-- ---------------------------------------------------------------- the delete

-- This is the one statement that stands in for auth.admin.deleteUser: GoTrue
-- ultimately deletes this row, and public.profiles.id references it
-- ON DELETE CASCADE, which is what drives everything below.
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
  'after: their block row is gone'
);

select is(
  (select count(*)::int from private.notification_outbox
    where recipient_profile_id = (select deleter from ids)),
  0,
  'after: their queued notification is gone'
);

-- The person row itself is the whole point: it must survive, unclaimed.
select is(
  (select count(*)::int from public.people
    where id = (select deleter_person from setup)),
  1,
  'after: the deleter''s own person row survives'
);

select is(
  (select profile_id from public.people
    where id = (select deleter_person from setup)),
  null,
  'after: that surviving person row is now unclaimed'
);

-- The bystander's edge is someone ELSE's row, not the deleter's: it must
-- survive untouched and keep pointing at the same (now-unclaimed) person.
select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select bystander from ids)
      and person_id = (select deleter_person from setup)),
  1,
  'after: the bystander''s edge to that person survives'
);

-- A person row unrelated to the deleter -- the contact they imported -- is
-- untouched by any of this; only celebrations owned by the deleter cascade.
select is(
  (select count(*)::int from public.people
    where id = (select contact_person from setup)),
  1,
  'after: an unrelated person row (the deleter''s own contact) is untouched'
);

select * from finish();
rollback;
