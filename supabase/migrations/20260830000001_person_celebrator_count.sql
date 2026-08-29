-- Spec 2026-08-29 §5.1. The person page shows "N people celebrate them" and
-- NEVER a name. The parent spec's original wording ("who else celebrates them")
-- would have exposed a third party's follower list to anyone who imported their
-- phone number; a count carries the same social-proof signal with a fraction of
-- the privacy surface.
--
-- security definer, so it does its own authorisation:
--
--   1. The caller must be able to see the person. people.id is a sequential
--      bigint -- without this check, walking the id space enumerates any user's
--      follower count.
--   2. A block in EITHER direction removes that celebrator from the total.
--      This is deliberately stricter than public.my_celebrates(), which excludes
--      only celebrators the viewer has blocked: that function returns identities
--      for the viewer's own list, while this one returns a number shown on a
--      third party's page. A blocked relationship should contribute to neither
--      side's total.
--
-- 45004 is the next unassigned class-45 code (45001 self-celebration,
-- 45002 no edge, 45003 person claimed). docs/db.md: SQLSTATE is a public API
-- decision because PostgREST maps it straight to an HTTP status.
create or replace function public.person_celebrator_count(p_person_id bigint)
returns int
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_count int;
begin
  -- coalesce(..., false), not a bare `not`: private.can_see_person's first
  -- branch is `p_person_id = private.my_person_id()`, which is NULL rather
  -- than false for a caller who has not claimed a person row. `NULL or false
  -- or false` is NULL, and plpgsql's `if not <NULL>` takes the false branch
  -- (skips the raise), so a bare `if not can_see_person(...)` never fires for
  -- an unclaimed, unconnected caller -- exactly the "outsider" case this
  -- function most needs to reject. Every other caller of can_see_person sits
  -- in an RLS `using` clause, where NULL already reads as "exclude the row",
  -- which is why this gap never surfaced there.
  if not coalesce(private.can_see_person(p_person_id), false) then
    raise exception 'person not visible to caller'
      using errcode = '45004';
  end if;

  select count(*)::int into v_count
  from public.celebrations c
  where c.person_id = p_person_id
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_profile_id = c.celebrator_profile_id
             and b.blocked_profile_id = auth.uid())
         or (b.blocker_profile_id = auth.uid()
             and b.blocked_profile_id = c.celebrator_profile_id)
    );

  return v_count;
end;
$$;

-- R12/R16 (docs/db.md): `revoke ... from public` also strips `authenticated`,
-- which holds EXECUTE only through the PUBLIC grant. The grant back is not
-- redundant -- without it the function is unreachable by the app.
revoke execute on function public.person_celebrator_count(bigint)
  from public, anon;
grant execute on function public.person_celebrator_count(bigint)
  to authenticated;
