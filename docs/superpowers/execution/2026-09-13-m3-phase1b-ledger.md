# SDD ledger — plan: docs/superpowers/plans/2026-09-04-m3-phase1b-recipient-confirm.md

Spec: `docs/superpowers/specs/2026-09-04-m3-phase1b-recipient-confirm-design.md`
Branch: `m3-phase1b-recipient-confirm`, in the main checkout (no worktree — same
ruling as every prior phase: worktrees cost this project twice before, M0's
removal nearly destroyed a ledger and Phase 2a's isolation stopped a session
merging its own work).
Controller's running notes: `.superpowers/sdd/2026-09-04-m3-phase1b-recipient-confirm/progress.md`
BASE at start: `80ff49b`. HEAD at close: `052799d`.

This is the phase close. Tasks 1–7 are complete and individually reviewed
(see `progress.md` for the full per-task record: every implementer report,
every review, every ruling, every defect). This document is the
cold-verification record and the carry-forward manifest.

## What this phase delivered

A recipient-facing confirm page: one **unauthenticated** Edge Function
(`supabase/functions/confirm/index.ts`) serving plain server-rendered HTML,
keyed by a gift's `confirm_token` — no Supabase session, no cookie, no
login, because a recipient is not a user of this app and must not be made
into one to receive a cake. Plus two long-deferred debts closed:

1. **F3's server-side date constraint** — `slot_date = occasion_date` is now
   enforced inside `private.create_gift` itself (raising `23514`), not only
   by the slot picker's client-side exact-date filter. The client filter
   stays; this is defence in depth, not a relocation.
2. **Spec §11.2** — `gifts_select_participants` no longer has a recipient
   branch. A recipient can no longer read `amount_minor` — what the sender
   paid — through `public.gifts`. The policy is now sender-or-staff only.

Deliberately **no Flutter web target**, departing from the M3 Phase 1a
spec's own framing of this phase as "the confirm page and the Flutter web
target." The recipient taps an SMS link on a mid-range phone to type five
address fields once, ever; Flutter web would ship a multi-megabyte payload
for what is roughly four kilobytes of HTML. Recorded as a deliberate
departure, not an omission — if a richer recipient surface is ever needed
(tracking a delivery, a gift history), it needs a real client and this
decision gets revisited then, not extended.

Commits: `804febe` (spec amendment), `80ff49b` (plan), then the seven tasks
below, closing at `052799d`.

---

## 1. Final verification numbers

All commands run cold — `supabase db reset` preceding every pgTAP run — on
branch `m3-phase1b-recipient-confirm`, base `80ff49b`, HEAD `052799d`.

| Command | Before (`80ff49b`) | After (`052799d`) |
|---|---|---|
| `supabase db reset && supabase test db` | 30 files / 287 assertions, PASS | **32 files / 295 assertions, PASS** |
| `./supabase/functions/test.sh` | 6 passed, 0 failed | **18 passed, 0 failed** |
| `fvm flutter analyze` | clean | **clean** |
| `fvm flutter test --exclude-tags=contract` | 207 | **207** |
| contract (`test/repositories` + `test/e2e`) | 47 | **47** |
| `./supabase/functions/test-gateway.sh` | did not exist | **6 checked, 0 failed** |

The Flutter counts (207 non-contract, 47 contract) are unchanged from
before this phase — this phase's file list never touched `lib/` or
`test/`'s Flutter suites directly except for one comment correction in
`draft_cubit.dart` (folded into Task 6) and the fixture re-dating inside
`gift_repository_test.dart` (Task 5), neither of which adds or removes a
test. The growth is entirely on the server side: pgTAP gained 2 files / 8
assertions (Task 1's grant test plus Task 6's RLS-policy test file
touch, plus Task 5's date-constraint assertions), and Deno tripled from 6
to 18 (Task 1 added none to Deno; Tasks 2–4 built the whole `confirm`
suite: the `verify_jwt` guard test, the GET form and neutral-404 tests,
the already-confirmed and XSS-escaping tests, and the POST handler's four
outcomes).

`test-gateway.sh` is new this phase (Task 2's own scope addition, ruled in
below) and cannot be folded into `test.sh`: the two need the Supabase
functions server running with opposite `--no-verify-jwt` flags, so it stays
a separate, manually-run script.

`config.toml:252` `[auth.sms] enable_confirmations = true` intact.
`git diff main -- supabase/config.toml` shows **only** the new
`[functions.confirm]` block and its comment (reproduced in §2 below) — the
project's first `[functions]` block ever, appended at the end of the file,
line 209's `[auth.email] enable_confirmations = false` untouched.

### Detail — the numbers were not simply "run once and recorded"

- **Task 5's constraint immediately caught a latent fixture bug.** The
  contract suite failed for the controller at 22/47 where the implementer
  had reported 47/47 — not a regression, a genuine time-of-day dependency.
  The fixture seeded slots with SQL `current_date + 1` (Postgres, UTC) but
  computed `occasionDate` with Dart's `DateTime.now().add(...)` (host,
  IST, +5:30). The two "today"s disagreed for 5.5 hours every night
  (roughly 23% of the clock) — harmless until the new constraint checked
  the date at all. Fixed by deriving both dates from **one** source (the
  slot insert's own `returning slot_date`, threaded into every
  `createDraft` call), verified with a negative control under
  `TZ=Pacific/Kiritimati` (UTC+14, failed pre-fix, passed post-fix) and
  `TZ=Pacific/Midway` (UTC−11) — a 25-hour spread.
