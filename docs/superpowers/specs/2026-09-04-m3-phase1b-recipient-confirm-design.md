# M3 Phase 1b — recipient confirmation

Design, 4 Sep 2026. Follows M3 Phase 1a (merged to `main` at `04436ed`).

## 1. What this phase is

The recipient's half of a gift: a link they open, an address they give, a
confirmation. Plus two debts Phase 1a deliberately deferred and this phase is the
natural home for.

Three deliverables:

1. **A confirm endpoint** — one Edge Function serving a server-rendered HTML form,
   keyed by the gift's `confirm_token`.
2. **F3's server-side date constraint** — `slot_date = occasion_date` enforced in
   `private.create_gift`, not just in the picker's UI.
3. **§11.2** — a recipient can no longer read what the sender paid.

## 2. A departure from the M3 spec, recorded deliberately

The M3 Phase 1a spec (§2) named this phase "**the confirm page and the Flutter web
target**", reasoning that "the web build is new to this project and carries the
unknowns; isolating it means a web-build problem cannot stall the app half."

**There is no Flutter web target in this phase, and none is planned for the confirm
page.** No `web/` directory, no `flutter build web`, no hosting decision, no new CI
target.

The reason is the recipient. They are not a user of this app — they are someone's
aunt who receives an SMS, taps a link on a mid-range Android browser, and types five
address fields once, ever. Flutter web would ship a multi-megabyte payload with a
cold start measured in seconds for a form that is roughly four kilobytes of HTML. The
isolation the spec wanted is achieved better by not building a second client at all.

Consequence if this is wrong: should a richer recipient surface ever be needed
(tracking a delivery, a gift history), it needs a real client, and this decision
would have to be revisited then rather than extended. That is a fair trade for a
one-time address form.

## 3. What M0 already built

Read `supabase/migrations/20260822000007_gifts.sql` and
`20260822000008_gift_lifecycle.sql` before implementing. M0 shipped more of this
than the phase name suggests:

- **`gifts.confirm_token uuid not null default gen_random_uuid() unique`**
  (`20260822000007_gifts.sql:19`) — every gift has one **from creation**, and
  `confirm_token_used_at timestamptz` (`:36`) makes it single-use.
- **`private.confirm_gift(p_confirm_token, p_line1, p_line2, p_city, p_pincode,
  p_label default 'Home')`** (`gift_lifecycle.sql:125`) — already implements the
  whole transaction: locks the gift `for update`, rejects an unknown token, rejects a
  used token, requires status `awaiting_confirm` (else `23514`), and **refunds when
  the city is outside the service area** (spec §5 rule 5). Revoked from `public`,
  `anon` and `authenticated` (`:247-248`).
- **`private.refund_gift(p_gift_id)`** (`:194`) — a status transition to `refunded`
  and nothing more. **No payment provider is involved**, so the out-of-area refund
  path is fully functional in this phase even though payments do not exist.
- **The status machine** (`20260822000007_gifts.sql:79-83`) — the only transition
  *into* `awaiting_confirm` is from `paid`.

## 4. The confirm endpoint

`supabase/functions/confirm/index.ts`, the sixth Edge Function, following the house
shape of `claim_profile` and `delete_account`.

### 4.1 Two methods

- **`GET /functions/v1/confirm?token=<uuid>`** → an HTML page. Inline `<style>`, no
  external assets, no JavaScript framework, no build step. Shows the sender's display
  name, the product name, the occasion date, and a form with five inputs:
  `line1`, `line2`, `city`, `pincode`, `label`.
- **`POST /functions/v1/confirm`** → `application/x-www-form-urlencoded` body,
  calls the gift RPC, returns an HTML result page.

Both are unauthenticated. **The token is the capability.** There is no Supabase
session, no cookie, and no login — a recipient is not a user of this app and must not
be made into one to receive a cake.

### 4.2 The RPC wrapper

`private.confirm_gift` is revoked from `public`, so `service_role` has no `EXECUTE`
grant on it. Add:

```sql
create or replace function public.rpc_confirm_gift(
  p_confirm_token uuid, p_line1 text, p_line2 text,
  p_city text, p_pincode text, p_label text default 'Home')
returns public.gifts language plpgsql security definer set search_path = ''
as $$ begin
  return private.confirm_gift(p_confirm_token, p_line1, p_line2,
                              p_city, p_pincode, p_label);
end; $$;

revoke execute on function public.rpc_confirm_gift(uuid,text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.rpc_confirm_gift(uuid,text,text,text,text,text)
  to service_role;
```

`service_role` **only** — matching `rpc_delete_own_draft_gifts`. It must never be
`anon`-callable: `anon` reaching it would let anyone who guesses a token write an
address, and would also make it callable without the endpoint's own validation.

**Do NOT add it to the R3 allowlist** in `11_rls_coverage.test.sql:42-50`. R3 asserts
the *exact* comma-separated set of `public` functions for which
`has_function_privilege('authenticated', …, 'EXECUTE')` holds, and its comment is
explicit: "extend it only for a function clients are meant to call." Because
`rpc_confirm_gift` is `service_role`-only, it must not appear in that set, so **the
expected string does not change** — and that unchanged string is precisely the proof
that the revoke landed. `rpc_delete_own_draft_gifts` (Phase 1a) is absent for the same
reason and sets the precedent. Adding it would defeat the test.

