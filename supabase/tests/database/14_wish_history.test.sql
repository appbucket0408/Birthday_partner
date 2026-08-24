begin;
select plan(3);

select tests.as_postgres();
select tests.create_user('wellwisher');
select tests.create_user('recipient');
select private.claim_person((select id from public.profiles where handle = 'wellwisher'), '+919800000001');
select private.claim_person((select id from public.profiles where handle = 'recipient'), '+919800000002');

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'wellwisher'),
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'recipient')),
  'contacts'
);

create temporary table ids as
select
  (select id from public.profiles where handle = 'wellwisher') as author,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'recipient')) as subject;
grant select on ids to authenticated;

select tests.as_user((select author from ids));

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select auth.uid()), (select subject from ids), 'Have a good one',
        extract(year from current_date)::int);

select is(
  (select count(*)::int from public.wishes),
  1,
  'an author sees the wish they just posted'
);

-- Now stop celebrating them. The edge is what can_see_person depends on.
delete from public.celebrations where celebrator_profile_id = (select auth.uid());

select is(
  (select count(*)::int from public.people),
  1,
  'after un-celebrating, the subject is no longer visible as a person'
);

-- The wish is history. It must survive the graph changing under it.
select is(
  (select count(*)::int from public.wishes),
  1,
  'an author still sees their own wish after un-celebrating the subject'
);

select * from finish();
rollback;