- **Task 6's review agent stalled once** waiting on a colima restart, and
  the resumed `supabase test db` reported `Files=32/Tests=292 FAIL` —
  three fewer tests and a red result, purely from running without a
  preceding `supabase db reset` after the container restart. A clean
  reset recovered `Files=32/Tests=295 PASS`, matching the implementer's
  own report exactly. Not a regression; see the environment traps below.
- **The 295/18/207/47/6 line above is the controller's own cold run**,
  13 Sep 2026, after Task 7's implementer stalled mid-verification for
  the second time this session (see §3). The controller ran verification
  directly rather than re-dispatching a third attempt, and hit — then
  diagnosed — the worst of the three environment traps in the process
  (§4 below).

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

Line 252 (`[auth.sms]`) is the guard for a reproduced total-account-takeover
bug from Phase 2a: with `enable_confirmations = false`, GoTrue runs with
`SMS_AUTOCONFIRM=true` and `PUT /auth/v1/user {"phone": ...}` silently
rewrites and confirms a session's phone number with no OTP, letting an
attacker point their session at an unclaimed victim's number and claim
their person row. It is guarded by no test and no CI, and this phase named
it explicitly (spec §4.5, §9 risk 2) as a file it was about to edit for an
unrelated reason — the very shape of change that could disturb it by
accident.

```diff
+[functions.confirm]
+verify_jwt = false
```

is the **only** change to the file, appended after line 437 (the file's
prior end), with a comment block (reproduced in §0 above) recording: why
the endpoint must run unauthenticated, that this is the project's first
`[functions]` block, that every other function is deliberately absent from
it and stays at the default `verify_jwt = true`, and which two test
artifacts prove that (`confirm/index.test.ts` at the handler level,
`test-gateway.sh` at the gateway level).

