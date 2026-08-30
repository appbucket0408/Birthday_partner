# M3 Phase 1a — Gifting: Catalog, Slot Hold, Draft

Date: 2026-08-30
Status: Approved for implementation planning
Parent spec: `docs/superpowers/specs/2026-08-22-birthday-gifting-app-design.md` §9, M3
Predecessor: M1 Phase 3, merged to `main` at `f294efb`

## 1. What Phase 1a is

M1 made the app useful: reminders, a timeline, a wish wall, a profile. M3 makes it
a product — you can send someone a cake without ever seeing their address.

Phase 1a builds the sender's half up to the point money would change hands, and
stops there deliberately. It ends with a real delivery slot held for fifteen real
minutes against a database-enforced capacity.

## 2. Scope

**In:** scheduling `private.expire_stale_gifts`, a public wrapper for
`private.create_gift` with the one guard it lacks, catalog browsing, slot selection,
draft creation, and the sender's own gift list.

**Out, and each for a stated reason:**

- **Anything that marks a gift paid.** `private.mark_gift_paid` is the `draft` →
  `awaiting_confirm` transition and it is server-side, so any stub is a path to free
  goods. **No client-reachable payment surface ships in this phase.** Tests bridge
  the gap with `service_role`, exactly as the pgTAP suite already does.
- **The confirm page and the Flutter web target** — Phase 1b. The web build is new
  to this project and carries the unknowns; isolating it means a web-build problem
  cannot stall the app half.
- **Payments proper** — Phase 2, when a provider account exists.

## 3. What M0 already built, and what it did not

M0 shipped more of this than the build-order table implies. Read
`supabase/migrations/20260822000007_gifts.sql` and `..._gift_lifecycle.sql` before
planning anything here.

**Already built and tested:**

- `public.gifts` with an eleven-state `gift_status` enum, and `confirm_token uuid`
  — the row id is never exposed in a URL, and the token is single-use via
  `confirm_token_used_at`.
- `public.gift_events`, an append-only transition log. `create_gift` writes a
  `null → draft` row. **Every new transition must keep writing one**; the ops
  console in M4 reads this table.
- `private.create_gift`, which already enforces: a non-null sender; **no
  self-gifting**; the product must be available; and **the slot must belong to the
  product's service area**. An earlier draft of this spec listed that last one as
  new work — it is not.
- `private.reserve_slot`, called by `create_gift`, against
  `delivery_slots_not_oversold check (reserved <= capacity)` — the daily cap
  enforced by the database rather than by remembering to check.
- `tests.race_last_slot`, a helper that opens two real connections and races them
  for the last unit of capacity.
- Catalog reads: `service_areas_select_all`, `products_select_active` and
  `delivery_slots_select_all` are already granted to `authenticated`. **Catalog
  browsing needs no new backend at all.**

**Not built:**

- **`private.expire_stale_gifts()` is scheduled nowhere.** See §4.
- **No celebration check in `create_gift`.** See §5.
- Every lifecycle function is revoked from `authenticated`, so none is reachable.

## 4. The gap this phase closes first

`private.expire_stale_gifts()` exists and nothing calls it. Slot capacity is a hard
constraint, so an abandoned draft holds a delivery slot **permanently**, and a real
customer eventually cannot book a van that is in fact free.

This is the same shape as M1's "nothing triggers the drain yet" — with one
difference that makes it fixable now rather than deferred: the drain needed FCM
credentials, and this needs nothing. It is pure SQL.

Schedule it with `pg_cron`, alongside the existing reminder fan-out in
`20260824000008_cron.sql`. The pgTAP test must prove a slot is actually **released**,
not merely that the function ran: hold a slot, expire it, assert `reserved` went back
down and the gift reached `expired`.

## 5. The one guard `create_gift` lacks

`private.create_gift` never checks that the sender celebrates the recipient. It
takes `p_recipient_person_id` directly, and `people.id` is a sequential bigint — so
a caller could aim a gift at a stranger by guessing an id, and in doing so learn
that the id exists.

`public.rpc_create_gift(p_recipient_person_id, p_product_id, p_slot_id,
p_occasion_date, p_message)` — `security definer`, deriving the sender from
`auth.uid()` rather than taking it as an argument, and refusing when the caller holds
no `celebrations` edge to the recipient.

**Use `coalesce(...)` if the check ever routes through a nullable helper.**
`private.can_see_person` returns **NULL, not false**, for a caller with no claimed
person row, and plpgsql's `if not NULL then` never branches — a bare check silently
admits exactly the caller it should refuse. That defect was found and fixed in M1
Phase 3 and is recorded in `docs/db.md`. An `exists (...)` against `celebrations`
does not have this problem, but anything indirect does.

Written test-first in pgTAP, with the guard reverted and the specific assertion
watched to fail.

**SQLSTATE is a public API decision** — PostgREST maps it to an HTTP status. Class 45
is unassigned and in use: `45001` self-celebration, `45002` no edge, `45003` person
claimed, `45004` person not visible. This adds `45005` for "you do not celebrate this
person".

**`23514` must reach the client distinctly.** That is the oversold constraint, and
two users racing for the last slot is a legitimate outcome, not a fault. The UI says
*"that slot just filled"*, never *"something went wrong"*.

