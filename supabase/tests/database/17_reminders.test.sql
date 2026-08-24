begin;
select plan(9);

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

select * from finish();
rollback;
