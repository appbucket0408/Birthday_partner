-- The profile's per-year track record. `security invoker` on purpose: RLS still
-- applies, so this function cannot see a wish the caller could not already read
-- directly, and it is testable as a real signed-in user rather than as postgres.
--
-- birthdays_celebrated is DISTINCT subject people, which diverges from
-- wishes_sent once a cake post and a typed message can both land on the same
-- person in the same year.
create or replace function public.my_birthday_stats()
returns table (
  stat_year int,
  wishes_sent int,
  wishes_received int,
  birthdays_celebrated int
)
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (
    select (select auth.uid()) as profile_id,
           (select private.my_person_id()) as person_id
  ),
  mine as (
    -- Filtered to the caller's own rows. Without this, a wish authored by
    -- someone else about a person the caller merely celebrates is visible under
    -- wishes_select_visible, lands in this CTE, and produces a phantom
    -- all-zero row for its year. RLS already guarantees both branches are
    -- readable, so nothing is lost by filtering here.
    select w.occasion_year, w.author_profile_id, w.subject_person_id
    from public.wishes w
    where w.author_profile_id = (select profile_id from me)
       or w.subject_person_id = (select person_id from me)
  )
  select
    m.occasion_year as stat_year,
    count(*) filter (where m.author_profile_id = (select profile_id from me))::int,
    count(*) filter (where m.subject_person_id = (select person_id from me))::int,
    count(distinct m.subject_person_id)
      filter (where m.author_profile_id = (select profile_id from me))::int
  from mine m
  group by m.occasion_year
  order by m.occasion_year desc;
$$;

-- Lives in public and is called by the app, so authenticated keeps execute.
-- It is security invoker, so that grant confers no privilege of its own.
revoke execute on function public.my_birthday_stats() from public, anon;
grant execute on function public.my_birthday_stats() to authenticated;
