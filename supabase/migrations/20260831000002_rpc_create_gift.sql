-- Spec 2026-08-30 §5. private.create_gift already enforces a non-null sender,
-- no self-gifting, product availability, and that the slot belongs to the
-- product's service area. It does NOT check that the sender celebrates the
-- recipient, and it takes p_recipient_person_id directly -- where people.id is
-- a sequential bigint. Without this wrapper a caller aims a gift at a stranger
-- by guessing an id, and learns the id exists.
--
-- The sender is derived from auth.uid() rather than taken as an argument, so a
-- caller cannot draft a gift as somebody else.
--
-- 45005 is the next unassigned class-45 code (45001 self-celebration, 45002 no
-- edge, 45003 person claimed, 45004 person not visible). docs/db.md: SQLSTATE
-- is a public API decision because PostgREST maps it to an HTTP status.
--
-- The celebration test is a direct `exists` against public.celebrations, NOT a
-- call to private.can_see_person -- that helper returns NULL rather than false
-- for a caller with no claimed person row, and `if not NULL then` never
-- branches (docs/db.md:175-185). An exists() cannot return NULL, so no
-- coalesce is needed here. Anything indirect would need one.
create or replace function public.rpc_create_gift(
  p_recipient_person_id bigint,
  p_product_id bigint,
  p_slot_id bigint,
  p_occasion_date date,
  p_message text default null
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender uuid := auth.uid();
begin
  if not exists (
    select 1
    from public.celebrations c
    where c.person_id = p_recipient_person_id
      and c.celebrator_profile_id = v_sender
  ) then
    raise exception 'you do not celebrate this person'
      using errcode = '45005';
  end if;

  return private.create_gift(
    v_sender,
    p_recipient_person_id,
    p_product_id,
    p_slot_id,
    p_occasion_date,
    p_message
  );
end;
$$;

-- R12/R16 (docs/db.md): `revoke ... from public` also strips `authenticated`,
-- which holds EXECUTE only through the PUBLIC grant. The grant back is not
-- redundant -- without it the function is unreachable by the app.
revoke execute on function public.rpc_create_gift(
  bigint, bigint, bigint, date, text) from public, anon;
grant execute on function public.rpc_create_gift(
  bigint, bigint, bigint, date, text) to authenticated;