This is the highest-risk edit in the phase (spec §9 risk 5): getting it
wrong in the permissive direction — a bug in per-function-block scoping
that widened the default for the other five — would have exposed
`claim_profile`, `delete_account`, `drain_reminders`, `resolve_contacts`
and `add_celebrations` to unauthenticated callers. Task 2 built and proved
both the handler-level and gateway-level halves of that guarantee (detailed
in §5's per-task record below). Must be re-checked by hand at every future
phase close until it is guarded some other way.

---

## 3. Per-task commit range

Derived from `git log --oneline main..HEAD` (`main` at `04436ed`, HEAD at
`052799d`).

| Task | Range | Notes |
|---|---|---|
| (spec + plan, pre-task) | `04436ed..80ff49b` | `17f0283` (design), `804febe` (spec amendment: verify_jwt is a required deliverable, not a detail), `80ff49b` (plan) |
| 1 — the service_role-only `rpc_confirm_gift` wrapper | `80ff49b..c6ac889` | `c6ac889`; plan-doc fix `3c09957` |
| 2 — `verify_jwt = false` + gateway guard | `3c09957..8e27579` | `7729996` (implementer), `cdaabf0` (fix round 1, fresh implementer), `8e27579` (fix round 2) |
| 3 — the GET form and the neutral 404 | `8e27579..03dfba4` | `2eacb99` (implementer), `03dfba4` (fix round 1: already-confirmed test + XSS escaping test) |
| 4 — the POST handler and its four outcomes | `03dfba4..f8bbe53` | `e86fed9` (implementer), `15f3c0f` (plan-doc fix), `f8bbe53` (fix round 1: pincode guard + 23514 narrowing, closing the Critical) |
| 5 — F3's server-side date constraint | `f8bbe53..1602762` | `6eb2db3` (implementer, uncommitted report — session rate limit), `1602762` (fix round 1: single-source-of-truth fixture dates) |
| 6 — §11.2, drop the recipient's read | `1602762..55b7b7f` | `55b7b7f` |
| 7 — phase close (staff demotion + this ledger) | `55b7b7f..052799d` | `052799d` (staff-demotion commit, controller-committed after the implementer stalled) |

`main..HEAD` = `04436ed..052799d`, 17 commits ahead of `main`, 0 behind, at
time of writing (branch runs directly off `main`, not a worktree).

---

## 4. Three environment traps

Each looks exactly like a regression and none is. This matters more than it
sounds: two of them cost real time in this phase.

1. **`supabase test db` without a preceding `supabase db reset`** reports a
   false failure after a container restart — *fewer* tests and a red
   result, the signature of a file aborting partway. Hit during Task 6's
   review, after colima had gone down and been restarted: a bare
   `supabase test db` reported `Files=32/Tests=292 FAIL`; `supabase db
   reset` first recovered `Files=32/Tests=295 PASS`, matching the
   implementer's own report exactly.

2. **A mass contract failure (30+)** usually means `supabase functions
   serve` died; the contract suite calls Edge Functions over real HTTP, so
   losing that process fails nearly every contract test at once, not just
   the ones touching `confirm`.

3. **`supabase db reset` orphans an already-running `functions serve`.**
   Kong keeps a stale upstream pointed at the edge-runtime container that
   `db reset` just replaced, and answers every function call with a 502
   ("invalid response was received from the upstream server"). The Deno
   suite then reports **0 passed / 18 failed — including `add_celebrations`'
   six, which this phase never touched.** Restarting `functions serve`
   alone does **not** fix it; Kong itself must be restarted (`docker
   restart supabase_kong_birthday_app`). The tell is that untouched suites
   fail too — that is the signature to look for, the same way trap 2's
   signature is "everything fails at once." A bare status-code probe is
   not enough to diagnose it, either: the controller's own first probe
   checked for a 404 and got one, and took it for the handler's own
   neutral 404 — it was Kong's. The fix was to grep the response **body**
   for the handler's own text, the same lesson `test-gateway.sh` already
   encodes (a status code alone never tells you who answered — Kong or
   the handler).

---

## 5. Not verified

- **No user can reach the confirm page.** A gift reaches `awaiting_confirm`
  only from `paid` (payments are M3 Phase 2, blocked on a provider
  account), and the link travels by SMS (M1 Phase 2c, blocked on an SMS
  account). The phase's value is that the recipient path is real and
  proven behind a token, not that anyone can use it yet — the third
  consecutive phase to ship an honest dead end, and per the spec, meant to
  be the last one that needs to.
- **No device or simulator run has ever happened, in any phase.** Every
  Flutter test runs on the Dart VM. This phase adds no Flutter screens, so
  it adds no new exposure — but the standing risk (named in every prior
  phase's ledger, and in Phase 2b's own history of an iOS ATS defect that
  survived 96 passing tests) is unreduced.
- **`[functions.confirm] verify_jwt = false` is invisible to the Deno
  suite**, which serves with `--no-verify-jwt` for every one of its 18
  tests and so bypasses Kong entirely. `test-gateway.sh` is the thing that
  actually covers the gateway-level guarantee, but it only runs manually,
  against a server started **without** the flag — it cannot join
  `test.sh`, since the two suites need opposite serve modes.
- **Whether a malformed pincode truly never reaches the database is
  unverified**, precisely. The handler validates the pincode format before
  calling the RPC (closing the Critical described in §7), but nothing in
  the suite distinguishes "the RPC was never called" from "the RPC was
  called and its transaction rolled back on the CHECK constraint." A
  precision gap in a code comment, not a known functional problem — flagged
  by the scoped re-reviewer on Task 4's fix round rather than assumed
  closed.

---

## 6. Carried forward

Every entry below is reproduced from
`.superpowers/sdd/2026-09-04-m3-phase1b-recipient-confirm/progress.md`
with its reasoning, not just its headline.

### `23514` is overloaded — the phase's most important carry-forward

Task 4's brief assumed `23514` (Postgres's generic CHECK-violation code)
meant, exclusively, "the gift is not awaiting confirmation." It does not.
Verified directly against the schema: `23514` is raised **explicitly** in
six places — `catalog_slots.sql:91`, `gifts.sql:126`,
`gift_lifecycle.sql:63`, `gift_lifecycle.sql:158`,
`birthday_parts.sql:149`, `phone_e164_guard.sql:66` — and **implicitly** by
every table CHECK constraint in the database, including
`addresses_pincode_format` (`pincode ~ '^[1-9][0-9]{5}$'`). Task 5 added a
**seventh** explicit raise for the slot-date mismatch. Phase 1a's Flutter
client already maps the bare code to "that slot just filled, pick another
window" (`draft_cubit.dart:68`) — so any handler, client or otherwise,
keying behaviour off this code alone is guessing.

