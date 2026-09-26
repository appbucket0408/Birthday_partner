# M4 Phase 1 — the ops console's live half

Execution record, 27 Sep 2026. Follows M3 Phase 1b.

Executed **inline** (superpowers:executing-plans), not subagent-driven. The user chose
speed after subagents stalled eight times in the session, five of them on M3 Phase 1b's
final review. Consequence, stated plainly: **there was no per-task reviewer.** One
whole-branch review is the only fresh context this phase buys, and it has not run yet.

## What this phase delivered

A staff web console for the two things operable today — the product catalog and the
delivery calendar — served from a second Flutter entry point (`lib/main_ops.dart`) built
for web. Three screens: sign in, service areas & products, delivery slots.

Four of M4's five originally-specced surfaces were **deliberately not built**: the
manifest, gift detail with a logged address read, status transitions and refunds all
need gifts past `paid`, and payments are blocked on a provider account. Building them
would have made this the fourth consecutive phase shipping something nobody can reach.

## 1. Final verification numbers

Cold, on `m4-phase1-ops-console`.

| Command | Before (`d13a08a`) | After |
|---|---|---|
| `supabase db reset && supabase test db` | 32 files / 295 assertions PASS | **32 / 295 PASS** |
| `./supabase/functions/test.sh` | 18 passed | **18 passed** |
| `./supabase/functions/test-signup.sh` | did not exist | **1 checked, 0 failed** |
| `fvm flutter analyze` | clean | **clean** |
| `fvm flutter test --exclude-tags=contract` | 207 | **241** |
| contract (`test/repositories test/e2e`) | 47 | **53** |
| `fvm flutter build web -t lib/main_ops.dart` | did not exist | **✓ Built build/web, 30M, 18.7s** |

The contract count rose from 47 to 53 because this phase's six `ops_repository_test.dart`
assertions live in `test/repositories/`.

### The contract suite's flakiness cost time again

The first cold run gave **45 passed / 8 failed in 11 minutes 39 seconds**. An immediate
rerun gave **53 passed / 0 failed in 1 minute 39 seconds**. A tenfold runtime difference
with no code change between runs: these are timeouts, not assertions.

