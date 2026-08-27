-- B1: `public.celebrations` was a write-your-own-visibility table, and
-- `private.can_see_person` grants sight of a `public.people` row to anyone
-- holding an edge to it. Put together, any signed-in user could read every
-- other user's real name and full date of birth:
--
--   celebrations_insert_own's `with check` constrained only
--   celebrator_profile_id. person_id was unconstrained, so an authenticated
--   session could insert an edge aimed at ANY person id -- and
--   people_select_visible then handed over that row. people.id is a
--   sequential bigint, so the whole user base enumerates in one loop.
--
--   celebrations_update_own had the same hole, and worse: it is an UPDATE
--   policy, and M0's celebrations_guard trigger is BEFORE INSERT only. So
--   even the self-celebration and block checks were absent on that path --
--   one owned edge could be re-aimed at victim after victim, forever, with
--   nothing to trip over.
--
-- Reproduced against the running database as an ordinary `authenticated`
-- user: INSERT aimed at a stranger's person id succeeded, UPDATE redirecting
-- an owned edge to that same stranger succeeded, and the stranger's real
-- display_name and birth_month/day/year came straight back out of
-- public.people.
--
-- This bug is inherited from M0 (20260822000004), not introduced by this
-- branch. It is fixed here because this is the last gate before a client
-- ships on top of the schema.
--
-- Three changes, each of which closes the hole on its own; together they are
-- defence in depth against a future policy edit reopening it:
--
--   1. `authenticated` cannot INSERT into celebrations at all. Edges are
--      minted only by public.rpc_add_celebration -> private.add_celebration,
--      which is service_role-only and reached through the add_celebrations
--      Edge Function. That path resolves person_id from a PHONE NUMBER the
--      caller supplied, never from a person id the caller chose, which is
--      precisely what makes enumeration impossible: you can only aim an edge
--      at someone whose number you already hold.
--
--   2. `authenticated` may UPDATE exactly one column, `nickname` -- the
--      celebrator's own private label for a person they already celebrate.
--      It is never shown to the subject (20260824000002 exists specifically
--      to keep nickname and source out of the incoming list), it does not
--      participate in any visibility predicate, and it is data the celebrator
--      contributed themselves. person_id, celebrator_profile_id and source
--      become unwritable by the client.
--
--   3. private.guard_celebration now runs BEFORE UPDATE as well as BEFORE
--      INSERT, so the self-celebration and block checks cover both paths.

-- ------------------------------------------------------------------ insert

-- With RLS on and no INSERT policy, `authenticated` is denied. The revoke is
-- the second lock: a future `for all` policy would otherwise silently restore
-- the insert path along with whatever it was actually meant to grant.
drop policy celebrations_insert_own on public.celebrations;

revoke insert on public.celebrations from anon, authenticated;

-- ------------------------------------------------------------------ update

-- docs/db.md, "A column-level `revoke` cannot cut back a table-level grant":
-- Supabase's default privileges hand `authenticated` table-level UPDATE on
-- every new public table, and a table-level grant permits writing EVERY
-- column. `revoke update (person_id)` on top of that is a no-op. The only
-- thing that works is to revoke the table privilege and grant the writable
-- columns back by name -- the same shape profiles uses to stop a user
-- setting their own is_staff.
--
-- Adding a client-writable column to celebrations means adding it to this
-- grant list. Adding one to this list is a security decision: anything named
-- here can be rewritten by the row's owner at will.
revoke update on public.celebrations from anon, authenticated;

grant update (nickname) on public.celebrations to authenticated;

-- Recreated rather than left alone, so the row-ownership rule and the
-- column rule sit together in one file. The predicate is unchanged and is no
-- longer the load-bearing control -- the column grant above is. This policy
-- now says only "you may touch rows you own"; WHICH columns is settled
-- before any policy is consulted.
drop policy celebrations_update_own on public.celebrations;

create policy celebrations_update_own
  on public.celebrations
  for update
  to authenticated
  using (celebrator_profile_id = (select auth.uid()))
  with check (celebrator_profile_id = (select auth.uid()));

-- ----------------------------------------------------------------- trigger

-- M0 created celebrations_guard as BEFORE INSERT only, which left every
-- check it performs -- no self-edges, no edge into someone who blocked you --
-- trivially bypassable by inserting a legal edge and then UPDATEing it into
-- an illegal one. The function is unchanged; it reads NEW the same way on
-- both events.
--
-- Under service_role or postgres there is no session, so auth.uid() and
-- therefore private.my_person_id() are null and the self-edge branch cannot
-- fire -- exactly as it already behaves on INSERT. The block branch does not
-- read the session and holds on every path.
--
-- Consequence worth knowing: this fires on ANY update to the row, including
-- a nickname edit. If the person you celebrate has blocked you since you
-- added them, renaming them now raises 'this person has blocked you'. That
-- is the intended reading of a block -- you do not get to keep curating an
-- entry for someone who has cut you off -- but it is a rejection the client
-- must expect on a path that looks purely cosmetic.
create trigger celebrations_guard_update
  before update on public.celebrations
  for each row execute function private.guard_celebration();