This already caused a Critical bug this phase (§7). It is **not reachable
today**: `SlotPickerScreen` is the only route to `DraftCubit.create` and
filters slots to exact-day equality before the user can see one, so a stale
`_occasionDate` cannot reach `create_gift` through the UI — Task 5's date
check is defence in depth against non-UI callers only. But
`draft_cubit.dart:68` still branches on the bare code with no message
inspection, so a future picker change, a new entry point, or a race could
show "that slot just filled" for what is actually a date mismatch, with
`draft_cubit_test.dart:120-128` covering only the generic slot-full case
and nothing guarding the misattribution. Cost if wrong: a wrong, misleading
explanation shown to a real user, with no test to catch it.

### A repeat GET after an out-of-area refund shows the neutral 404

M0's `private.confirm_gift` sets `confirm_token_used_at` **only** on the
success path (`gift_lifecycle.sql:187`); the out-of-area path
(`gift_transition('declined')` → `release_slot` → `refund_gift`) returns
without setting it (`:166-177`). So after a refund the status is
`refunded`, the used-at flag stays NULL, and a repeat GET of the same link
falls past the already-used branch into the neutral 404 — a recipient who
was just refunded, revisiting their own link, reads "This link is not
valid." Accepted for this phase (ruling, not a fix): no user can reach this
at all until payments and SMS both ship; the POST already told the
recipient what happened at the moment it happened; distinguishing
`refunded` on GET would add a sixth outcome and its own disclosure
question; and setting the flag on the refund path means editing M0's
`confirm_gift`, outside this phase's constraints and something M0
deliberately avoided (its own comment says a retry is already impossible
because the status check rejects it). Cost if wrong: an unhelpful message
instead of an explanation, to a user who cannot exist yet — must be
revisited before the flow goes live.

### `seed.sql`'s `tests.create_user()` leaves GoTrue's `*_token` columns NULL

Task 3's implementer hit this directly: a raw `insert into auth.users`
fixture left `confirmation_token` and its siblings NULL. Because that
fixture runs over a **live, committed** connection (unlike pgTAP, which
rolls back), the single row broke GoTrue's `listUsers()` for the entire
local Auth service, which then silently broke `add_celebrations`'s
unrelated phone-reuse cleanup with `AuthApiError: Phone number already
registered` — root-caused via `docker logs
supabase_auth_birthday_app`, fixed by setting those columns to `''`. The
same gap exists in `seed.sql`'s own `tests.create_user()`, inert **only**
because pgTAP always rolls back. Left `seed.sql` untouched — correct for
this task's scope. Cost if wrong: any future live-connection seeder hits
this and breaks Auth service-wide, surfacing in a suite that has nothing to
do with the actual cause — the worst possible diagnostic, and this phase
already paid for it once.

### Intermittent contract timeouts and a `JWT issued at future` error

Surfaced incidentally during Task 5's verification, not caused by this
phase's work: one run hit 6 timeouts plus a "JWT issued at future" error in
unrelated suites (profile/graph/wish/contacts); an immediate rerun was
clean at 47/47. The error text suggests clock skew between the db
container and the host — the same class of problem as the timezone bug
Task 5 fixed in the fixture. Worth a look before anyone trusts a single red
run of the contract suite.

### From the spec, restated rather than left to fade with the branch

- **Spec §9's race row.** A real two-connection race against
  `rpc_create_gift`, using M0's `tests.race_last_slot`, is still unwritten.
  Phase 1a waived it with a rationale now known to be factually wrong (its
  cited assertion is sequential and single-connection, not a real race);
  the waiver has been corrected in the plan documents but the test itself
  remains undone work, not a fix-round item.
- **The paid-gift deletion policy.** `delete_account` clears `draft` and
  `expired` gifts today; any other status still refuses erasure. M3 Phase
  2 must decide reassign / anonymise / refuse before payments ship, and
  revisit that function.
- **`address_access_log.staff_profile_id`** is `ON DELETE RESTRICT` on a
  deliberately immutable table, so a staff member who has ever opened the
  ops console can never be deleted. Inert until M4.
