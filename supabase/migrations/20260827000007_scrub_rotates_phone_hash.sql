-- B2 and B3 are the same bug wearing two faces: 20260827000005 scrubbed the
-- deleted user's NAME and BIRTHDAY off their surviving people row but
-- deliberately preserved `phone_e164_hash`, and that hash is the row's only
-- lookup key. Anything that can compute the hash can still find, re-attach
-- to, and refill the row.
--
-- B2 -- a recycled phone number hands the new owner the previous owner's
-- entire graph. Number recycling is routine in +91: carriers reissue a
-- disconnected number after 90 days. private.claim_person upserts
-- `on conflict (phone_e164_hash) do update set profile_id = ...`, so the
-- next person to verify that number is attached to the SAME people row.
-- Reproduced: alice's person id 76 came back as bob's person id 76, with
-- one inbound celebration edge and one wish -- bob could read "happy
-- birthday Alice" on a wall that used to be hers.
--
-- B3 -- a re-import resurrects the deleted user's birthday and queues real
-- reminders about them. 20260827000005's own comment claimed that nulling
-- birth_month "stops enqueue_reminders from ever queueing a NEW one for this
-- person". It does not. private.upsert_person refills BLANK birth columns on
-- any row with `profile_id is null`, and the scrubbed row is exactly that:
-- blank and unclaimed. One friend re-importing their address book put
-- month=4 day=15 straight back, and private.enqueue_reminders then queued a
-- notification about a user who had asked to be erased. (That comment is
-- corrected in place in 20260827000005; the behaviour is fixed here.)
--
-- ---------------------------------------------------------------- the fix
--
-- Rotate phone_e164_hash to an unmatchable value inside the scrub, so the
-- row can never again be found by phone -- not by a claim, not by an import,
-- not by resolve_contacts. The row id is untouched, so inbound edges from
-- other profiles still resolve and nobody else's list breaks.
--
-- The replacement is two gen_random_uuid()s with their dashes stripped: 64
-- lowercase hex characters, which is the exact shape people_phone_hash_format
-- ('^[0-9a-f]{64}$') demands and the same width private.phone_hash produces,
-- so nothing downstream can tell the column changed kind. random() is NOT
-- used: it is a deterministic PRNG seeded per-backend and its output is
-- predictable from other draws, which is not an acceptable basis for a
-- privacy control. gen_random_uuid() draws from the platform CSPRNG. Two of
-- them carry ~244 bits of entropy, so colliding with a real HMAC (or with
-- another rotated row, which the unique index would reject) is not a case
-- that needs handling. The value is unrelated to the phone number, so unlike
-- the hash it replaces it cannot be reversed by anyone -- including us.
--
-- This also corrects what the erasure actually claimed. A peppered phone
-- hash is not anonymous data: it is a deterministic function of a phone
-- number, so anyone holding the number can re-derive it and confirm the row
-- is that person's. Keeping it was keeping an identifier for a user who
-- asked to be forgotten. Rotating it strengthens the erasure rather than
-- weakening the "the person row survives" guarantee -- what survives is the
-- row and its edges, which is all that guarantee was ever for.
--
-- ------------------------------------------------------- the trade-off
--
-- Stated here so the next reader finds it written down instead of
-- discovering it:
--
--   * The bystander's celebration edge is now permanently STRANDED. It
--     points at a row named 'Deleted user' with no birthday, and no future
--     event can ever reunite that row with the human it described. The
--     bystander keeps a dead entry in their list until they remove it.
--
--   * A later re-import of that same number mints a SECOND, separate people
--     row beside the stranded one. The two are unlinkable by design. If the
--     original owner ever signs up again on the same number, they get the
--     new row and none of their old inbound edges.
--
-- Both are accepted deliberately. The alternative is the B2 repro: handing a
-- stranger's social graph, wish wall and inbound reminders to whoever next
-- gets the recycled number. A stale row in one person's list is a cosmetic
-- cost; the other is an unrecoverable privacy breach against someone who
-- already left.
create or replace function private.scrub_person_on_profile_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person_id bigint;
begin
  select p.id into v_person_id from public.people p where p.profile_id = old.id;

  -- A profile that never claimed a number (deleted mid-onboarding, or an
  -- email/anonymous session) has no people row to scrub.
  if v_person_id is null then
    return old;
  end if;

  -- Already-queued reminders would otherwise still drain and fire -- under
  -- the placeholder name set below rather than a leaked real one, since
  -- private.next_reminder_batch reads public.people.display_name live
  -- rather than a copy, but a "Deleted user's birthday is today" push is
  -- still a notification about nobody's birthday and must not go out.
  delete from private.notification_outbox where subject_person_id = v_person_id;

  delete from public.addresses where owner_person_id = v_person_id;

  update public.people
  set display_name = 'Deleted user',
      birth_month = null,
      birth_day = null,
      birth_year = null,
      -- The rotation. This is what makes the three nulls above permanent:
      -- private.upsert_person only ever finds a row BY this hash, so once it
      -- no longer matches the number, no import can refill those columns and
      -- private.claim_person can no longer re-attach a new owner to the row.
      phone_e164_hash =
        replace(pg_catalog.gen_random_uuid()::text, '-', '') ||
        replace(pg_catalog.gen_random_uuid()::text, '-', '')
  where id = v_person_id;

  return old;
end;
$$;

-- docs/db.md: `create or replace` does not re-run the original revoke, but a
-- replaced function keeps the privileges of the one it replaced, so this is
-- belt and braces rather than strictly required. It is repeated because the
-- allowlist assertion in 01_private.test.sql is unforgiving and a dropped
-- revoke is a leaked private function.
revoke execute on function private.scrub_person_on_profile_delete()
  from public, anon, authenticated;
