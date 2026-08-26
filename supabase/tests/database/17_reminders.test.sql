begin;
select plan(21);

select has_table('private', 'notification_outbox', 'the outbox exists');

select tests.as_postgres();
select tests.create_user('remindme');
select private.claim_person((select id from public.profiles where handle = 'remindme'), '+919110000001');

-- A friend whose birthday is exactly seven days from a fixed reference date.
-- The reference date is passed in, so these assertions never depend on today.
select tests.create_person('+919110000002', 'Week Away', 1::smallint, 8::smallint);
select tests.create_person('+919110000003', 'Leap Friend', 2::smallint, 29::smallint);

insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select id from public.profiles where handle = 'remindme'), p.id, 'contacts'
from public.people p where p.display_name in ('Week Away', 'Leap Friend');

-- December-to-January wraparound: reference 2027-01-01, T-7 lands on 2027-01-08.
select is(
  private.enqueue_reminders(date '2027-01-01'),
  1,
  'a birthday seven days ahead across the new year is queued'
);

select is(
  (select offset_days || ' on ' || occasion_date
     from private.notification_outbox
     order by id desc limit 1),
  '7 on 2027-01-08',
  'the queued row carries the T-7 offset and the occasion date'
);

-- Running the same day twice must not double-send. The unique constraint is the
-- guarantee; this asserts it is actually doing the work.
select is(
  private.enqueue_reminders(date '2027-01-01'),
  0,
  'a second run on the same day queues nothing'
);

select is(
  (select count(*)::int from private.notification_outbox),
  1,
  'and the outbox still holds exactly one row'
);

-- Feb 29 in a non-leap year fires on Feb 28, so a T-0 run on 2027-02-28 finds it.
select is(
  private.enqueue_reminders(date '2027-02-28'),
  1,
  'a Feb 29 birthday is reminded on Feb 28 in a non-leap year'
);

-- ...and in a leap year it fires on the real date, not twice.
select is(
  private.enqueue_reminders(date '2028-02-29'),
  1,
  'in a leap year the Feb 29 birthday fires on Feb 29'
);

-- The drain sees only rows with a device to send to.
select tests.as_postgres();
select is(
  (select count(*)::int from private.next_reminder_batch()),
  0,
  'a user with no registered device yields nothing to send'
);

insert into public.device_tokens (profile_id, token, platform)
values ((select id from public.profiles where handle = 'remindme'), 'fcm-remind', 'android');

select isnt_empty(
  $$ select outbox_id from private.next_reminder_batch() $$,
  'once a device is registered the batch has work'
);

-- The batch CLAIMS. A second drain arriving immediately must get nothing.
select is(
  (select count(*)::int from private.next_reminder_batch()),
  0,
  'a second drain gets nothing because the first claimed the batch'
);

-- A sent row never returns, even once its claim lease has expired.
-- Every row in the outbox is marked sent, not just the first: assertions 6 and 7
-- added two more rows after "the outbox still holds exactly one row", so marking
-- only `order by id limit 1` would leave two genuinely-eligible rows behind and
-- the count below would be 2 for a reason that has nothing to do with sent_at.
-- Marking all three still tests exactly what the assertion claims -- were the
-- `sent_at is null` filter dropped from the claim, this would return 3 and fail.
select private.mark_reminder_sent(o.id) from private.notification_outbox o;
update private.notification_outbox set claimed_at = null;
select is(
  (select count(*)::int from private.next_reminder_batch()),
  0,
  'a sent reminder never comes back'
);

-- attempts advances at CLAIM time now, so a failure's observable effect is
-- last_error. Assert that, or this proves only that some earlier claim
-- incremented a counter.
select private.mark_reminder_failed(
  (select id from private.notification_outbox order by id limit 1), 'fcm 500');
select is(
  (select last_error from private.notification_outbox order by id limit 1),
  'fcm 500',
  'a failed delivery records why'
);

-- The counter has to advance somewhere or the retry cap never engages. It is
-- the claim that does it, which is what bounds a drain that dies mid-send.
update private.notification_outbox
set sent_at = null, claimed_at = null, attempts = 0;
select private.next_reminder_batch();
select is(
  (select max(attempts) from private.notification_outbox),
  1,
  'claiming a reminder counts an attempt'
);

update private.notification_outbox set sent_at = null, claimed_at = null, attempts = 5;
select is(
  (select count(*)::int from private.next_reminder_batch()),
  0,
  'a reminder that has failed five times is not retried'
);

-- F5(a): one claimed reminder must not become an unbounded number of FCM
-- calls. A user may register unlimited devices; the lateral join in
-- next_reminder_batch bounds it to five per reminder, regardless of how many
-- device rows exist for the recipient.
delete from private.notification_outbox;
delete from public.device_tokens
where profile_id = (select id from public.profiles where handle = 'remindme');

insert into public.device_tokens (profile_id, token, platform)
select (select id from public.profiles where handle = 'remindme'),
       'fcm-remind-' || g, 'android'
