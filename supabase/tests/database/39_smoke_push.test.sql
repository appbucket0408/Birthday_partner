begin;
select plan(9);

-- It queues pushes to any member, so it must be as closed as the drain's own
-- wrappers: service_role and nobody else.
select ok(
  not has_function_privilege('anon', 'public.rpc_queue_test_push(uuid, text)', 'execute'),
  'anon must NOT queue test pushes');
select ok(
  not has_function_privilege('authenticated', 'public.rpc_queue_test_push(uuid, text)', 'execute'),
  'a signed-in user must NOT queue test pushes to anyone');
select ok(
  has_function_privilege('service_role', 'public.rpc_queue_test_push(uuid, text)', 'execute'),
  'service_role can: smoke-push.sh runs as it');

select tests.as_postgres();
select tests.create_user('smoke_me');
select tests.create_user('smoke_friend');
select tests.create_user('smoke_unclaimed');
select private.claim_person((select id from public.profiles where handle = 'smoke_me'), '+919390000001');
select private.claim_person((select id from public.profiles where handle = 'smoke_friend'), '+919390000002');

create temporary table ids as
select
  (select id from public.profiles where handle = 'smoke_me')        as me,
  (select id from public.profiles where handle = 'smoke_friend')    as friend,
  (select id from public.profiles where handle = 'smoke_unclaimed') as unclaimed,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'smoke_me'))     as me_person;

-- A reminder can be queued, delivered, and queued again.
select private.queue_test_push((select me from ids), 'reminder');
update private.notification_outbox set sent_at = now(), attempts = 3
where recipient_profile_id = (select me from ids);
select private.queue_test_push((select me from ids), 'reminder');
select is(
  (select count(*)::int || ',' || bool_and(sent_at is null)::text
          || ',' || max(attempts)::text
   from private.notification_outbox
   where recipient_profile_id = (select me from ids) and kind = 'reminder'),
  '1,true,0',
  're-running reuses the one row and resets it to unsent with fresh attempts'
);

-- A wish needs a real one on the wall.
select throws_like(
  $$ select private.queue_test_push((select me from ids), 'wish') $$,
  '%no wish by someone else%',
  'with no wish on the wall it says so rather than inventing one'
);

insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select friend from ids), (select me_person from ids), 'contacts';
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select friend from ids), (select me_person from ids), 'Smoke wish', 2026);

-- The trigger already queued it; the smoke call re-queues that same row.
update private.notification_outbox set sent_at = now()
where kind = 'wish' and recipient_profile_id = (select me from ids);
select private.queue_test_push((select me from ids), 'wish');
select is(
  (select count(*)::int || ',' || bool_and(sent_at is null)::text
   from private.notification_outbox
   where kind = 'wish' and recipient_profile_id = (select me from ids)),
  '1,true',
  'a wish smoke re-queues the real wish''s one notification, never a second'
);

select throws_like(
  $$ select private.queue_test_push((select unclaimed from ids), 'reminder') $$,
  '%no claimed person%',
  'a member who has not finished onboarding is refused clearly'
);
select throws_like(
  $$ select private.queue_test_push((select me from ids), 'anniversary') $$,
  '%unknown kind%',
  'an unknown kind is refused'
);
select is(
  (select count(*)::int from private.notification_outbox
   where recipient_profile_id = (select me from ids)),
  2,
  'nothing else was queued along the way'
);

select * from finish();
rollback;