- **`seed.sql`'s `products` insert is not idempotent** (`on conflict do
  nothing` with no inferable unique constraint) — pre-existing since Phase
  1a, unfixed, masked because the project always uses `supabase db reset`
  rather than a bare re-apply of `seed.sql`.
- **Whether a sender may hold two slots at once** — nothing forbids it;
  the fifteen-minute hold expiry bounds the damage.

---

## 7. Every ruling, with its cost if wrong

### Pre-flight

- **Ruling (no worktree).** Same as every prior phase — worktrees cost
  this project twice before (M0's removal nearly destroyed a ledger; 2a's
  isolation stopped a session merging its own work). Cost if wrong: no
  isolation from the shared checkout.
- **Ruling (F1 — the T5/T6 fixture-overlap).** T5 re-dates the `createDraft`
  calls in `gift_repository_test.dart` assertions 4–7; T6 then re-points
  assertion 7's fixture at a staff caller. Both touch the same assertion,
  sequentially, so no merge conflict — but T6 could have silently reverted
  T5's dating while rewriting the fixture. Decided: T6's dispatch carried
  an explicit instruction to preserve T5's occasion dates, and its
  verification re-ran the whole contract suite rather than assertion 7
  alone. Cost if wrong: a re-dated fixture regresses and assertion 4 or 6
  fails with `23514` — loud, not silent.
- **Ruling (T3's fixture mechanism).** The plan offered two options:
  service_role seed functions living in `public`, or direct Postgres
  seeding. Decided on **direct Postgres seeding**, and no
  `20260904000004_test_seed_helpers.sql` migration was created. Reasons:
  test-only functions in `public` are permanently visible to PostgREST and
  need their own revoke discipline forever; `add_celebrations`'s own test
  already sets the precedent of seeding over `SUPABASE_DB_URL` for exactly
  this reason; and `test.sh` already exports that variable, so the harness
  needs no change. Cost if wrong: the Deno test file grows a SQL block,
  and a schema change to `gifts` could break the fixture without breaking
  the handler.
- **Ruling (T6 Step 6's staff fixture, verified feasible before dispatch,
  not assumed).** `private.is_staff()` reads `public.profiles.is_staff`,
  and `authenticated` has no update grant on that column — so the API
  cannot make a caller staff, but the contract suite's `psql()` helper
  execs into the database container as superuser and already seeds rows no
  repository can create. That is the path used. Cost if wrong: T6 Step 6
  stops and reports, as its own text instructed.
- **Note, not a ruling:** the plan's stated ordering rationale ("doing T5
  before the endpoint tasks would force those fixtures to be written
  twice") was judged weakly argued — T3's fixtures must pair `slot_date`
  with `occasion_date` either way. The order is still correct, but for a
  different reason: migration `000002` (T5) sorts before T3's helper
  migration `000004`, so any `db reset` applies the date constraint first.
  Recorded so a later reader does not trust the stated reason over the
  real one.

### Task 1 — the `rpc_confirm_gift` wrapper

- **My defect #1 (controller), and it could never have worked.** The
  brief specified assertion 4's expected literal as `'{search_path=""}'`,
  which is not even a valid `text[]` encoding. Verified against the live
  DB: the real value is `'{"search_path=\"\""}'`. The implementer corrected
  exactly that literal and left the assertion structure alone. Correct
  call, no cost realized.
- **My defect #2 (controller), cosmetic.** The brief said assertions 2/3
  would "pass vacuously" pre-migration; wrong — `has_function_privilege` on
  a nonexistent signature hard-errors and aborts the whole script, so
  nothing runs individually. The implementer added two isolated probes
  beyond the brief's own step to exercise assertions 1 and 4 properly,
  closing a gap the brief itself had left.
- **Finding, not a defect:** the explicit `grant ... to service_role` is
  redundant — Supabase's default privileges on `public` already grant
  `service_role` EXECUTE on new functions there (verified via
  `pg_default_acl`). That default does **not** extend to `private`, which
  is why the wrapper itself is still necessary.
- **Ruling (keep the redundant explicit grant).** Both implementer and
  reviewer recommended keeping it; the controller agreed for a reason
  neither stated: relying on a platform default for a security boundary is
  worse than being explicit, because a Supabase change to default
  privileges would silently move the boundary. Cost if wrong: one
  redundant line.
- **My ruling on the shape of the fix-round probes.** The reviewer's
  Important 1 judged the probe "remove the grant line," found the
  assertion still passed, and called that a defect in the assertion.
  Correct observation, wrong probe for what the assertion actually claims
  (that `service_role` **can** execute) — the on-target probe is an
  explicit `revoke execute ... from service_role`, which is the real
  regression the assertion guards against. Both Important findings turned
  out to be closable by running the right probes, not by changing code.
  Cost if wrong: two throwaway probes and a corrected sentence in the
  report.
- **Ruling: no scoped re-review dispatched for fix round 1.** The round
  produced **zero code diff** — only a plan-doc commit and a correction to
  a gitignored report — so a re-reviewer would have nothing to read.
  Verified the substance directly instead: queried `pg_proc.proacl` via
  `aclexplode` on the live DB and confirmed `rpc_confirm_gift` grants
  EXECUTE to `postgres` and `service_role` only, with `anon` and
  `authenticated` absent. Cost if wrong: a fix round closed on the
  controller's own verification rather than a reviewer's — but the final
  whole-branch review still sees this diff.

### Task 2 — `verify_jwt = false` + the gateway guard

- **My claim was wrong, and the reviewer disproved it empirically.** The
  controller told the implementer "no local test can verify the config
  value" — true of `test.sh` (hardcodes `--no-verify-jwt`), false as a
  general claim. The reviewer restarted `functions serve` **without** the
  flag and curled all six functions with no Authorization header: `confirm`
  reached its own handler and returned 501; the other five were
  gateway-intercepted with Kong's distinct `{"msg": ...}` shape. That is a
  real local verification of exactly the thing the spec called highest-risk.
- **Ruling: automate the gateway check, accepting scope beyond the plan.**
  The reviewer proved the config is locally verifiable at all and
  recommended a second script. Decided to add it (this became
  `test-gateway.sh`) for three reasons: the spec itself names this config
  edit its highest risk; the project has already paid once for exactly this
  failure mode (an iOS ATS defect that survived 96 passing tests because
  nothing verified a config-level fact); and the check itself is six curls.
  It cannot join `test.sh` — the two need opposite serve flags — so it is a
  separate script with its own documented manual serve mode. Cost if wrong:
  one script and a documented manual step protecting the phase's riskiest
  change, which would otherwise have shipped on a reviewer's one-off curl.
- **Ruling: re-dispatch fix round 1 rather than have the controller fix
  the stopped agent's probe itself.** The first fix-round implementer
  stalled mid-probe, leaving `test-gateway.sh`'s `GATED` array with
  `confirm` swapped in for `add_celebrations` — the deliberate "prove it can
  fail" mutation, never restored. The one-word fix was trivial, but the
  round's remaining work (run against a flagless server, restore
  `--no-verify-jwt`, re-run `test.sh`, re-run the probe properly) was not.
  A controller fix would have skipped review and put unverified work in
  the tree. Cost if wrong: one extra dispatch.
- **Ruling: dispatch a scoped re-review for fix round 1**, unlike Task 1's
  zero-diff round — this round added 115 new lines
  (`test-gateway.sh`) no reviewer had ever seen. The re-reviewer
  reproduced every claim live (unmodified script: 6/6; probe on a scratch
  copy: exit 1 naming `confirm`; restored serve mode: `test.sh` 7/7) and
  found one Important (`check_exempt` cannot distinguish "gateway healthy"
  from "confirm's own deployment is broken" — a 404, a connection refusal,
  or a 500 all print "gateway-exempt OK") and one Minor (a comment
  overstating its own danger in the safe direction).
- **Ruling: no scoped re-review for fix round 2**, and the controller
  flagged this explicitly as the **second** round in this task it had
  closed on its own verification — a pattern, not a one-off, worth naming
  rather than let pass silently. What tipped it: 35 lines of shell in a
  test-only script, reviewed already line-by-line in the prior round, and
  the one hazard the fix could plausibly have introduced (over-tightening
  the 404 check so Task 4's later, legitimate neutral 404 would fail) is
  exactly what the controller verified directly — more specific than a
  generic re-review would likely have surfaced. Verified: the new 404
  rejection requires **both** status 404 **and** a body match on `/function
  not found/i`, correctly distinguishing Kong's "function not deployed"
  from confirm's own neutral 404 two tasks before that neutral 404 existed
  to collide with it. Cost if wrong: an unreviewed 35-line change to a
  test-only script, shipped to the whole-branch review with this ledger
  pointing at it directly.

### Task 3 — the GET form and the neutral 404

- **A real landmine found and disarmed, not merely a finding.** The
  implementer's fixture did a raw `insert into auth.users` leaving GoTrue's
  `confirmation_token` and sibling columns NULL. Because this fixture runs
  over a live, committed connection, that one row broke `listUsers()`
  service-wide and silently broke `add_celebrations`'s unrelated cleanup.
  Root-caused via `docker logs`, fixed by setting the columns to `''`.
  Reproduced above in §6 as a live carry-forward (the same gap exists in
  `seed.sql` itself, inert only because pgTAP rolls back).
- **Ruling: accept the out-of-area-refund neutral-404 gap, carry
  forward** — reasoning reproduced in full in §6 above.
- **Ruling: the reviewer's "already confirmed" Important is promoted, not
  waived.** The already-confirmed GET branch — one of the three outcomes
  the brief itself declares — had no test at all. Not deferrable to Task
  4 (POST): this is GET's own already-shipped branch, and the reviewer
  established it was reachable (the fixture's superuser connection can
  call `private.confirm_gift` directly to produce a used token, then
  re-GET it).
- **Ruling: the reviewer's escaping Minor is promoted to the same fix
  round, over its own rated severity.** The reviewer judged missing XSS
  coverage deferrable because the code is correct today and test values
  are seed-controlled. The controller disagreed: `display_name` is
  sender-chosen and rendered to an unauthenticated recipient, so a
  malicious sender's script-tag display name is a genuine (if low-stakes)
  attack on a stranger. The escaping was already correct; the promotion
  turns a manually-inspected property into a regression guard, cheaply.
- **Ruling: dispatch a scoped re-review despite the controller's own prior
  verification of both fix-round items** — explicitly naming this as the
  third round in the task sequence where a skip could have been justified,
  and three would be a pattern. Justified concretely: this task's own
  review had already found a declared-but-untested outcome in code the
  controller had personally judged fine. The re-reviewer then found things
  the controller had not checked (an attribute-injection question, proven
  not-exploitable by tracing the one attribute sink back through the
  token's UUID-regex gate; and idempotency, proven by running `test.sh`
  twice consecutively rather than assumed from the fixture's teardown
  logic).

### Task 4 — the POST handler and its four outcomes

- **My defect #1 (controller), the important one: revert #4 as specified
  was a no-op.** The brief claimed that breaking POST's 23514 mapping
  would fail Task 3's byte-identity test — false, that test is GET-only.
  The checklist item could never have proven what it claimed to prove.
  The implementer caught this and added a fifth test that actually forces
  the branch (POST a draft gift's token, compare byte-for-byte against a
  GET neutral 404, with the assertion message stating the point: "must
  call the SAME `renderNeutral404`, not a copy of its output").
- **My defect #2 (controller), arithmetic.** Step 4 predicted "14 passed"
  against a 12 baseline plus four new tests — should have been a different
  count; corrected in the plan documents afterward.
- **CRITICAL, and the controller's own brief's defect: `23514` is not what
  the brief assumed.** Full mechanism and cost reproduced in §6 above as
  the phase's headline carry-forward. The concrete, shipped consequence
  before the fix: a real recipient holding a genuinely `awaiting_confirm`
  gift who mistyped their pincode was told "This link is not valid" — a
  false, permanent-reading rejection of a link that was, in fact, still
  good (the transaction rolled back and the gift was untouched) — and this
  branch also skipped the `console.error` every other failure path gets,
  making it invisible in logs too.
- **Ruling (embedded in the fix round): two independent layers, not one.**
  Fix (a) is a `PINCODE_RE` pre-validation mirroring the DB's own
  `addresses_pincode_format` CHECK, upgrading a generic failure into a
  specific, actionable message. Fix (b) narrows the `23514` branch to
  require both the code **and** a message match against the
  not-awaiting-confirmation text, so any other `23514` (including a
  pincode CHECK violation that somehow still reaches the RPC) falls
  through to a logged generic failure instead of the false "invalid link."
  The implementer's own honest disclosure: reverting (a) alone did fail
  the new test, but not via the predicted neutral-404 misdiagnosis — (b)
  already intercepts that specific symptom, so the failure surfaced as a
  logged generic 500 instead. Both fixes are independently warranted; the
  scoped re-reviewer explicitly rejected "purely UX" as an undersell of
  (a) — without it a routine typo still yields an unlabelled 500 whose
  copy suggests transience/retry rather than "fix your input," still logs
  a spurious error, and still burns an RPC transaction the CHECK rolls
  back.
- **Ruling: dispatch a scoped re-review for the Critical's fix round
  regardless of the controller's own verification** — a Critical fix
  changing production error-mapping earns a review seat unconditionally.
  The re-reviewer went further than the controller had: verified the new
  pincode test's **first** assertion is status 200 (which is what fails
  under fix (a) alone reverted, proving the test exercises (a) and not
  merely (b)'s fallout), and ruled that reverting both fixes together
  would add no information (it exactly reproduces the pre-fix commit,
  whose behaviour is the already-diagnosed bug).

### Task 5 — F3's server-side date constraint

- **Ruling: fix the fixture, not the constraint, and derive both dates
  from one source.** Full mechanism in §1's Detail above. Cost if wrong:
  a suite that is green by day and red by night is worse than one that
  simply fails, because it teaches everyone to re-run rather than read.
- **Ruling: the fresh fix-round implementer asked before committing
  uncommitted, verified work; the controller committed it instead.**
  Judged as coordination, not authoring — the diff the review sees is
  identical either way, and the controller had already independently
  re-run the negative control (7/7 under both `TZ` extremes) before
  committing.
- **Ruling: fold the stale doc-comment fix into Task 6 rather than
  treating it as its own task.** `draft_cubit.dart:20-24` asserted "there
  is deliberately no `slot_date = p_occasion_date` constraint" and "the
  client is the only guard" — both now false as of Task 5's migration.
  The third confidently-wrong comment found this phase (after the
  `DropdownButtonFormField` resync claim and the "30_..." mis-citation,
  both from Phase 1a and this phase respectively) — the controller
  promoted this one for the same reason it promoted those: a comment
  stating a false invariant stops the next reader from ever checking it
  themselves. Cost if wrong: a one-paragraph doc edit in a file Task 6
  would not otherwise have opened.
- **Carry forward (not a ruling, restated for completeness): the
  `draft_cubit.dart:68` bare-code branch on `23514`** — see §6's headline
  entry above.

### Task 6 — §11.2, drop the recipient's read

- **A near-miss the implementer caught that the controller's own brief did
  not anticipate.** A plausible reading of the brief's "seed a staff
  profile" instruction — setting `is_staff = true` in `setUpAll` for the
  whole file — would have broken test 2's inactive-product exclusion,
  because `products_staff_write` is a **permissive** `for all` policy and
  Postgres ORs permissive policies together, so a staff caller would see
  the inactive product test 2 asserts is absent. The implementer scoped
  the promotion to test 7 alone specifically to avoid this interaction.
- **Ruling: fold the staff-demotion fix into Task 7 rather than leave it
  for the final review**, over the reviewer's own assessment that it was
  cheap and not required. The controller took it anyway because this
  phase had already paid twice for latent traps whose failure surfaces in
  the wrong file (the GoTrue landmine, the 23514 overload), and Task 7
  re-runs every suite from cold regardless, so the fix is exercised for
  free. Cost if wrong: one line in a teardown.
- **Environment trap surfaced during this task's review**, recorded here
  and generalized in §4 above: a post-restart `supabase test db` without a
  reset reported a false `292/FAIL` where reset-then-test showed the true
  `295/PASS`.
- Minor (deferred, not promoted): the staff promotion is safe only because
  test 7 is currently the last test in the file — nothing enforces that
  ordering, and a future test 8 appended after it would silently inherit
  `is_staff = true` and fail for a reason that looks nothing like the
  cause. Addressed by the Task 7 demotion above, which removes the
  precondition rather than merely documenting it.

### Task 7 — phase close

- **Ruling: the controller ran the cold verification itself rather than
  re-dispatching the whole task a third time.** Two implementer agents had
  already stalled mid-verification in this session (once on Task 6's
  review, once on Task 7 proper) — the verification step itself, a long
  sequence of commands with no judgement embedded in it, was the recurring
  failure mode. Running it directly removes that failure mode entirely;
  the part that genuinely needs judgement — this ledger — still went to a
  subagent, supplied with the numbers so it never had to run anything.
  Cost if wrong: the controller spent turns on shell commands instead of
  coordination.
- In the course of that verification the controller found and documented
  the third environment trap (§4.3) — Kong orphaned against a replaced
  edge-runtime container after `db reset`, masking a total Deno outage as
  "everything failed" and initially fooling the controller's own
  status-code-only probe.

---

## 8. Live carry-forward from Phase 1a, addressed by this phase

Phase 1a's own ledger (§6 there) named §11.2 — the recipient's
`amount_minor` exposure — as dormant until a recipient-facing surface
existed to read it. **That surface now exists** (the confirm endpoint), and
this phase's Task 6 closed the exposure directly: `gifts_select_participants`
no longer has a recipient branch at all. The recipient never reads
`public.gifts` through RLS in the first place — the confirm endpoint runs
entirely as `service_role` and the recipient never has a session — so this
was closed pre-emptively rather than reactively. When a genuine
recipient-facing in-app surface ships later ("a gift is coming for you"),
access must return through a narrow `security definer` function exposing
safe columns only, never by restoring the broad policy branch — recorded
in the spec (§6.4) as the only acceptable shape going forward.

The suppression-oracle carry-forward from M1 Phase 3 (re-verified in Phase
1a) is unrelated to this phase's work and unchanged: `grep -rn
suppress_person supabase/functions/` still returns only comments, no
caller exists, and the gap remains dormant rather than closed.

---

## Suite size at phase close

32 pgTAP files / 295 assertions · 18 Deno tests (`test.sh`) + 6 checks
(`test-gateway.sh`, manual) · 207 non-contract + 47 contract Flutter tests
(254 total) · `flutter analyze` clean · all cold from `supabase db reset`,
verified by the controller at HEAD `052799d`, 13 Sep 2026.

Per this task's own constraints: **this branch is not merged.** The
whole-branch review that must come before a merge decision, and the merge
decision itself, both belong to the human.
