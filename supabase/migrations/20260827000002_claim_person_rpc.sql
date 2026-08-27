-- Onboarding's last step. private.claim_person links a profile to the person
-- row for their phone hash, which is what makes the user findable by anyone
-- holding their number and what gives them a non-null private.my_person_id().
-- Without it their Celebrates list, wish wall and stats are all empty.
--
-- service_role ONLY. The phone must come from the caller's VERIFIED JWT, not
-- from a request body -- otherwise a signed-in user could claim someone else's
-- number and inherit their inbound celebration edges. The Edge Function reads
-- it from the session; this wrapper trusts its caller because only the Edge
-- Function can reach it.
create or replace function public.rpc_claim_person(
  p_profile_id uuid,
  p_phone text
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select private.claim_person(p_profile_id, p_phone);
$$;

revoke execute on function public.rpc_claim_person(uuid, text)
  from public, anon, authenticated;
grant execute on function public.rpc_claim_person(uuid, text) to service_role;
