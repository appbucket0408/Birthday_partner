-- The Celebrates count and list — the "followers" half of the profile — needs
-- the reverse direction of the edge. celebrations_select_own covers only the
-- outgoing direction, so a user could not see who celebrates them at all.
--
-- This is additive: it grants sight of edges pointing AT the viewer's person,
-- and nothing about edges between two other people.
create policy celebrations_select_incoming
  on public.celebrations
  for select
  to authenticated
  using (
    person_id = (select private.my_person_id())
    and not exists (
      select 1 from public.blocks b
      where b.blocker_profile_id = (select auth.uid())
        and b.blocked_profile_id = celebrations.celebrator_profile_id
    )
  );