### 4.3 The outcomes, and what each reveals

`confirm_token` is populated at **creation**, not at payment, so a well-formed token
exists while a gift is still `draft`. The endpoint must therefore distinguish five
cases, not four:

| Case | Response | Page |
|---|---|---|
| Confirmed | 200 | "Thank you — the cake is on its way to \<city\>." |
| City outside the service area → refunded | 200 | "We do not deliver to \<city\> yet, so the gift has been refunded." Honest, and the refund already happened. |
| Token already used | 200 | "This gift is already confirmed." |
| Unknown token | 404 | Neutral: "This link is not valid." |
| **Token valid but gift is not `awaiting_confirm`** (e.g. still `draft`, or `expired`) | 404 | **The same neutral page, byte for byte.** |

**The last two are deliberately indistinguishable.** Separating them would turn the
endpoint into an oracle confirming that a token is real but its gift not yet paid —
information an attacker probing tokens should not get, and information no legitimate
recipient needs, because a link is only ever sent after payment. `already used` stays
distinct because a recipient who taps their own link twice deserves a straight answer,
and holding the token is itself evidence of legitimacy.

A pgTAP or Deno assertion must prove the unknown-token and wrong-status responses are
identical, and it must be watched to fail.

### 4.4 Token strength, stated rather than assumed

`gen_random_uuid()` is UUID v4: 122 random bits. Brute-forcing the token space is not
feasible, so no endpoint rate limit ships in this phase and the 404 timing difference
between "no such row" and "wrong status" is not a practical oracle. **Recorded so it
is a decision, not an omission** — if the token ever becomes shorter, or guessable,
or reused, this reasoning must be revisited.

The token travels in an SMS URL and will persist in the recipient's message history.
That is acceptable for a single-use address form on a gift the sender chose to send,
and is noted rather than mitigated.

### 4.5 What the page must not show

Never `amount_minor`, and never any address the recipient did not just type.

The GET handler reads exactly four values, as `service_role`, with an explicit column
list — never `select *`, so a column added to `gifts` later cannot leak by default:

- `profiles.display_name` via `gifts.sender_profile_id` (`profiles.display_name` is
  `not null`, `20260822000003_profiles.sql:4`)
- `products.name` via `gifts.product_id`
- `gifts.occasion_date`
- `gifts.message` — nullable; see §11 question 1

A Deno assertion must prove the rendered HTML contains no price, asserting on the
**response body** rather than on the query shape. It must be watched to fail by
interpolating the amount into the template.

## 5. F3 — the date constraint moves to the server

Today `slot_date = occasion_date` is enforced **only** by the slot picker's
client-side exact-date filter (`slot_picker_screen.dart`). `private.create_gift`
checks sender, self-gift, product-active, slot-in-area and capacity — no date check —
and `gifts` carries no such constraint. Anything creating a gift outside the picker
can write a row whose van arrives on a different day than the occasion it records.

Add the check to `private.create_gift`, raising **`23514`** (the code it already uses
for "slot is not in the product's service area", and the code the client already maps
for a slot problem):

```
if the chosen slot's slot_date <> p_occasion_date then
  raise exception 'slot % is not on the occasion date' using errcode = '23514';
```

Fold it into the existing slot lookup rather than adding a second query.

**This breaks four green contract tests, which is why Phase 1a deferred it.**
`test/repositories/gift_repository_test.dart` pairs
`occasionDate: DateTime.now().add(const Duration(days: 10))` with `roomySlotId` on
`current_date + 1` and `tightSlotId` on `current_date + 2` — assertions 4, 5, 6 and 7
(`:321, :347`, and the assertion 6/7 fixtures). Re-date the **fixtures**, not the
constraint: each `createDraft` call must pass the `occasionDate` matching its slot.
The seeded gift row at `:232` (`current_date + 60` against `roomySlotId`) is inserted
by raw SQL and bypasses `create_gift`, so it is unaffected — but re-date it anyway so
the fixture does not model an impossible row.

The client filter **stays**. This makes the invariant defence in depth rather than
replacing one single point of failure with another.

## 6. §11.2 — a recipient can no longer read the price

### 6.1 The exposure

`gifts_select_participants` (`20260822000007_gifts.sql:176-184`) grants `select` to
`authenticated` where `sender_profile_id = auth.uid() or recipient_person_id =
private.my_person_id() or private.is_staff()`, **with no column restriction**. A
claimed recipient who is also an app user can query `public.gifts` through PostgREST
and read `amount_minor` — what the sender paid for their present. No app screen shows
it, but no app screen has to: the row is readable directly.

### 6.2 Why not a column revoke

