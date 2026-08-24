-- The Celebrates count and list — the "followers" half of the profile — needs
-- the reverse direction of the edge. celebrations_select_own covers only the
-- outgoing direction, so a user could not see who celebrates them at all.
--
-- RLS is row-level, so a policy exposing incoming edges would also hand the
-- subject the celebrator's private `nickname` and the `source` that reveals how
-- they were found. Column grants are role-wide and would blind celebrators to
-- their own nicknames, so the incoming list is a function returning only the
-- celebrator's identity. Display names come from public.people, which
-- private.can_see_person already makes visible in this direction.
create or replace function public.my_celebrates()
returns table (celebrator_profile_id uuid, celebrator_person_id bigint)
language sql
security definer
set search_path = ''
stable
as $$
  select c.celebrator_profile_id, p.id
  from public.celebrations c
  left join public.people p on p.profile_id = c.celebrator_profile_id
  where c.person_id = (select private.my_person_id())
    and not exists (
      select 1 from public.blocks b
      where b.blocker_profile_id = (select auth.uid())
        and b.blocked_profile_id = c.celebrator_profile_id
    );
$$;

revoke execute on function public.my_celebrates() from public, anon;
grant execute on function public.my_celebrates() to authenticated;
