-- M3 Phase 1b, Task 6 (design doc 2026-09-04-m3-phase1b-recipient-confirm §6):
-- a recipient can no longer read what the sender paid.
--
-- The exposure: gifts_select_participants (20260822000007_gifts.sql:176-184)
-- granted select to `authenticated` where sender_profile_id = auth.uid() OR
-- recipient_person_id = private.my_person_id() OR private.is_staff(), with
-- no column restriction. A claimed recipient who is also an app user could
-- query public.gifts through PostgREST and read amount_minor -- what the
-- sender paid for their present -- directly. No app screen shows it, but no
-- app screen has to: the row was simply readable.
--
-- Why not a column revoke: Postgres column privileges are per role, not per
-- row, so `revoke select (amount_minor) ... from authenticated` would hide
-- the price from the *sender* too. Once payments ship the sender needs a
-- receipt, so that fix would have to be undone in Phase 2. It also breaks
-- things immediately: myGifts() issues a bare .select()
-- (gift_repository_impl.dart:122), and a role lacking SELECT on one column
-- gets a permission error, not a silent omission, on every column in that
-- select -- and Gift.fromRow reads row['amount_minor'] as int non-nullably
-- (gift.dart:76), the same TypeError shape as Phase 1a's Product.flavour
-- defect.
--
-- The fix: drop the recipient branch. The policy becomes sender or staff
-- only. The sender keeps the whole row, including the price they paid. A
-- recipient reads nothing from public.gifts at all. This is safe today
-- because no recipient-facing in-app surface exists: the gift list is
-- scoped to sender_profile_id, and the confirm endpoint never uses RLS -- it
-- runs as service_role and the recipient has no session.
--
-- This inverts an M0 guarantee, deliberately: 07_gifts.test.sql asserted
-- "the recipient sees the gift addressed to them" (count(*) = 1 as the
-- honoree). That assertion now asserts zero rows instead.
--
-- When a recipient-facing surface ships ("a gift is coming for you"), access
-- returns through a narrow security definer function exposing safe columns
-- only -- never by restoring this branch.
drop policy gifts_select_participants on public.gifts;

create policy gifts_select_participants
  on public.gifts
  for select
  to authenticated
  using (
    sender_profile_id = (select auth.uid())
    or (select private.is_staff())
  );