from generate_series(1, 6) g;

select private.enqueue_reminders(date '2027-01-01');
select is(
  (select count(*)::int from private.next_reminder_batch()),
  5,
  'a recipient with six registered devices yields at most five rows for one reminder'
);

-- The lease is what stops a crashed drain stranding rows forever. Age a claim
-- past it rather than clearing it, or the expiry branch is never exercised and
-- the interval could be changed to anything without failing a test.
update private.notification_outbox
set sent_at = null, claimed_at = now() - interval '11 minutes', attempts = 0;
select isnt_empty(
  $$ select outbox_id from private.next_reminder_batch() $$,
  'a claim older than the lease is reclaimable'
);

-- The Edge Function calls this wrapper rather than the private function
-- directly, so it is worth proving the wrapper actually returns rows, not
-- merely that it exists and is callable. The outbox's only row was claimed by
-- the lease-expiry assertion above and is therefore ineligible, so seed a
-- fresh eligible reminder first -- a distinct (subject, occasion_date, offset)
-- so it cannot collide with that claimed row under notification_outbox_once.
insert into private.notification_outbox (
  recipient_profile_id, subject_person_id, offset_days, occasion_date
)
values (
  (select id from public.profiles where handle = 'remindme'),
  (select id from public.people where display_name = 'Leap Friend'),
  7,
  date '2027-02-28'
);

select isnt_empty(
  $$ select outbox_id from public.rpc_next_reminder_batch(1) $$,
  'the service_role wrapper passes rows through, not just exists'
);

-- Offset 1 is otherwise never exercised anywhere in this file.
-- The fan-out is called as its own statement rather than from the assertion's
-- WHERE clause: the outbox is empty at that point, so a qual on the scan of it
-- would never be evaluated and the sub-select would return null regardless of
-- what the fan-out did.
select tests.as_postgres();
delete from private.notification_outbox;
select private.enqueue_reminders(date '2027-01-07');
select is(
  (select o.offset_days || ' on ' || o.occasion_date
     from private.notification_outbox o
    order by o.id desc limit 1),
  '1 on 2027-01-08',
  'a birthday tomorrow is queued at offset 1'
);

-- The highest-risk path in the task: in a leap year, T-1 (2028-02-28) must
-- match Feb 29 via the plain birth_day arm, not via the Feb-28 fallback arm
-- that exists for non-leap years. This proves which arm matched, not that a
-- duplicate is impossible -- the two arms are OR-ed inside one predicate, so
-- this assertion cannot distinguish "one arm matched" from "no double-fire".
delete from private.notification_outbox;
select is(
  private.enqueue_reminders(date '2028-02-28') || ' row(s)',
  '1 row(s)',
  'in a leap year T-1 matches the real Feb 29, not the Feb-28 fallback'
);

-- A block must stop the fan-out, not just the read paths.
-- Built explicitly rather than selected out of the existing fixture: the people
-- created by tests.create_person carry no profile_id, so there is no profile to
-- block with. 'Week Away' and 'Leap Friend' also have to stop being celebrated
-- first -- Week Away's Jan 8 birthday fires at offset 7 from 2027-01-01, which
-- would mask the block entirely. What is left is one edge, pointing at a person
-- who has a profile, and that profile blocks the celebrator.
delete from private.notification_outbox;
select tests.create_user('blockerguy');
select private.claim_person(
  (select id from public.profiles where handle = 'blockerguy'), '+919110000004');
update public.people
set birth_month = 1::smallint, birth_day = 8::smallint
where phone_e164_hash = private.phone_hash('+919110000004');

delete from public.celebrations
where celebrator_profile_id = (select id from public.profiles where handle = 'remindme');

-- The edge has to predate the block: private.guard_celebration refuses to
-- create an edge towards someone who has already blocked you.
insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'remindme'),
  (select id from public.people where phone_e164_hash = private.phone_hash('+919110000004')),
  'contacts');

insert into public.blocks (blocker_profile_id, blocked_profile_id)
values (
  (select id from public.profiles where handle = 'blockerguy'),
  (select id from public.profiles where handle = 'remindme'));

select is(
  private.enqueue_reminders(date '2027-01-01'),
  0,
  'a blocked celebrator gets no reminder about the person who blocked them'
);

-- The fan-out is useless unless something runs it, and pg_cron stores schedules
-- as rows — so assert the whole job, not just its timing. A job pointed at the
-- wrong function, or left inactive, would silently mean no reminders ever fire.
select is(
  (select j.jobname || ' | ' || j.schedule || ' | ' || btrim(j.command) || ' | active=' || j.active
     from cron.job j
    where j.jobname = 'birthday-reminder-fanout'),
  'birthday-reminder-fanout | 0 3 * * * | select private.enqueue_reminders(); | active=true',
  'the reminder fan-out is scheduled daily and enabled'
);

select * from finish();
rollback;
