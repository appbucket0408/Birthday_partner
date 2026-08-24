-- A wish is a record of something you did. Its visibility to its own author
-- must not depend on whether the celebration edge still exists, or the per-year
-- track record silently loses rows every time someone tidies their list.
--
-- The subject-side branch is unchanged: everyone who can see the person can
-- still see the wishes on their wall.
drop policy wishes_select_visible on public.wishes;

create policy wishes_select_visible
  on public.wishes
  for select
  to authenticated
  using (
    author_profile_id = (select auth.uid())
    or (select private.can_see_person(wishes.subject_person_id))
  );