This is the carry-forward M3 Phase 1b recorded ("intermittent contract timeouts and a
`JWT issued at future` error, suggesting clock skew between the db container and the
host"). It has now misled two consecutive phases. **It deserves its own task** — a red
contract run currently means "rerun and see", which is exactly the habit that lets a
real regression through.

## 2. Config guard

`[auth.sms] enable_confirmations = true` — intact.

**Its line number changed: 252 → 272**, because Task 2's comment block added 20 lines
above it. Nothing breaks, because every check in this project greps by content
(`grep -n enable_confirmations`), not by line. But the literal "line 252" is now stale in
the M4 spec, the M4 plan, and both M3 phase ledgers.

Those were accurate when written and are left alone. The lesson is that citing a line
number for a guard, in a file `supabase init` and CLI upgrades rewrite wholesale, was
always fragile. Future references should name the `[auth.sms]` block.

## 3. Per-task commit range

| Task | Commits |
|---|---|
| 1 — data layer | `d13a08a..1159943` |
| 2 — close email self-signup | `1159943..d185825` |
| 3 — console shell + sign-in | `d185825..5554e32` |
| 4 — catalog screen | `5554e32..40fb5ad` |
| 5 — slot capacity editor | `40fb5ad..788c2d2` |
| 6 — web build, verification, ledger | `788c2d2..HEAD` |

## 4. Not verified

- **The web bundle has never been loaded in a browser.** `flutter build web` succeeding
  is not the same as the console working. That is a human step, like the device run.
- **`[auth.email] enable_signup = false` is covered by no automated suite.** It is a
  GoTrue setting read at container start; no Dart test reaches the signup endpoint and no
  pgTAP test can see an env var. `supabase/functions/test-signup.sh` is the manual check —
  the same arrangement `test-gateway.sh` provides for `verify_jwt`. It was watched to
  fail against the old config before the change.
- **No device or simulator run has ever happened, in any phase.** This phase adds no
  mobile screens, so no new exposure there, but the standing risk is unreduced.
- **There was no per-task review.** Inline execution removed that gate by design.

## 5. Every ruling, with its cost if wrong

**Pre-flight, F1 — the router named two screens that did not exist.** Task 3 builds
`ops_router.dart` with `/catalog` and `/slots`, but those screens arrive in Tasks 4 and
5. As written it could not compile — the exact defect M1 Phase 2b shipped, whose router
referenced five screen classes it never imported. Decided: Task 3 ships a labelled
placeholder per route, deleted by the task that replaces it. *Cost if wrong: two
throwaway widgets.* **Outcome: worked. Both placeholders were deleted on schedule, and
the router's arrival test kept passing unchanged across both swaps.**

**Branching from an unmerged branch.** M4 is cut from `d13a08a` on
`m3-phase1b-recipient-confirm`, not from `main`, because merging Phase 1b is the user's
call. *Cost if wrong: if Phase 1b never merges, M4 carries it along.* Its review range is
cut from `d13a08a`, not `main`, so a reviewer does not re-read Phase 1b.

**Task 1 — a new OTP test number required a `config.toml` edit.** The brief says "this
suite's own phone number" without saying that supplying one means editing the guarded
file. Added `919999000014`; guard verified before and after; diff additive only. A full
`supabase stop && supabase start` is required after — the first run failed with a live
Twilio error because an earlier stop had failed while Docker was down, so GoTrue still
held the old list. *Cost if wrong: one unused test number.*

**Task 1 — `Product` had no `isActive` field.** The brief's own assertion reads
`created.isActive`. The model was built for the buyer's catalog, where `productsIn`
filters to active rows so everything it maps is active by definition. Added via TDD,
non-nullable with a `true` default: `is_active` is `not null default true`, so a nullable
field would push a null check into every consumer for a case the database forbids.
*Cost if wrong: one field and two tests.*

**Task 1 — the brief's test 1 could not pass, and my test was wrong rather than the
code.** It has a non-staff caller expect `allProductsIn` to return an inactive product.
`products_select_active for select using (is_active)` hides those rows; what admits them
for staff is `products_staff_write for all using (private.is_staff())`, Postgres ORing
the two permissive policies. So "the console can see inactive products" is **not** a
property of the repository's query alone — omitting the client filter is necessary but
not sufficient. Split into 1a (non-staff sees only active) and 1b (staff sees both).
*Cost if wrong: one test became two.*

**Task 2 — the guard's line number moved (see §2).** Decided not to retro-edit historical
documents. *Cost if wrong: someone greps line 252 and misreads which setting they found;
mitigated because the grep returns all matches with their numbers.*

**Task 3 — the router needed a `refreshListenable`.** The brief did not mention one.
Without it the redirect evaluates once and a successful sign-in leaves the user staring
at the sign-in screen. *Cost if wrong: one adapter class, ~12 lines.*

**Task 4 — replacing a placeholder broke three router tests.** The real
`OpsCatalogScreen` reads `OpsRepository` off context where the placeholder read nothing,
so the router test's tree needed a provider. Not a code defect: the router is correct,
the test's tree was incomplete for what it now renders. *Cost if wrong: a fake in one
test file.* **The same fake covered Task 5's swap, as predicted.**

**Task 5 — the one place `DateTime.now()` is allowed.** The router picks the slots
screen's default date range. Justified because it decides only what to **show**: nothing
written to the database derives from it, `slotDate` comes from the caller, and the cubit
never calls `now()`. Stated in a comment at that call site so a later reader does not
"tidy" a `now()` into the cubit. *Cost if wrong: the default window is off by a day near
midnight, and staff change the range.*

**Task 6 — the project was not configured for the web at all.** `flutter build web`
failed with "This project is not configured for the web". This *is* the unknown the M3
Phase 1a spec named when it deferred a web target, arriving on schedule. Ran
`flutter create . --platforms web`, which the plan did not anticipate. *Cost if wrong:
scaffolding files that are inert if unused.*

**Task 6 — `flutter create` silently dropped the android and ios migration records**,
replacing both `.metadata` entries with `web` rather than appending. Restored all three by
hand so the change is purely additive. *Cost if wrong: `.metadata` is advisory for
migration tooling, not build input, so the blast radius is a future upgrade rather than
today's build.* It also created a counter-app `test/widget_test.dart`, deleted.

**A trap worth recording for any CI:** `flutter build web` **exited 0** when it had not
built anything. A pipeline trusting the exit code would record a successful build that
produced nothing.

## 6. Deferred minors

- `ops_slots_cubit_test.dart` tests 2 and 3 assert via `(state as OpsSlotsError).message`,
  so a wrong state fails as a cast error rather than naming the state. Asserting
  `isA<OpsSlotsError>()` first would give a better diagnostic. Detection works; this is
  cosmetic.
- The web build emits a `cupertino_icons` font-family warning that predates this phase,
  and a wasm dry-run suggestion. Neither blocks.

## 7. Carried forward

- **M4 Phase 2** — manifest, 6am cron, gift detail with logged address read, status
  transitions, refunds. Blocked on payments.
- **`address_access_log.staff_profile_id` is `ON DELETE RESTRICT`** on a deliberately
  immutable table, so a staff member who has ever opened a gift's address can never be
  deleted. Inert until Phase 2 ships that read — and it is the same shape as the
  `gifts.sender_profile_id` regression M3 Phase 1a's final review caught, so **Phase 2
  must decide the policy before shipping, not after**.
- **The contract suite's intermittent timeouts** (§1). Now misleading in two consecutive
  phases; deserves its own task.
- **The `23514` overload.** `draft_cubit.dart:68` still branches on the bare code. This
  phase designed around it rather than fixing it: every write in the console validates
  client-side precisely because four constraints share that code.
- Spec §9's race row; `seed.sql`'s non-idempotent `products` insert and its NULL GoTrue
  columns; hosting for the console bundle (this phase builds, it does not deploy).

## Suite size at phase close

pgTAP 32 files / 295 assertions · Deno 18 · signup check 1 · Flutter 241 non-contract +
53 contract · web bundle 30M.
