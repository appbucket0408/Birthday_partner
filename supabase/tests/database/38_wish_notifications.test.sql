begin;
select plan(25);

select has_column('public', 'profiles', 'wish_notifications_enabled',
  'profiles.wish_notifications_enabled exists');
select col_default_is('public', 'profiles', 'wish_notifications_enabled',
  'true', 'wish notifications default on');

select tests.as_postgres();
select tests.create_user('wn_author');
select tests.create_user('wn_kid');
select tests.create_user('wn_other');
-- Never claims a person row: a member who has only a profile.
select tests.create_user('wn_noperson');
select private.claim_person((select id from public.profiles where handle = 'wn_author'), '+919380000001');
select private.claim_person((select id from public.profiles where handle = 'wn_kid'), '+919380000002');
select private.claim_person((select id from public.profiles where handle = 'wn_other'), '+919380000003');
select tests.create_person('+919380000004', 'Unclaimed Pal');

-- Resolved as postgres, for the same reason as 09_wishes (R22): an
-- authenticated session cannot read other users' profiles.
create temporary table ids as
select
  (select id from public.profiles where handle = 'wn_author')   as author,
  (select id from public.profiles where handle = 'wn_kid')      as kid,
  (select id from public.profiles where handle = 'wn_other')    as other,
  (select id from public.profiles where handle = 'wn_noperson') as noperson,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'wn_kid'))   as kid_person,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'wn_author')) as author_person,
  (select id from public.people where display_name = 'Unclaimed Pal') as pal_person;
grant select on ids to authenticated;

insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select author from ids), (select kid_person from ids), 'contacts'
union all
select (select author from ids), (select pal_person from ids), 'contacts'
union all
select (select noperson from ids), (select kid_person from ids), 'contacts';

-- ------------------------------------------------------------ the trigger

-- Posted the way the app posts: as the author, through wishes_insert_own.
-- The trigger is security definer, so it can queue for a recipient whose
-- profile the author cannot even read.
select tests.as_user((select author from ids));
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select auth.uid()), (select kid_person from ids), 'Happy birthday!', 2026);
select tests.as_postgres();

select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.author_profile_id = (select author from ids)
     and w.subject_person_id = (select kid_person from ids)),
  1,
  'a wish about a member queues exactly one notification'
);

select is(
  (select o.kind || ',' || (o.recipient_profile_id = (select kid from ids))::text
          || ',' || (o.subject_person_id = (select kid_person from ids))::text
          || ',' || coalesce(o.offset_days::text, 'null')
          || ',' || coalesce(o.occasion_date::text, 'null')
   from private.notification_outbox o where o.kind = 'wish'),
  'wish,true,true,null,null',
  'the row is a wish, for the member, about their own person, with no reminder fields'
);

-- Idempotency is a CONSTRAINT, not the trigger's good behaviour.
select throws_ok(
  $$ insert into private.notification_outbox
       (recipient_profile_id, subject_person_id, kind, wish_id)
     select recipient_profile_id, subject_person_id, 'wish', wish_id
     from private.notification_outbox where kind = 'wish' $$,
  '23505',
  null,
  'a second notification for the same wish is refused by the database'
);

-- Each kind's shape is enforced: no hybrid rows.
select throws_ok(
  $$ insert into private.notification_outbox
       (recipient_profile_id, subject_person_id, kind, wish_id, offset_days)
     select recipient_profile_id, subject_person_id, 'wish', wish_id, 0
     from private.notification_outbox where kind = 'wish' $$,
  '23514',
  null,
  'a wish row cannot carry a reminder offset'
);
select throws_ok(
  $$ insert into private.notification_outbox
       (recipient_profile_id, subject_person_id, offset_days)
     values ((select kid from ids), (select author_person from ids), 0) $$,
  '23514',
  null,
  'a reminder row still needs its occasion date'
);

-- ------------------------------------------------------------ skip rules

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select author from ids), (select pal_person from ids), 'Hi pal', 2026);
select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.subject_person_id = (select pal_person from ids)),
  0,
  'a wish about an unclaimed contact queues nothing: there is no member to tell'
);

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select kid from ids), (select kid_person from ids), 'Note to self', 2026);
select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.author_profile_id = (select kid from ids)),
  0,
  'a wish on your own wall queues nothing'
);

insert into public.wishes (author_profile_id, subject_person_id, body, kind, occasion_year)
values ((select author from ids), (select kid_person from ids), 'sent a cake', 'cake', 2026);
select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.kind = 'cake'),
  0,
  'a cake post queues nothing: only written wishes notify'
);

-- The preference, written by the member themselves through the column grant.
select tests.as_user((select kid from ids));
update public.profiles set wish_notifications_enabled = false
where id = (select auth.uid());
select is(
  (select wish_notifications_enabled from public.profiles where id = (select auth.uid())),
  false,
  'a member can turn wish notifications off themselves'
);
select tests.as_postgres();

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select author from ids), (select kid_person from ids), 'Muted wish', 2027);
select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.occasion_year = 2027),
  0,
  'a member who turned wish notifications off is queued nothing'
);

