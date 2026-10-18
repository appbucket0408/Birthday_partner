begin;
select plan(11);

select ok(
  not has_function_privilege('anon', 'public.my_notifications(timestamptz, int)', 'execute'),
  'anon cannot list notifications');
select ok(
  not has_function_privilege('anon', 'public.mark_notifications_seen()', 'execute'),
  'anon cannot mark notifications seen');

select tests.as_postgres();
select tests.create_user('inbox_me');
select tests.create_user('inbox_author');
select tests.create_user('inbox_other');
select private.claim_person((select id from public.profiles where handle = 'inbox_me'), '+919410000001');
select private.claim_person((select id from public.profiles where handle = 'inbox_author'), '+919410000002');
select private.claim_person((select id from public.profiles where handle = 'inbox_other'), '+919410000003');

create temporary table ids as
select
  (select id from public.profiles where handle = 'inbox_me')     as me,
  (select id from public.profiles where handle = 'inbox_author') as author,
  (select id from public.profiles where handle = 'inbox_other')  as other,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'inbox_me'))     as me_person,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'inbox_author')) as author_person,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'inbox_other'))  as other_person;
grant select on ids to authenticated;

-- A wish for me (queued by the trigger), a reminder for me, and a reminder
-- for someone else that I must never see.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select author from ids), (select me_person from ids), 'contacts';
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select author from ids), (select me_person from ids), 'Inbox wish', 2026);
insert into private.notification_outbox
  (recipient_profile_id, subject_person_id, offset_days, occasion_date, created_at)
values
  ((select me from ids), (select author_person from ids), 1, date '2027-05-02',
   now() - interval '1 hour'),
  ((select other from ids), (select author_person from ids), 1, date '2027-05-02',
   now());

-- The author's people row and profile differ, so the inbox has to choose,
-- the same way the push does (profile first: see 38_wish_notifications).
update public.profiles set display_name = 'Asha Profile' where id = (select author from ids);
update public.people set display_name = 'Asha From Contacts' where id = (select author_person from ids);

select tests.as_user((select me from ids));

select is(
  (select count(*)::int from public.my_notifications()),
  2,
  'I see my two notifications and not the one queued for someone else'
);

select is(
  (select kind || ',' || author_name || ',' || (person_id = (select me_person from ids))::text
          || ',' || (wish_id is not null)::text
   from public.my_notifications() where kind = 'wish'),
  'wish,Asha From Contacts,true,true',
  'a wish names its author as the push does, and routes to my own wall'
);

select is(
  (select kind || ',' || subject_name || ',' || offset_days::text
   from public.my_notifications() where kind = 'reminder'),
  'reminder,Asha From Contacts,1',
  'a reminder carries who and when'
);

select is(
  (select string_agg(kind, ',' order by created_at desc) from public.my_notifications()),
  'wish,reminder',
  'newest first'
);

select is(
  (select count(*)::int from public.my_notifications(p_limit => 1)),
  1,
  'the limit applies'
);

select is(public.my_unseen_notification_count(), 2, 'both start unseen');
select is(public.mark_notifications_seen(), 2, 'opening the screen marks both seen');
select is(public.my_unseen_notification_count(), 0, 'and the bell clears');

-- Marking mine touched nobody else's.
select tests.as_postgres();
select is(
  (select count(*)::int from private.notification_outbox
   where recipient_profile_id = (select other from ids) and seen_at is null),
  1,
  'another member''s notification is still unseen'
);

select * from finish();
rollback;