## 6. What the sender may never see

The whole product rests on one rule: **the sender never sees the recipient's
address, and learns the city only after confirmation.**

`gifts.delivery_address_id` points at an `addresses` row the sender cannot read.
`gifts.delivery_city` is denormalised onto the gift and written **only at
confirmation**, which is Phase 1b.

So in this phase every gift the sender can see has `delivery_city` null, and the
gift list must render that as a plain "address not confirmed yet" rather than an
empty space that looks like a bug.

**The plan proves this rather than asserting it:** a pgTAP assertion that a sender
selecting their own gift row cannot reach the linked address, and that
`delivery_city` is null before confirmation.

## 7. Screens

**Catalog** — service area, then the active products in it. Both already readable;
no new backend. Reached from a person page's "Send a cake" action, since you gift
someone you celebrate.

**Slot picker** — slots for that area, each showing remaining capacity
(`capacity - reserved`), disabled at zero. Capacity is public information here: it
is a delivery van's schedule, not anyone's personal data.

**Draft** — recipient, product, slot, an optional message capped at 280 characters
by `gifts_message_length`, then create.

**Gift list** — the sender's own gifts and their status, reached from the profile.

**The flow dead-ends after draft, and the UI must say so.** The sender reserves a
slot and can go no further until payments land. A screen that implies a payment step
is coming next is worse than one that plainly says the slot is held for fifteen
minutes and checkout is not built yet.

## 8. Architecture

Phase 3's rules, unchanged and now the house style:

- A narrow `GiftRepository` (interface + impl) — catalog reads, draft creation, and
  the sender's list. Not folded into any existing repository.
- Registered in `app.dart`, read with `context.read<GiftRepository>()`. **No
  `?? ConcreteImpl(...)` fallback.**
- `GiftCubit` mixes in `ReentrancyGuard` from `lib/core/reentrancy_guard.dart`.
  A double-tap on "create" must not burn two slots — and here that is not a
  cosmetic concern, because a burnt slot is real capacity removed from a real van.
- All copy in `lib/core/app_strings.dart`.
- Domain rules as methods on value objects, not helpers scattered in cubits.

## 9. Testing

| Layer | Covers |
|---|---|
| pgTAP | `rpc_create_gift`'s celebration guard, reverted and watched to fail; the cron actually releasing a slot; the sender's inability to reach the address |
| Contract, real Supabase | `GiftRepository` — catalog reads, draft creation, the `23514` oversold path |
| Cubit, `bloc_test` | Selection state, re-entrancy, the oversold branch reaching the user as its own message |
| Widget | The slot picker, including a full slot rendered disabled |
| Race | Two concurrent creates for the last slot, using M0's `tests.race_last_slot` |

Two standing rules carry: **a green suite is not evidence** until the new assertion
has been watched to fail with its implementation reverted — eight tests across
earlier phases passed against the exact bug they were written to catch; and any
widget test counting screens passes `skipOffstage: false`.

This phase needs **one new test phone number**, continuing the one-per-suite
convention. Two suites sharing a number has caused a cross-file failure twice on
this project.

## 10. Risks carried into this phase

1. **No end-to-end run of the app on a device has ever been performed.** Every
   Flutter test runs on the Dart VM. An iOS App Transport Security defect once
   survived 96 passing tests and died only when a human ran a simulator. This phase
   adds four screens and does not close that gap.
2. **The suppression oracle is reduced, not closed** (M1 Phase 3 ledger §6 and §7).
   Dormant only because `private.suppress_person` has no Edge Function caller.
3. **`[auth.sms] enable_confirmations = true`** is a load-bearing security control
   guarded by no test, and `supabase init` or a CLI upgrade rewrites that file.
4. **`addresses` has an `ON DELETE RESTRICT` FK from `address_access_log`**
   (M1 Phase 2a carry-forward #9), which becomes live when the ops console ships.

## 11. Open questions

1. **Where the occasion date comes from.** `create_gift` takes `p_occasion_date`
   directly. The natural source is the recipient's next birthday via
   `Birthday.nextOccurrence`, which already encodes the Feb 29 → Feb 28 rule the
   reminder fan-out uses. The implementation plan settles whether the sender may
   override it; the spec's position is that they may not, because a cake dated
   anything other than the birthday is a different product.
2. **The recipient can read the whole gift row, including `amount_minor`.**
   Found while verifying §6. `gifts_select_participants` grants SELECT to
   `recipient_person_id = my_person_id()` with no column restriction, so a claimed
   recipient can read what their gift cost. They are meant to know a gift is coming —
   they confirm the address for it — but the price is a different matter, and
   revealing it is a social faux pas at best.

   Out of scope here: no recipient-facing surface ships in Phase 1a. **It becomes
   live in Phase 1b**, which is exactly when a recipient first touches a gift, so
   1b's plan must decide whether to restrict the column or accept it. Recorded now so
   it is a decision then rather than a discovery.

3. **Whether a sender may hold two slots at once.** Nothing in the schema forbids
   it. Left open deliberately — it is a product decision that costs nothing to
   defer, and the fifteen-minute expiry bounds the damage either way.
