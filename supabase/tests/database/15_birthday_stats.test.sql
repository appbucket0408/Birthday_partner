begin;
select plan(4);

select tests.as_postgres();
select tests.create_user('counter');
select tests.create_user('friendone');
select tests.create_user('friendtwo');
select private.claim_person((select id from public.profiles where handle = 'counter'), '+919900000001');
select private.claim_person((select id from public.profiles where handle = 'friendone'), '+919900000002');
select private.claim_person((select id from public.profiles where handle = 'friendtwo'), '+919900000003');

-- counter celebrates both friends; friendone celebrates counter back.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select id from public.profiles where handle = 'counter'), p.id, 'contacts'
from public.people p
where p.profile_id in (
  select id from public.profiles where handle in ('friendone', 'friendtwo'));

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'friendone'),
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'counter')),
  'contacts'
);

create temporary table ids as
select
  (select id from public.profiles where handle = 'counter') as me,
  (select id from public.profiles where handle = 'friendone') as f_one,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'friendone')) as p_one,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'friendtwo')) as p_two,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'counter')) as p_me,
  extract(year from current_date)::int as this_year;
grant select on ids to authenticated;

-- counter wishes both friends; friendone wishes counter.
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values
  ((select me from ids),    (select p_one from ids), 'Happy day one', (select this_year from ids)),
  ((select me from ids),    (select p_two from ids), 'Happy day two', (select this_year from ids)),
  ((select f_one from ids), (select p_me from ids),  'You too',       (select this_year from ids));

select tests.as_user((select me from ids));

select is(
  (select wishes_sent from public.my_birthday_stats()
    where stat_year = (select this_year from ids)),
  2,
  'wishes sent counts both wishes I wrote'
);

select is(
  (select wishes_received from public.my_birthday_stats()
    where stat_year = (select this_year from ids)),
  1,
  'wishes received counts the wish written to me'
);

select is(
  (select birthdays_celebrated from public.my_birthday_stats()
    where stat_year = (select this_year from ids)),
  2,
  'birthdays celebrated counts distinct people I wished'
);

-- A second wish to the same person in a later year must not inflate this year.
select tests.as_postgres();
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select me from ids), (select p_one from ids), 'Next year',
        (select this_year from ids) + 1);

-- A second wish to a subject already wished this year, as a 'cake' row since the
-- partial unique index allows only one 'message' per subject per year. This is
-- what makes wishes_sent and birthdays_celebrated diverge, so a regression
-- dropping DISTINCT cannot pass.
insert into public.wishes (author_profile_id, subject_person_id, body, kind, occasion_year)
values ((select me from ids), (select p_one from ids), 'sent a cake', 'cake',
        (select this_year from ids));

select tests.as_user((select me from ids));
-- One assertion covering three things at once: that grouping produces exactly
-- one row per year, that each row's values are right, and that
-- birthdays_celebrated counts DISTINCT subjects (3 wishes sent this year, but
-- only 2 distinct people).
select is(
  (select string_agg(
            stat_year || ':' || wishes_sent || '/' || wishes_received
              || '/' || birthdays_celebrated,
            ' ' order by stat_year)
     from public.my_birthday_stats()),
  (select this_year || ':3/1/2 ' || (this_year + 1) || ':1/0/1' from ids),
  'stats group per year with correct values, counting distinct subjects'
);

select * from finish();
rollback;
