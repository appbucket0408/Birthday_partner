-- Spec 2026-08-29 §4.1. Phase 2a left the timeline's inline birthday edit with
-- no surface at all: public.people has no UPDATE policy, and
-- private.upsert_person only fills NULLs and only when profile_id is null.
--
-- This is security definer, so it bypasses RLS and must do its own
-- authorisation. Two conditions, both load-bearing:
--
--   1. The caller holds a celebration edge to the person. people.id is a
--      sequential bigint; without this check it is an open write target.
--   2. The person has not claimed a profile. Otherwise any celebrator could
--      rewrite a real user's date of birth. A claimed user's own birthday wins.
--
-- SQLSTATEs are chosen, not incidental: docs/db.md records that PostgREST maps
-- them straight to HTTP status codes, so class 45 (unassigned) keeps these
-- reaching the client as 400-class application errors rather than 500s.
create or replace function public.rpc_update_person_birthday(
  p_person_id   bigint,
  p_birth_month smallint,
  p_birth_day   smallint,
  p_birth_year  smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.celebrations c
    where c.person_id = p_person_id
      and c.celebrator_profile_id = auth.uid()
  ) then
    raise exception 'not celebrating this person'
      using errcode = '45002';
  end if;

  if exists (
    select 1
    from public.people p
    where p.id = p_person_id
      and p.profile_id is not null
  ) then
    raise exception 'person has claimed their profile'
      using errcode = '45003';
  end if;

  update public.people
     set birth_month = p_birth_month,
         birth_day   = p_birth_day,
         birth_year  = p_birth_year
   where id = p_person_id;
end;
$$;

-- R12/R16 (docs/db.md): `revoke ... from public` also strips `authenticated`,
-- which holds EXECUTE only through the PUBLIC grant. The grant back is not
-- redundant -- without it the function is unreachable by the app.
revoke execute on function public.rpc_update_person_birthday(
  bigint, smallint, smallint, smallint) from public, anon;
grant execute on function public.rpc_update_person_birthday(
  bigint, smallint, smallint, smallint) to authenticated;
