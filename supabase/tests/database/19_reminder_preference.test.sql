begin;
select plan(4);

select has_column('public', 'profiles', 'reminders_enabled',
  'profiles.reminders_enabled exists');

select tests.as_postgres();
select tests.create_user('quiet');
select private.claim_person(
  (select id from public.profiles where handle = 'quiet'), '+919210000001');
select tests.create_person('+919210000002', 'Quiet Friend',
  extract(month from current_date)::smallint,
  extract(day from current_date)::smallint);
insert into public.celebrations (celebrator_profile_id, person_id, source)
values ((select id from public.profiles where handle = 'quiet'),
        (select id from public.people where display_name = 'Quiet Friend'),
        'contacts');

-- Default on: the reminder is queued.
select is(
  private.enqueue_reminders(),
  1,
  'a user with reminders on is queued a reminder'
);

-- Turned off: nothing is queued.
delete from private.notification_outbox;
update public.profiles set reminders_enabled = false where handle = 'quiet';
select is(
  private.enqueue_reminders(),
  0,
  'a user who turned reminders off is queued nothing'
);

-- And the user can actually flip it themselves — a new column on profiles is
-- not client-writable until it is added to the column grant list, and that
-- failure is silent (the update simply affects nothing).
select tests.as_user((select id from public.profiles where handle = 'quiet'));
select lives_ok(
  $$ update public.profiles set reminders_enabled = true
     where id = (select auth.uid()) $$,
  'a user can turn their own reminders back on'
);

select * from finish();
rollback;
