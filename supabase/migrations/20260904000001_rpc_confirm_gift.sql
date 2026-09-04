-- The confirm endpoint's only way into the gift lifecycle (spec §4.2).
--
-- private.confirm_gift is revoked from public/anon/authenticated
-- (20260822000008_gift_lifecycle.sql:247-248), and revoking from PUBLIC strips
-- the default EXECUTE grant, so service_role has no privilege on it either --
-- verified before writing this migration, not assumed. This wrapper is the
-- grant boundary.
--
-- service_role ONLY, exactly like public.rpc_delete_own_draft_gifts
-- (20260901000001). It must never be anon-callable: anon reaching this would
-- let anyone who guessed a 122-bit token write an address directly, bypassing
-- the endpoint's own validation and its neutral-404 folding (spec §4.3).
--
-- Deliberately NOT added to the R3 allowlist in 11_rls_coverage.test.sql: R3
-- asserts the exact set of public functions executable by `authenticated`, so
-- this function's ABSENCE from that unchanged string is the proof the revoke
-- landed (spec §4.2).
create or replace function public.rpc_confirm_gift(
  p_confirm_token uuid,
  p_line1 text,
  p_line2 text,
  p_city text,
  p_pincode text,
  p_label text default 'Home'
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
begin
  return private.confirm_gift(
    p_confirm_token, p_line1, p_line2, p_city, p_pincode, p_label);
end;
$$;

revoke execute on function
  public.rpc_confirm_gift(uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function
  public.rpc_confirm_gift(uuid, text, text, text, text, text)
  to service_role;
