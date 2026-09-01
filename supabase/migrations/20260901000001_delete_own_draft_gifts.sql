-- Pre-merge review fix (docs/superpowers/execution/2026-08-31-m3-phase1a-
-- ledger.md §8, BLOCKER). gifts.sender_profile_id is ON DELETE RESTRICT
-- (20260822000007_gifts.sql:20), so once M3 shipped, admin.auth.admin.
-- deleteUser started failing PERMANENTLY for any user who has ever drafted a
-- gift: private.expire_stale_gifts moves a lapsed hold to 'expired' and
-- KEEPS the row (20260822000008_gift_lifecycle.sql:222-223), so the hold
-- lapsing never clears the FK. Reproduced on the live DB:
--
--   ERROR: update or delete on table "profiles" violates foreign key
--          constraint "gifts_sender_profile_id_fkey" on table "gifts"
--
-- Ruling: delete_account/index.ts deletes the caller's own 'draft' and
-- 'expired' gifts before calling admin.auth.admin.deleteUser. Both states
-- carry no payment, no delivery and no counterparty obligation, so removing
-- them harms nobody -- whereas refusing account erasure over an abandoned,
-- free draft is the worse outcome. A gift in ANY OTHER status (paid and
-- beyond) must keep blocking deletion, loudly: that policy question --
-- reassign, anonymise, or refuse -- is deliberately deferred to M3 Phase 2,
-- which must revisit this function before payments ship.
--
-- Deleting the gift ROW alone is not sufficient for a still-'draft' gift:
-- its slot hold has not lapsed, so private.reserve_slot's `reserved` counter
-- is still incremented, and once the gift row is gone nothing will ever call
-- private.release_slot for it -- a permanent capacity leak, the exact same
-- "silently wrong" shape this whole review exists to catch. An 'expired'
-- gift needs no release: private.expire_stale_gifts already released its
-- slot BEFORE transitioning it to 'expired' (gift_lifecycle.sql:222-223),
-- so by the time a gift reaches that status its slot is already free.
--
-- service_role ONLY, called by delete_account after it has already verified
-- the caller's session from their JWT -- this function trusts p_profile_id
-- for the same reason public.rpc_claim_person does: only that Edge Function
-- can reach it.
create or replace function public.rpc_delete_own_draft_gifts(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select id, slot_id, status
    from public.gifts
    where sender_profile_id = p_profile_id
      and status in ('draft', 'expired')
    for update
  loop
    if r.status = 'draft' and r.slot_id is not null then
      perform private.release_slot(r.slot_id);
    end if;
    delete from public.gifts where id = r.id;
  end loop;
end;
$$;

revoke execute on function public.rpc_delete_own_draft_gifts(uuid)
  from public, anon, authenticated;
grant execute on function public.rpc_delete_own_draft_gifts(uuid) to service_role;