-- Reminders are a separate switch and stay on.
select is(
  (select reminders_enabled from public.profiles where id = (select kid from ids)),
  true,
  'turning wish notifications off leaves reminders alone'
);

update public.profiles set wish_notifications_enabled = true
where id = (select kid from ids);

-- A block: the blocked author's wish does not reach the blocker.
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select (select kid from ids), (select other from ids);
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select other from ids), (select kid_person from ids), 'From a blocked user', 2026);
select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.author_profile_id = (select other from ids)),
  0,
  'a wish from someone the member blocked queues nothing'
);

-- An author with no person row (profile only). Still notifies.
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select noperson from ids), (select kid_person from ids), 'From a new member', 2026);
select is(
  (select count(*)::int from private.notification_outbox o
   join public.wishes w on w.id = o.wish_id
   where w.author_profile_id = (select noperson from ids)),
  1,
  'a wish from a member without a person row is queued'
);

-- ------------------------------------------------------------ the batch

-- The author's people row and profile carry DIFFERENT names, so the batch
-- has to choose: the recipient sees the people row (the author celebrates
-- them, can_see_person's third branch), exactly as their wall shows it.
-- Profile first: private.sync_person_from_profile copies a profile's name
-- onto its person row, so the other order would leave them equal and this
-- would prove nothing.
update public.profiles set display_name = 'Asha Profile'
where id = (select author from ids);
update public.people set display_name = 'Asha From Contacts'
where id = (select author_person from ids);
update public.profiles set display_name = 'Newbie Profile'
where id = (select noperson from ids);

-- One reminder alongside, so the batch is checked for both kinds at once.
insert into private.notification_outbox
  (recipient_profile_id, subject_person_id, offset_days, occasion_date)
values ((select kid from ids), (select author_person from ids), 0, date '2027-03-01');

insert into public.device_tokens (profile_id, token, platform)
values ((select kid from ids), 'fcm-wish-kid', 'android');

create temporary table batch as
select * from private.next_reminder_batch(100);

select is(
  (select count(*)::int from batch),
  3,
  'one claim returns both kinds: two wishes and one reminder'
);

select is(
  (select author_name from batch b
   join public.wishes w on w.id = b.wish_id
   where w.author_profile_id = (select author from ids)),
  'Asha From Contacts',
  'a wish carries the author name the recipient sees in the app, not the profile name'
);

select is(
  (select author_name from batch b
   join public.wishes w on w.id = b.wish_id
   where w.author_profile_id = (select noperson from ids)),
  'Newbie Profile',
  'an author with no visible person row is named by their own profile, as feed_page does'
);

select is(
  (select b.kind || ',' || (b.subject_person_id = (select kid_person from ids))::text
          || ',' || coalesce(b.offset_days::text, 'null')
   from batch b
   join public.wishes w on w.id = b.wish_id
   where w.author_profile_id = (select author from ids)),
  'wish,true,null',
  'a wish row routes to the recipient''s own person and carries no offset'
);

select is(
  (select kind || ',' || subject_name || ',' || offset_days::text
          || ',' || coalesce(author_name, 'null') || ',' || coalesce(wish_id::text, 'null')
   from batch where kind = 'reminder'),
  'reminder,Asha From Contacts,0,null,null',
  'a reminder row is unchanged: subject name and offset, no author or wish'
);

-- The claim, the lease and release work the same for a wish row.
select is(
  (select count(*)::int from private.next_reminder_batch(100)),
  0,
  'a second drain gets nothing: the wish rows were claimed with the reminder'
);
select is(
  private.release_reminder_claims(
    array(select outbox_id from batch where kind = 'wish')),
  2,
  'release_reminder_claims gives a wish row''s attempt back like a reminder''s'
);

-- ------------------------------------------------------------ deletion

-- An author deleting their account cascades their wishes, and the wish_id
-- foreign key takes the notification with them.
delete from auth.users where id = (select noperson from ids);
select is(
  (select count(*)::int from private.notification_outbox o
   where o.kind = 'wish'
     and not exists (select 1 from public.wishes w where w.id = o.wish_id)),
  0,
  'no wish notification outlives its wish'
);
select is(
  (select count(*)::int from private.notification_outbox where kind = 'wish'),
  1,
  'only the deleted author''s notification went'
);

-- The recipient deleting theirs removes every notification owed to them.
delete from auth.users where id = (select kid from ids);
select is(
  (select count(*)::int from private.notification_outbox
   where subject_person_id = (select kid_person from ids)),
  0,
  'a deleted member is owed no notifications'
);

select * from finish();
rollback;