Postgres column privileges are **per role, not per row**, so
`revoke select (amount_minor) ... from authenticated` hides the price from the
*sender* too. Once payments ship the sender needs a receipt, so that fix would have
to be undone in Phase 2. It also breaks things immediately: `myGifts()` issues a bare
`.select()` (`gift_repository_impl.dart:122`), and a role lacking `SELECT` on one
column gets a **permission error**, not a silent omission; and `Gift.fromRow` reads
`row[ApiParams.amountMinor] as int` non-nullably (`gift.dart:76`), which is the exact
`TypeError` shape as Phase 1a's `Product.flavour` defect.

### 6.3 The fix

**Drop the recipient branch from `gifts_select_participants`.** The policy becomes
sender or staff. The sender keeps the whole row, including the price they paid. A
recipient reads nothing from `public.gifts` at all.

This is safe today because **no recipient-facing in-app surface exists**: the gift
list is scoped to `sender_profile_id`, and the confirm endpoint never uses RLS — it
runs as `service_role` and the recipient has no session.

### 6.4 The M0 guarantee this changes, stated plainly

`supabase/tests/database/07_gifts.test.sql:86-92` asserts *"the recipient sees the
gift addressed to them"* — `count(*) = 1` as the honoree. That assertion must be
**inverted** to assert zero rows, with a comment naming this spec and the reason.

Inverting a passing M0 assertion is a deliberate behaviour change, not a test fix, and
the plan must treat it as such: the new assertion has to be watched to fail against
the old policy, proving it tests the policy rather than the fixture.

When a recipient-facing surface does ship — "a gift is coming for you" — access
returns through a **narrow `security definer` function exposing safe columns only**,
never by restoring the broad branch. That is the right shape regardless, and this
change makes it the only available shape.

## 7. Testing

| Layer | Covers |
|---|---|
| Deno (`supabase/functions/test.sh`) | All five confirm outcomes; unknown-token and wrong-status responses byte-identical; the rendered HTML containing no price; a token-reuse attempt; a `GET` with a malformed/absent token; `POST` with a missing field |
| pgTAP | `rpc_confirm_gift` callable by `service_role` and refused to `anon` and `authenticated`; the date constraint raising `23514`, reverted and watched to fail; the recipient reading **zero** gift rows, watched to fail against the old policy; `rpc_confirm_gift` in the R3 allowlist |
| Contract, real Supabase | The four re-dated `createDraft` fixtures still green; a mismatched date rejected with `23514` |

`awaiting_confirm` is reachable only from `paid`, so every confirm fixture must be set
up with `service_role` — exactly as the M3 spec sanctions for the payment gap.

**A green suite is not evidence.** Every new assertion is watched to fail with its
implementation reverted, then restored. Phase 1a caught thirteen tests that passed
against the exact bug they were written to catch.

## 8. What this phase does NOT make reachable

Stated up front so it is not discovered later as a disappointment:

**No user can reach the confirm page when this phase closes.** Two things stand in
the way, both out of scope:

- A gift reaches `awaiting_confirm` only from `paid`, and payments are M3 Phase 2,
  blocked on a provider account.
- The link is delivered by SMS, which is M1 Phase 2c, blocked on an SMS account.

The value of this phase is that the recipient path becomes **real and proven** behind
a token, so that when payments and SMS arrive, nothing about confirmation is
unwritten. It is the third consecutive phase to ship an honest dead end, and the last
one that needs to.

## 9. Risks

1. **No device or simulator run has ever happened, in any phase.** Every Flutter test
   runs on the Dart VM. This phase adds no Flutter screens, so it adds no new
   exposure — but it does not reduce the standing risk either.
2. **`[auth.sms] enable_confirmations = true`** (`supabase/config.toml:252`) guards a
   reproduced total-account-takeover bug and is covered by no test. Every task
   touching that file must re-verify it.
3. **Inverting the M0 recipient assertion** (§6.4) is the only behaviour change here
   to an existing guarantee.
4. **`seed.sql`'s `products` insert is not idempotent** — pre-existing, unfixed,
   masked because the project always uses `supabase db reset`.

## 10. Carried forward, not addressed here

- **Spec §9's race row** — a real two-connection race against `rpc_create_gift` using
  M0's `tests.race_last_slot`. Phase 1a waived it with a factually wrong rationale
  (its assertion is sequential and single-connection); the waiver is corrected and the
  gap recorded, but the test is still unwritten.
- **The paid-gift deletion policy** — `delete_account` clears `draft` and `expired`
  gifts; any other status still refuses. Phase 2 must decide reassign / anonymise /
  refuse, and revisit that function before payments ship.
- **`address_access_log.staff_profile_id`** is `ON DELETE RESTRICT` and the table is
  deliberately immutable, so a staff member who has opened the ops console can never
  be deleted. Inert until M4.
- **Whether a sender may hold two slots at once** — nothing forbids it; the
  fifteen-minute expiry bounds the damage.

## 11. Open questions

1. **Does the confirm page need to show the sender's message?** `gifts.message` is
   capped at 280 characters and the sender wrote it for the recipient. Showing it on
   the confirm page is the obvious place, but the spec's original intent for the
   message is unrecorded. Defaulting to **showing it**, since a gift with a hidden
   note is a worse product; reversible either way.
2. **What happens to the address after delivery?** `addresses` rows persist and
   `address_access_log` audits staff reads. Retention is an M4 ops question, untouched
   here.
