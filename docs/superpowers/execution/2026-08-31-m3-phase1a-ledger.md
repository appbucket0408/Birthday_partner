# SDD ledger — plan: docs/superpowers/plans/2026-08-30-m3-phase1a-gifting-draft.md

Spec: `docs/superpowers/specs/2026-08-30-m3-phase1a-gifting-draft-design.md`
Branch: `m3-phase1a-gifting-draft`, in the main checkout (no worktree — same
ruling as every prior phase: worktrees cost this project twice before, M0's
removal nearly destroyed a ledger and Phase 2a's isolation stopped a session
merging its own work).
Controller's running notes: `.superpowers/sdd/2026-08-30-m3-phase1a-gifting-draft/progress.md`

This is Task 8, the phase close. Tasks 1–7 are complete and individually
reviewed (see `progress.md` for the full per-task record, including every
implementer report, every review, and every ruling). This document is the
cold-verification record and the carry-forward manifest.

Task 8 did three things, per its brief and its amendment:

1. **The gift list** (spec §7: "the sender's own gifts and their status,
   reached from the profile"). New `GiftListCubit`/`GiftListState`/
   `GiftListScreen`, fed by `GiftRepository.myGifts()` (already scoped to
   the caller's own `sender_profile_id` — Task 4's contract assertion 7).
   Status rendered through `GiftStatus` (eleven DB states plus `unknown`).
   Hold-expiry flagged via `Gift.isHoldExpiredAt` against the cubit's
   injected clock, computed once at `load()` time. `deliveryCity` renders
   `giftCityPending` — every gift in this phase has a null one (spec §6).
   Entry point added to `ProfileScreen` (a plain `ListTile`, not a fourth
   stat tile — there is no count worth a second fetch here).

2. **Closed `/gifts`, a live dead end.** Confirmed directly (not
   hypothetical, per Task 7's own final entry): `draft_screen.dart`'s "See
   my gifts" button called `context.go('/gifts')` with no `/gifts` GoRoute,
   no prefix handling, and no `errorBuilder` configured anywhere — landing a
   real signed-in user on go_router's default unmatched-route page. Added
   `/gifts` as a real, parameterless GoRoute and to the redirect guard's
   literal `signedIn` set (correct here, unlike `/person/:personId` and
   `/gift/new/:personId`, which carry a path parameter and need prefix
   matching instead). `test/router/app_router_test.dart` gained a test
   proving arrival through the **real** `buildRouter` — the exact gap that
   let the dead end survive: Task 7's `draft_screen_test.dart` proved only
   that the button called `context.go`, using an inline test `GoRouter` that
   declared its own `/gifts` route inline, never exercising the production
   router at all.

3. **Fixed the seed (Amendment F4)** so the flow is completable at all. See
   §7 below — this also surfaced a real miss in the amendment's own
   blast-radius claim, found and fixed in this task.

Commit: `7467612` — "feat(gifting): the gift list, close /gifts, fix the
seed for a completable flow".

---

## 1. Final verification numbers

All commands run from a cold `supabase db reset`, on branch
`m3-phase1a-gifting-draft` at HEAD `7467612`, with the local Supabase stack
already up (colima + docker), using FVM Flutter 3.35.2 / Dart 3.9.0 and
Supabase CLI 2.78.1.

| Command | Before this task (base `3c37a4e`) | After this task (`7467612`) |
|---|---|---|
| `supabase db reset && supabase test db` | **30 files / 278 assertions, `Result: PASS`** | **30 files / 278 assertions, `Result: PASS`** (see the mid-task dip below) |
| `supabase functions serve --no-verify-jwt &` then `./supabase/functions/test.sh` | **6 passed, 0 failed** | **6 passed, 0 failed** |
| `fvm flutter analyze` | **`No issues found!`** | **`No issues found!`** |
| `fvm flutter test --exclude-tags=contract` | **187 passing, 0 failed** | **202 passing, 0 failed** |
| `fvm flutter test test/repositories test/e2e --dart-define=SUPABASE_ANON_KEY=...` | **47 passing, 0 failed** | **47 passing, 0 failed** |

The Flutter non-contract delta is exactly this task's own new tests: 6 in
`gift_list_cubit_test.dart`, 8 in `gift_list_screen_test.dart`, 1 in
`app_router_test.dart` (187 + 15 = 202). The contract suite is unchanged at
47 — the amendment's own claim (gift contract tests create their own
service area and assert with `contains` against their own ids, never
counting seed rows) held, verified by actually running it cold rather than
trusted on the amendment's word.

**The pgTAP count is not simply "unchanged" — it dipped and was recovered
inside this task, and that is itself a finding, not noise.** Detail below.

### Detail

- `supabase db reset` applied all 32 migrations cleanly, with the usual
  idempotent-extension notice and the expected
  `tests.create_person(text,text,date)` overload-drop notice (pre-existing,
  from the M0-era migration described in `seed.sql`'s own header comment).
- **First cold run of `supabase test db` after adding the seed's new
  Gurugram slots, before any test-file fix, FAILED**:
  `supabase/tests/database/28_expire_stale_gifts_cron.test.sql` and
  `29_rpc_create_gift.test.sql` both errored with `more than one row
  returned by a subquery used as an expression`, dropping the run to
  `Files=30, Tests=275, Result: FAIL`. Root cause: both files build a
  temporary fixture table with
  `... where s.slot_date = current_date + 7`, relying on that date being
  occupied by exactly one slot **anywhere in the whole table**, not just in
  their own named test area (`Sweep Test Area`, `Gift Test Area`). Adding a
  Gurugram slot for every one of the next 60 days puts a Gurugram slot (and
  Gurugram's own product) on `current_date + 7` too, so the unscoped join
  now matches two rows instead of one, and every downstream
  `(select ... from fixture_table)` — expecting exactly one row — errors.
  **This is a real miss in the amendment's own "blast radius already
  checked" claim.** The amendment correctly named `05_catalog_slots.test.sql`
  (uses its own `'Gurugram Test'` area, unaffected) and the Flutter contract
  tests (create their own area, unaffected) as safe, and said "confirm that
  holds by running both suites from cold, which this task does anyway" —
  that confirmation is exactly what caught this, and it did not fully hold.
  Fixed by scoping both queries to their own named service area
  (`where s.service_area_id = (select id from public.service_areas where
  name = 'Sweep Test Area' | 'Gift Test Area')`) instead of relying on
  `slot_date` being globally unique — a strict correctness improvement to
  two already-closed tasks' pgTAP files (Task 1's and Task 2's), made
  necessary because this task's own seed change is what exposed a
  pre-existing fragility in them. Re-ran cold: `Files=30, Tests=278,
  Result: PASS` — back to the baseline count, confirming the fix is
  targeted and adds no new assertions of its own (a deliberate choice —
  these are scoping fixes to existing fixtures, not new test coverage).
- Deno: `./supabase/functions/test.sh` ran the one existing suite
  (`add_celebrations/index.test.ts`, 6 tests) — this project has no other
  `*.test.ts` file under `supabase/functions/`, confirmed by `find`. 6
  passed, 0 failed, both before and after.
- `fvm flutter analyze` reported `No issues found!` against the full `lib/`
  and `test/` tree, both before and after this task's edits.
- `fvm flutter test --exclude-tags=contract` printed `All tests passed!`
  ending at `+202`, up from Task 7's closing `187`.
- `fvm flutter test test/repositories test/e2e
  --dart-define=SUPABASE_ANON_KEY=...` (anon key pulled fresh from
  `supabase status -o json` after each reset) printed `All tests passed!`
  ending at `+47`, unchanged — this task added no contract test file, per
  its own file list (only `gift_list_cubit_test.dart` was in scope).

### A second, pre-existing seed defect found but NOT fixed (disclosed, not silently worked around)

While confirming the new `delivery_slots` insert's idempotency (re-running
`seed.sql` a second time against an already-seeded database, over a direct
`psql` connection into the running container, without a `db reset` in
between), the new insert proved idempotent as required — still exactly 60
Gurugram slots and 1 Race Test Area slot, no duplicates. **But the
pre-existing `products` insert is NOT idempotent**: it uses
`on conflict do nothing` with no conflict target, and `public.products` has
no unique constraint for it to infer one from, so a second run of
`seed.sql` against an already-seeded database silently inserts a second
`'Classic Chocolate Truffle'` row rather than being skipped. Verified: two
identical rows (ids 1 and 2, both `service_area_id = 1`) after a manual
second run. This is pre-existing — unchanged by this task, present in
`seed.sql:178–181` before this task touched the file at all — and only
`supabase db reset` (which this whole project's tooling always uses, never
a bare re-apply of `seed.sql`) avoids triggering it. Not fixed here: it is
outside this task's file list and its own amendment's specific instruction
("matching the existing insert" for the *slots* insert only), and fixing it
would mean adding a real unique constraint or column list to the `products`
insert, a schema-adjacent decision this task was not asked to make. Flagged
here rather than left for the next person to rediscover by watching
duplicate products appear after an unusual local workflow.

---

## 2. Config guard

```
$ grep -n enable_confirmations supabase/config.toml
209:enable_confirmations = false
252:enable_confirmations = true

$ awk '/^\[auth\./{sec=$0} /enable_confirmations/{print NR": "sec" -> "$0}' supabase/config.toml
209: [auth.email] -> enable_confirmations = false
252: [auth.sms] -> enable_confirmations = true
```

Line 209 (`false`) is under `[auth.email]` — unrelated, correct as `false`.
Line 252 (`true`) is under `[auth.sms]` — **this is the guard**, and it
still reads `true`. `git diff --stat supabase/config.toml` was checked
against the base commit and the file was not touched by this task at all
(0 lines changed).

This line is the fix for a reproduced total-account-takeover bug from Phase
2a (recorded in `docs/superpowers/execution/2026-08-27-m1-phase2a-ledger.md`):
with `enable_confirmations = false`, GoTrue runs with
`SMS_AUTOCONFIRM=true`, and `PUT /auth/v1/user {"phone": ...}` silently
rewrites and confirms a session's phone number with no OTP at all, letting
an attacker point their session at an unclaimed victim's number and claim
their person row outright. It is guarded by no test and no CI —
`supabase init` or a CLI upgrade rewrites this file — and this is the phase
this brief specifically named as "one that can disturb it" (Task 1 edited
it once, legitimately, to schedule the cron job's cadence). It must be
re-checked by hand at every future phase close until it is guarded some
other way.

---

## 3. Per-task commit range

Derived from `git log --oneline main..HEAD` (`main` at `f294efb`, HEAD at
`7467612`).

| Task | Range | Notes |
|---|---|---|
| (design + plan, pre-task) | `f294efb..e74d286` | `3cce3fd` (design), `ecabbb6` (plan), `e74d286` (plan amendment: F1 — push, not route, for the slot picker/draft) |
| 1 — schedule `expire_stale_gifts` | `e74d286..ad62777` | `ad62777` |
| 2 — `rpc_create_gift` + celebration guard | `ad62777..1fb8e73` | `1fb8e73` |
| 3 — catalog/gift row mappings | `1fb8e73..44887e5` | `b0af889` (implementer), `61fcd9f` (plan doc: name nullable columns), `44887e5` (fix round 1: nullable `flavour`/`size`) |
| 4 — `GiftRepository` | `44887e5..62e9ce6` | `07564de` (implementer), `62e9ce6` (fix round 1: assertions 5 and 7 made genuinely discriminating) |
| 5 — the catalog screen | `62e9ce6..209f75b` | `3c6baff` (implementer), `209f75b` (fix round 1: screen coverage, `person()` failure path, dead string) |
| 6 — the slot picker | `209f75b..f0af721` | `f0af721` |
| 7 — the draft screen | `f0af721..3c37a4e` | `16a3e63` (implementer), `3c37a4e` (fix round 1: thread recipient name, lock the notice) |
| 8 — this phase close | `3c37a4e..7467612` | `7467612` (gift list, `/gifts` route, seed fix, pgTAP fixture scoping fix) |

`main..HEAD` = `f294efb..7467612`, 16 commits ahead of `main`, 0 behind, at
time of writing (branch runs directly off `main`, not a worktree).

---

## 4. Not verified

**No end-to-end run of the app on a real device has ever been performed for
this project, in any phase, and this phase does not close that gap** —
named explicitly as risk 1 in the spec (§10) and repeated here rather than
left to be found again.

Concretely:

- **Every Flutter test in this repository — all 202 non-contract and all
  47 contract tests, this phase's new ones included — runs on the Dart
  VM.** None of them boot `main.dart`, mount `App`, or drive `GoRouter`
  inside a real iOS/Android runtime. The contract tests do talk to a real
  local Supabase stack over real HTTP, which is a meaningfully stronger
  guarantee than a mock — but the client side of every one of those calls
  still runs on the Dart VM, not inside a device's networking, permissions,
  or lifecycle stack.
- **This phase adds four screens — catalog, slot picker, draft, and now the
  gift list — and none of them has ever rendered on a device or a
  simulator.** Every assertion in this ledger's Flutter counts is a
  widget-test assertion against the Dart VM's own rendering pipeline.
- **This is not a hypothetical risk category for this specific project.**
  Phase 2b's own ledger records that an iOS App Transport Security defect
  (no `NSAppTransportSecurity` key in `Info.plist`, silently blocking every
  cleartext request to the local Supabase stack) survived 96 passing tests
  and was found only when a human ran a simulator. No amount of Dart-VM
  test count, this phase's 249 Flutter tests included, is evidence against
  a defect of that same shape existing anywhere in this phase's four new
  screens.
- No simulator was launched and no browser-automation tool was used in this
  session, per this task's explicit constraints.

### Seed completability — reasoned from the fixtures, not run

**The full flow — person page → catalog → slot picker → draft → gift
list — is now completable against the seed**, for a test contact whose
birthday's next occurrence falls within the seeded window, reasoning
through each hop:

1. **Person page → catalog.** `CatalogCubit.load(personId)` requires a
   non-null `Person.birthday`; any claimed test contact with a birthday
   set clears this.
2. **Catalog.** `serviceAreas()` returns both `Gurugram` and `Race Test
   Area` (both `is_active = true` by column default). `CatalogLoaded`
   picks `areas.first.id` as the initially selected area — the seed's own
   insert order makes `Gurugram` (id 1) the likely first row, but even if
   `Race Test Area` (id 2) resolved first, the screen's own area dropdown
   lets the user switch to Gurugram, which is the only area with a product
   (`Classic Chocolate Truffle`, seed.sql:178–181). Either way the product
   is reachable.
3. **Slot picker.** `SlotPickerScreen` filters `slotsIn(serviceAreaId,
   onOrAfter: occasionDate)` to slots falling exactly on
   `birthday.nextOccurrence(now())` (Task 6's A3). This task's seed change
   gives Gurugram a slot (capacity 5, `10:00–13:00`) on every one of the
   next 60 days from the reset date. **So any test contact whose next
   birthday occurrence falls within that 60-day window reaches a bookable
   slot; one whose birthday falls outside it legitimately sees
   `giftNoSlots`, which is correct per spec §11 (a cake dated anything
   other than the birthday is a different product), not a bug.** A device
   tester must deliberately set a test contact's birthday inside that
   window (today, 2026-08-31, that window is 2026-09-01 through
   2026-10-30) for the flow to complete — the seed cannot make an
   arbitrary birthday bookable, only a birthday chosen to fall in range.
4. **Draft.** Tapping a bookable slot pushes `DraftScreen` with the
   product, slot, occasion date, and recipient name already in hand
   (nothing further to fetch). `DraftCubit.create()` calls
   `rpc_create_gift`, which requires the sender to celebrate the recipient
   (a normal precondition of having a person page for them at all), the
   product active (true by default), and slot capacity available (5,
   fresh). All satisfied.
5. **Gift list.** On success, the hold-notice dialog's "See my gifts"
   button now resolves through this task's `/gifts` route (previously a
   dead end) to `GiftListScreen`, whose `GiftListCubit.load()` calls
   `myGifts()` and renders the just-created gift: product (by id — see the
   Concerns section below), occasion date, status `Draft`, and
   `giftCityPending` (every gift in this phase has a null `deliveryCity`).

No step in this chain depends on anything not already seeded or already
true of a normally-onboarded test contact. This is a paper reasoning from
the fixtures and the code, explicitly **not** a device or simulator run,
per this task's constraints.

---

## 5. Carried forward

Every line from
`.superpowers/sdd/2026-08-30-m3-phase1a-gifting-draft/progress.md` marked
`minor (deferred)`, and every line beginning `Ruling:`, reproduced here
with its reasoning intact rather than just its headline. Grouped by where
it was recorded. Two of these — Amendment F4 (the seed) and Task 7's final
entry (the `/gifts` dead end) — were this task's own job and are now
addressed; they are reproduced below verbatim, as recorded, with a note
added rather than silently dropped.

### Pre-flight / cross-cutting

- **Ruling (no worktree):** no worktree, as in the three prior phases.
  Worktrees cost this project twice (M0's removal nearly destroyed a
  ledger; 2a's isolation stopped the session merging its own work). Cost
  if wrong: no isolation from the shared checkout.
- **Ruling (F1 — routes vs. push for the accumulating selection):** the
  plan made `/gift/slots` and `/gift/draft` routes, but both are
  parameterless and neither can carry the selection accumulating across
  the three screens (person id and birthday from the person page, the
  product from the catalog, the slot from the picker). Decided: only
  `/gift/new/:personId` is a route; the slot picker and draft screen are
  reached by `Navigator.push`, carrying the accumulated selection forward
  — the same precedent as M1 Phase 2b's `OtpScreen`. `/gifts` (Task 8)
  stays a real route: parameterless and genuinely addressable, since it
  only loads the signed-in user's own gifts. Cost if wrong: if a later
  milestone needs a deep-linkable draft (a push notification resuming an
  abandoned hold), the route and its parameters must be added then —
  cheap and additive, and the hold expires in fifteen minutes anyway.

### Task 1 (schedule `expire_stale_gifts`)

- Minor (deferred): the migration comment says a released slot is bookable
  "within a few minutes"; worst case is ~10 minutes after expiry with a
  `*/10` cron cadence. Cosmetic wording only.

### Task 2 (`rpc_create_gift` + celebration guard)

- **Ruling (defer the assertion 4/5 fixture coupling):** reverting the
  celebration guard made assertion 4 fail via the capacity constraint
  (23514) rather than cleanly via the guard's own absence, because
  assertion 1 earlier in the same transaction had already consumed the
  fixture's capacity-1 slot. Resolved on review: assertion 4 is
  load-bearing **provably from control flow**, not from the revert trial —
  the guard's `if not exists (...) then raise` runs before
  `private.create_gift` is called, and `reserve_slot` is only reached
  inside that call, so in the green run 45005 is produced by the guard,
  never by a capacity coincidence. Ruling: defer the fixture fix, no fix
  round — the coupling originates in the controller's own brief, not an
  implementer choice, and the guard's correctness does not depend on the
  fixture. Cost if wrong: a future guard regression surfaces as a masked
  23514 rather than a clean "no exception thrown" — a worse diagnostic,
  but still a failing test.
- Minor (deferred), **CARRY TO THE FINAL REVIEW**: give assertion 4 its own
  slot with spare capacity, or run it before assertion 1 consumes the
  fixture's only unit, so a genuine guard regression surfaces as "no
  exception thrown" rather than a masked 23514. **Status at Task 8: still
  open** — this task did not touch `29_rpc_create_gift.test.sql`'s
  assertion ordering or fixture capacity, only the unrelated area-scoping
  fix in §1 above (a different query in the same file).

### Task 3 (catalog/gift row mappings)

- **Ruling (fix round + require `fromRow` coverage):** the controller's own
  brief described `ServiceArea`/`Product` in prose as "plain field
  mappings" rather than giving source, leaving nullability to inference —
  `Product.flavour`/`.size` are nullable columns but were typed
  non-nullable `String`, throwing a `TypeError` on a null value with
  nothing to catch it distinctly (a generic, code-less `ServerFailure`
  that aborts an entire area's catalog). Fixed; `test/models/product_test.dart`
  added to exercise `fromRow` directly, watched to fail against the
  original cast.
- Minor (deferred): no `fromRow` coverage for `Gift` or `DeliverySlot`;
  arrived with Task 4's contract tests against real rows.

### Task 4 (`GiftRepository`)

- **Ruling (promote the assertion 5 Minor into the fix round):**
  assertion 5's original fixture targeted a nonexistent sentinel id
  (`999999999`), so with the guard removed the FK on
  `recipient_person_id` tripped and produced 23503 — masking whether the
  celebration guard itself was ever exercised. The dangerous case is a
  **real** person the caller does not celebrate: no FK to trip, so a
  guard-less RPC would succeed silently and create a gift aimed at a
  stranger — precisely the id-space-walking exploit assertion 5 exists to
  close. Fixed with a real, uncelebrated person fixture; re-verified the
  guard-removed exploit now completes with **no exception at all**, not a
  different one.
- Minor (deferred): assertion 7's `deliveryCity == null` half cannot
  distinguish "sender blocked from the address" from "nothing has
  confirmed yet" — `confirm_gift` is the only writer and is unreachable
  this phase. Phase 1b closes it.
- Minor (deferred): `productsIn()` adds `.eq(isActive, true)`, duplicating
  `products_select_active`'s RLS filter. Harmless; asymmetric with
  `serviceAreas()`, where the client-side filter IS load-bearing since
  `service_areas_select_all` is `using(true)`.
- **CARRY TO THE FINAL REVIEW** — the `ON DELETE RESTRICT` product
  decision: `gifts.sender_profile_id` is `ON DELETE RESTRICT`, so
  `AuthRepository.deleteAccount()` now fails for any user who has sent a
  gift. Predicted in writing at `delete_account/index.ts:24-35` as inert
  "only because M1 ships no gifts" — M3 shipped gifts, so it is inert no
  longer. The contract test's teardown works around it by deleting gifts
  before calling `deleteAccount()`, which is correct for a test but is not
  the product fix. **The human owns the choice: reassign, anonymise, or
  refuse deletion.** Worse sibling for M4: `address_access_log.staff_profile_id`,
  immutable, so reassignment is not available at all. **Status at Task 8:
  still open** — out of this task's scope (no `GiftRepository` signature
  or auth-flow change was authorized).

### Ruling F2 (before Task 5 — the catalog route cannot be entered cold)

`/gift/new/:personId` IS a route (unlike the picker and draft), so it is
addressable cold with a person id and nothing else — but Task 7's original
design needed a `Birthday` handed down from the person page, which is
absent on a cold entry. Decided: `CatalogCubit` also takes
`PersonRepository` and loads the person alongside the areas, refusing a
null birthday up front with a new string (`giftNeedsBirthday`) reusing the
existing `CatalogError` state rather than growing a fourth branch. Deferred
as a Minor, deliberately: cold entry also bypasses the person page's
`viewerCelebrates` gate — not closed, because the server guard (Task 4's
45005) is real and provably load-bearing, and the refusal is honest, just
late. **Status at Task 8: still open**, unchanged.

### Task 5 (the catalog screen)

- **My defect (dead string):** Step 1 of the brief specified
  `giftPriceTemplate = '₹%s'` while Amendment B put the `₹` inside
  `Product.priceLabel` directly — the implementer correctly built
  `priceLabel`, kept the now-dead string because the brief asked for it,
  and flagged the contradiction. Ruling: delete it (would double the `₹`
  symbol if a later task reached for it).
- **Minor promoted (false code comment):** `catalog_screen.dart`'s
  reasoning for avoiding `DropdownButtonFormField` asserted `initialValue`
  "does not re-sync on a later rebuild" — verified false against the
  pinned SDK (`didUpdateWidget` does call `setValue` when it changes).
  The chosen `DropdownButton` is fine regardless (its own `didUpdateWidget`
  reads `widget.value` fresh), so the outcome was never at risk, but the
  comment was corrected — a confidently wrong comment is worse than none.
- **Lesson carried:** a `find.text` assertion on a `DropdownButton` is
  vacuous — `DropdownButton.build()` wraps every item in an `IndexedStack`,
  and non-selected children are not `Offstage`-wrapped, so
  `skipOffstage: true` does not exclude them. Assert the widget's own
  `.value` instead. (Restated as a house rule in every subsequent task's
  brief, including this one's.)

### Ruling F3 (before Task 6 — nothing ties the delivery slot's date to the occasion date)

`private.create_gift` checks sender/self-gift/product-active/slot-area/
capacity, but nothing constrains the chosen slot to fall on the occasion
date — verified by reading the migration directly. All four of Task 4's
`createDraft` contract tests already exercised this gap (an 8–9 day
mismatch, green). Decided: close it **client-side in Task 6**, where the
picker requests and displays only slots on the exact occasion date, making
a mismatched pair unreachable through the UI. **Deferred, not folded in
here: the server-side `slot_date = p_occasion_date` check** — adding it now
would break Task 4's four already-reviewed contract test fixtures, which
deliberately mis-date. **CARRY TO THE FINAL REVIEW.** Cost if wrong: until
that check exists, the invariant is UI-only; anything that creates a gift
without going through the picker (a future deep link, an ops tool, a
script) can still produce a self-contradicting row. **Status at Task 8:
still open**, unchanged — this task's file list did not authorize a new
migration.

### Ruling F4 (found while amending Task 6 — the local seed cannot produce a bookable gift at all) — ADDRESSED BY THIS TASK

The only seeded product was in Gurugram; the only seeded slot in Race Test
Area — different areas, so the gifting flow could not be completed against
the local seed no matter what Tasks 6 and 7 built, and Task 6's exact-date
filter (F3's fix) compounded it further. Decided at the time: fix the seed
in Task 8, not Task 6, because Task 8 is the cold-verification task and
mixing a fixture change into a screen task would muddy that task's own
break-and-fail evidence. **Addressed in this task** — see §7 above and the
commit message. The blast-radius claim made at the time this ruling was
written ("pgTAP uses its own `Gurugram Test` area... so adding Gurugram
slots breaks nothing") was **directionally correct but incomplete**: it
missed `28_expire_stale_gifts_cron.test.sql` and `29_rpc_create_gift.test.sql`,
both of which broke and were fixed in this task (see §1's Detail).

### Task 6 (the slot picker)

- **Ruling (accepted, not fixed — StatefulWidget instead of a Cubit):**
  the implementer disclosed the inconsistency itself, citing
  `CelebrationListScreen`'s precedent (not identical, but DIP still holds
  per spec §8's "read with `context.read`" house pattern). Accepted —
  rewriting 425 working, tested lines for consistency alone was judged not
  a good trade. Noted, not fixed: the flow now reads catalog=Cubit,
  picker=StatefulWidget, draft=Cubit and gift list=Cubit (Task 8), so the
  picker remains the one odd one out. **Status at Task 8: still open**,
  unchanged — out of this task's file list.
- Minor (deferred): a double-tap on a slot pushes the draft screen twice —
  the picker has no `ReentrancyGuard`. Harmless: `DraftCubit.create` IS
  guarded, so no capacity is burned; the user just sees two stacked
  screens.
- Minor (deferred), **CARRY TO THE FINAL REVIEW**: the birthday invariant
  at `catalog_screen.dart:198-203` is a Dart `assert`, compiled out in
  release. Not a live risk today (`catalog_cubit.dart`'s null refusal is a
  real runtime check, not itself an assert) but defence-in-depth on an
  already-enforced invariant, not the invariant itself. **Status at Task
  8: still open**, unchanged.

### Ruling F5 (during Task 7 — the occasion date stops at the picker, and would be derived twice)

The same defect as F2/A2, recurring one hop later: the original
placeholder `DraftCubit.create` design took a `Birthday` and would derive
the occasion date again, independently, which could disagree with the
picker's own `birthday.nextOccurrence(now())` computation (a session
crossing midnight between screens is enough) — reintroducing F3's mismatch
from a client-side divergence, in the very task that exists to close it.
Decided: the occasion date is derived once, upstream, and carried —
`DraftCubit.create` takes a required `occasionDate` it cannot compute or
override. No fix round needed for Task 6; Task 7's brief was amended
directly. Addressed in Task 7 (`16a3e63`), verified by the controller
before dispatching the review.

### Task 7 (the draft screen)

- **Lesson carried (test-infrastructure defect, found by the
  implementer):** `RepositoryProvider.value` wrapped around
  `MaterialApp`'s `home` does not reach a route pushed later — a pushed
  route is a sibling `OverlayEntry`, not a descendant of `home`. Masked in
  Tasks 5 and 6 because `SlotPickerScreen`'s `catch (_)` swallows the
  failed provider read into a generic error state; `DraftScreen`'s
  `BlocProvider(create:)` does not, so Task 7's first end-to-end test hit
  it immediately. Verified this did NOT invalidate Task 6's own evidence
  (its `pumpPicker` scoped the provider around `SlotPickerScreen` directly
  as `home`'s child, a true descendant). Fixed by scoping the provider
  around the whole `MaterialApp` in any test that pushes — restated as a
  house rule in every subsequent brief, including this one's, and followed
  in this task's own `gift_list_screen_test.dart`.
- Minor (deferred), **CARRY TO THE FINAL REVIEW**: the flip side of the
  house error shape — `SlotPickerScreen`'s `catch (_)` turns a
  `ProviderNotFoundException` into "something went wrong," so a genuine DI
  misconfiguration presents as a routine failure rather than failing
  loudly. Cannot happen in production today (the real provider tree is
  always present). **Status at Task 8: still open**, unchanged.
- **Ruling F6 (two of the controller's own defects — recipient shown by
  id, and a missing screen test):** the original brief never said where
  the recipient's display name should come from (no `PersonRepository` was
  threaded into the draft screen), so the sender saw "Recipient #42" on
  the one screen where they are about to spend money on a specific person;
  and the file list omitted `draft_screen_test.dart`, leaving the honest
  dead-end notice (the single thing spec §7 is most emphatic about)
  verified only by reading the source. Both addressed in Task 7's fix
  round 1 (`3c37a4e`): `displayName` threaded through the existing push
  chain (no `PersonRepository` added), and `draft_screen_test.dart` created
  with 8 tests including a rendered-text guard against "coming soon" /
  "payment" / "checkout will" language.
- **Task 7's final entry — the `/gifts` dead end, CONFIRMED real — ADDRESSED
  BY THIS TASK.** "`/gifts` has no GoRoute, no prefix handling, and
  `app.dart` configures NO `errorBuilder`, so a user who completes a draft
  today and taps 'See my gifts' reaches go_router's default unmatched-route
  page. Not a crash, but a broken end to the one flow this phase built."
  Recorded as pre-existing from `16a3e63`, not introduced by the fix
  round, with the explicit note "TASK 8 MUST CLOSE IT." Addressed — see §1
  of this ledger's summary above and `test/router/app_router_test.dart`'s
  new `/gifts` test.

### Task 8 (this phase close) — new findings

- **The pgTAP blast-radius miss** (F4's own claim, incomplete) — see §1's
  Detail above and Ruling F4's update in this section. Fixed within this
  task.
- **A second, pre-existing, NOT-fixed seed defect**: `seed.sql`'s
  `products` insert is not idempotent (`on conflict do nothing` with no
  target, and no unique constraint on `products` to infer one from) — a
  second run of `seed.sql` against an already-seeded database silently
  duplicates the Gurugram product row. Pre-existing, unchanged by this
  task, masked in every normal workflow because this project always uses
  `supabase db reset` rather than a bare re-apply of `seed.sql`. See §1's
  Detail for the reproduction. **Not fixed** — outside this task's
  authorized file list and its amendment's specific instruction (which
  named only the *slots* insert). Flagged for whoever next touches
  `seed.sql`'s catalog fixtures.

---

## 6. Live carry-forwards from the spec

Named explicitly in the phase's spec (§11) and in Task 8's own brief as
things this ledger must record rather than let fade with the branch.

### §11.2 — the recipient can read `amount_minor` on a gift aimed at them

`gifts_select_participants` has no column restriction, so a recipient who
can see a gift row at all (the RLS policy's "I am the recipient" branch)
can read `amount_minor` — the exact price the sender paid — even though the
whole point of §6's design is that the sender's side is the one restricted
(no address access). **This becomes live in Phase 1b**, the first phase
where a recipient-facing surface (the confirm page) actually exists to
read it. Nothing in Phase 1a exposes this to any client, since no
recipient-facing screen ships yet, but the RLS policy itself already
permits it today, at the database layer, for anyone who authenticates
directly against PostgREST.

### The suppression oracle: reduced, not closed

Unchanged since M1 Phase 3's ledger (§6 there), re-verified here rather
than assumed: `grep -rn suppress_person supabase/functions/` still returns
only comments (`delete_account`'s comment names suppression as a planned
future request type), never a caller. `private.suppress_person` has no
Edge Function caller, so no suppression can be created through the API and
there is nothing to enumerate. **It reopens in full the moment any
client-reachable path to create a suppression ships** — at that point,
neither `add_celebrations`' per-item `"skipped"` status nor its aggregate
`skipped` count may keep behaving as a proxy for "this specific number is
suppressed," per M1 Phase 3's ledger's own analysis (which itself corrected
two successively-too-optimistic earlier readings of the same gap — see
that ledger's Addendum). Dormant only, not closed, and unrelated to any
work this phase did — carried forward because Task 8's own brief named it
explicitly as something this ledger must record.

---

## Suite size at phase close

30 pgTAP files / 278 assertions · 6 Deno tests · 202 non-contract + 47
contract Flutter tests (249 total) · `flutter analyze` clean · all cold
from `supabase db reset`, verified in this session at HEAD `7467612`.

Per this task's own Step 7 and the top-level constraints: **this branch is
not merged.** The merge decision, and the whole-branch review that must
come before it, both belong to the human.
