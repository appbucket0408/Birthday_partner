begin;
select plan(26);

select tests.as_postgres();
select tests.create_user('rb_author');
select tests.create_user('rb_blocker');
select tests.create_user('rb_viewer');
select tests.create_user('rb_staff');
update public.profiles set is_staff = true where handle = 'rb_staff';
select private.claim_person((select id from public.profiles where handle = 'rb_author'), '+919390000001');
select private.claim_person((select id from public.profiles where handle = 'rb_blocker'), '+919390000002');
select private.claim_person((select id from public.profiles where handle = 'rb_viewer'), '+919390000003');

create temporary table ids as
select
  (select id from public.profiles where handle = 'rb_author')  as author,
  (select id from public.profiles where handle = 'rb_blocker') as blocker,
  (select id from public.profiles where handle = 'rb_viewer')  as viewer,
  (select id from public.profiles where handle = 'rb_staff')   as staff,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'rb_author'))  as author_person,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'rb_blocker')) as blocker_person;
grant select on ids to authenticated;

-- They celebrate each other; the viewer knows neither.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select author from ids), (select blocker_person from ids), 'contacts'
union all
select (select blocker from ids), (select author_person from ids), 'contacts';

select tests.as_user((select author from ids));
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select auth.uid()), (select blocker_person from ids), 'Happy birthday!', 2026);
select tests.as_postgres();

create temporary table wish as
select id from public.wishes
where author_profile_id = (select author from ids);
grant select on wish to authenticated;

-- ------------------------------------------------------------------ report

select tests.as_user((select viewer from ids));

select is(
  (select count(*)::int from public.feed_page() where id = (select id from wish)),
  1,
  'a stranger sees a member''s wall post in the public feed'
);

select lives_ok(
  $$ select public.rpc_report_wish((select id from wish), 'spam', ' looks like spam ') $$,
  'a stranger can report a post they see in the feed'
);

select is(
  (select count(*)::int from public.feed_page() where id = (select id from wish)),
  0,
  'a reported post disappears from the reporter''s feed'
);

select lives_ok(
  $$ select public.rpc_report_wish((select id from wish), 'harassment') $$,
  'reporting the same post twice is not an error'
);

select throws_ok(
  $$ select public.rpc_report_wish((select id from wish) + 1000, 'spam') $$,
  'P0002',
  null,
  'a post that does not exist is not found'
);

select is_empty(
  $$ select 1 from public.reports $$,
  'a reporter cannot read reports, not even their own'
);

select tests.as_user((select author from ids));

select throws_ok(
  $$ select public.rpc_report_wish((select id from wish), 'spam') $$,
  'P0002',
  null,
  'nobody reports their own post'
);

select tests.as_user((select blocker from ids));

select throws_ok(
  $$ select public.rpc_report_wish((select id from wish), 'rude') $$,
  '23514',
  null,
  'only the listed reasons are accepted'
);

select tests.as_postgres();

select is(
  (select count(*)::int from public.reports where wish_id = (select id from wish)),
  1,
  'a double report is one row'
);

select is(
  (select note from public.reports where wish_id = (select id from wish)),
  'looks like spam',
  'the note is trimmed'
);

select is(
  (select wish_body from public.reports where wish_id = (select id from wish)),
  'Happy birthday!',
  'the post''s text is kept on the report as evidence'
);

-- ------------------------------------------------------------------- block

select tests.as_user((select blocker from ids));

select is(
  (select count(*)::int from public.wishes where id = (select id from wish)),
  1,
  'before blocking, the post is on my wall'
);

select lives_ok(
  $$ insert into public.blocks (blocker_profile_id, blocked_profile_id)
     values ((select auth.uid()), (select author from ids)) $$,
  'I can block someone'
);

select tests.as_postgres();

select is(
  (select count(*)::int from public.celebrations
    where (celebrator_profile_id = (select author from ids)
           and person_id = (select blocker_person from ids))
       or (celebrator_profile_id = (select blocker from ids)
           and person_id = (select author_person from ids))),
  0,
  'blocking removes the celebrations between us in both directions'
);

select tests.as_user((select blocker from ids));

select is(
  (select count(*)::int from public.wishes where id = (select id from wish)),
  0,
  'their post is hidden from my wall'
);

select is(
  (select count(*)::int from public.feed_page()
    where author_profile_id = (select author from ids)),
  0,
  'their posts are hidden from my feed'
);

select results_eq(
  $$ select profile_id, display_name from public.my_blocked_users() $$,
  $$ select (select author from ids), 'Rb_author'::text $$,
  'they are on my blocked list, by the name they chose'
);

select tests.as_user((select author from ids));

select is(
  (select count(*)::int from public.people where id = (select blocker_person from ids)),
  0,
  'the blocked person can no longer see the blocker'
);

select throws_ok(
  $$ insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
     values ((select auth.uid()), (select blocker_person from ids), 'Hi again', 2027) $$,
  '42501',
  null,
  'the blocked person cannot wish the blocker'
);

select tests.as_postgres();

select throws_ok(
  $$ insert into public.celebrations (celebrator_profile_id, person_id, source)
     values ((select author from ids), (select blocker_person from ids), 'contacts') $$,
  'this person has blocked you',
  'the blocked person cannot celebrate the blocker again'
);

select throws_ok(
  $$ insert into public.celebrations (celebrator_profile_id, person_id, source)
     values ((select blocker from ids), (select author_person from ids), 'contacts') $$,
  'you have blocked this person',
  'nor can the blocker, while the block stands'
);

-- --------------------------------------------------------------------- ops

select tests.as_user((select viewer from ids));

select throws_ok(
  $$ select * from public.ops_open_reports() $$,
  '42501',
  null,
  'only staff can read the review queue'
);

select lives_ok(
  $$ select public.rpc_report_user((select author from ids), 'harassment') $$,
  'a person can be reported too'
);

select tests.as_user((select staff from ids));

select results_eq(
  $$ select wish_id, wish_body, wish_still_exists, report_count
     from public.ops_open_reports() where wish_id is not null $$,
  $$ select (select id from wish), 'Happy birthday!'::text, true, 1 $$,
  'staff see the open post report with its text'
);

select throws_ok(
  $$ select public.ops_resolve_report(
       (select id from public.reports where wish_id is null), 'remove') $$,
  '22023',
  null,
  'a person report has no post to remove'
);

select public.ops_resolve_report(
  (select id from public.reports where wish_id = (select id from wish)), 'remove');

select tests.as_postgres();

select results_eq(
  $$ select (select count(*)::int from public.wishes where id = (select id from wish)),
            (select count(*)::int from public.reports
              where status = 'removed' and wish_body = 'Happy birthday!'
                and reviewed_by = (select staff from ids)) $$,
  $$ values (0, 1) $$,
  'removing deletes the post and closes the report, keeping its evidence'
);

select * from finish();
rollback;
