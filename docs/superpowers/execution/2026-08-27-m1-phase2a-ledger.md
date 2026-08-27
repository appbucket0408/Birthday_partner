# SDD ledger — plan: docs/superpowers/plans/2026-08-27-m1-phase2a-app-backend-surfaces.md

Spec: docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md (read)
Worktree: .claude/worktrees/m1-phase2a-backend on branch worktree-m1-phase2a-backend
BASE at start: 81c04a9
Baseline verified in this worktree: Files=19, Tests=168, PASS

Created with the native EnterWorktree tool rather than `git worktree add`, per
the worktree skill's preference. Worth knowing: its default base ref is
`origin/<default-branch>` and this repo has NO remote — it nonetheless branched
correctly from local HEAD (81c04a9, all 18 migrations and 19 test files present).
Also worth knowing: a worktree-isolated session refuses shell commands it cannot
statically prove stay inside the worktree — no `cd`, no loops. Run plain
sequential commands.

## Pre-flight scan

### Cross-task pairs (shared file or interface)

| Tasks | Produced -> Consumed | Finding |
|---|---|---|
| T1 -> T5, T6, T7 | working local OTP -> a real user session for HTTP testing | clean; T1 seeds three test numbers and T5/T6/T7 each use a different one, so no test can consume another's user |
| T1 -> T2..T4 | config.toml only | clean; no schema overlap, and T1 asserts the suite is unchanged at 168 |
| T2 -> T2 | profiles.reminders_enabled -> the fan-out filter | clean; the same migration adds the column, its grant, and the filter, so no window exists where the column is present but unconsulted |
| T2 -> 17_reminders.test.sql | reminders_enabled defaults true -> existing fan-out assertions | clean; default true means every existing fixture keeps queueing, and T2's step 4 says so explicitly |
| T3 -> T5 | rpc_claim_person(uuid, text) -> claim_profile Edge Function | clean; T5 calls it with p_profile_id/p_phone, matching T3's signature exactly |
| T4 -> T6 | rpc_add_celebration(uuid,text,text,smallint,smallint,smallint) -> add_celebrations | clean; T6 passes all six named params |
| T4 -> T4 | private.add_celebration -> public.rpc_add_celebration | clean; wrapper is a pure pass-through with an identical parameter list |
| T5, T6, T7 -> allowlists | three new Edge Functions, no new client-callable DB functions | clean; every wrapper is service_role only, so neither standing allowlist moves |
| T5 -> T7 | claim_profile -> delete_account's cascade probe | clean; T7's step 3 calls claim_profile and add_celebrations to create something to cascade, both of which exist by then |
| T6 -> T7 | add_celebrations -> same | clean |

### Per-task self-consistency

| Task | Finding |
|---|---|
| T1 | clean; config-only, adds no pgTAP, and its own step 5 asserts the suite stays at 168 |
| T2 | clean; plan(4) matches 4 assertions (has_column, two enqueue counts, one lives_ok) |
| T3 | clean after the plan-time fix; plan(4) matches 4. The original draft called a volatile function inside a WHERE — the same shape that broke an assertion in Phase 1 — and was rewritten during plan self-review to call it in its own statement |
| T4 | clean; plan(6) matches 6 assertions |
| T5 | clean; no pgTAP, verification is curl. Reads the phone from the session, never the body |
| T6 | clean; no pgTAP, verification is curl including a suppressed contact |
| T7 | clean; no pgTAP, verification is a before/after cascade probe |

### Assertion arithmetic

168 -> 168 (T1, config only) -> 172 (T2, +4) -> 176 (T3, +4) -> 182 (T4, +6)
-> 182 (T5, T6, T7 add no pgTAP). Matches the plan's Definition of Done.

The scan surfaced no conflicts requiring a ruling before execution.

## Known hazard carried from the plan

`gifts.sender_profile_id` is ON DELETE RESTRICT, so Task 7's account deletion
succeeds today (M1 has no gifts) and will fail in M3 once a user has sent one.
Recorded in the plan and in the function's own comment; M3 must decide whether a
sender's gifts are reassigned, anonymised, or deletion refused. Not this plan's
problem to solve.

## Progress
Task 1: DONE at ed7016a, Files=19 Tests=168 PASS (unchanged, as required — config only). Controller verified OTP independently: /auth/v1/otp -> {"message_id":"test-otp"}, /auth/v1/verify -> access token with user.phone = "919999000001" (UNPREFIXED).
Task 1: PLAN DEFECT found by the implementer — my brief's two-line recipe was insufficient. GoTrue refuses EVERY phone request with phone_provider_disabled until an SMS provider is nominally enabled, even when test_otp covers every number in use. Fixed by enabling the already-scaffolded [auth.sms.twilio] block with unmistakably fake local values. Reviewer confirmed no less-invasive option exists inside config.toml.
Task 1: KEY FORMAT SETTLED (three later pieces of work depend on it): test_otp keys are UNPREFIXED (919999000001) while the app sends +-prefixed E.164; GoTrue strips the +. auth.users.phone is stored WITHOUT the +, so Task 5's claim_profile +-normalisation is load-bearing, not defensive.
Task 1: review — spec ✅, quality Approved, 0 critical, 1 important, 1 minor.
Task 1: fix round 1/5 dispatched (F1 restore a do-not-commit guardrail, F2 a reversibility pointer).
Task 1: fix round 1/5 complete (2 addressed, 0 open; commits ed7016a..fd4fa65). Controller verified the diff is comment-only (no non-comment line differs) and the suite is unchanged. Re-review: both ADDRESSED, placeholder values still unmistakably fake, no breakage.
Task 1: complete (commits 81c04a9..fd4fa65, review clean after 1 fix round)

Task 2: dispatched (sonnet), BASE fd4fa65, brief task-2-brief.md, report task-2-report.md. Adds profiles.reminders_enabled and makes the fan-out honour it. Carries the R14 column-grant trap and the requirement that create-or-replace on enqueue_reminders preserve Phase 1's blocks filter and Feb-29 handling.
Task 2: DONE at e768b7f, Files=20 Tests=172 PASS. Controller verified both traps: reminders_enabled is client-writable (grant list now ends with it), and the create-or-replace preserved Phase 1's blocks filter, Feb-29 branch and accumulator while adding only the join and the toggle. enqueue_reminders is still non-executable by authenticated.
Task 2: controller probed the direction of the toggle directly — both on -> 1 queued; SUBJECT's toggle off -> still 1 (a subject's preference must not suppress other people's reminders); RECIPIENT's toggle off -> 0. Correct scoping; backwards would have let one user's setting silently control others' notifications.
Task 2: review — spec ✅, quality Approved, 0 critical, 0 important, 2 minor. The reviewer diffed the replaced function line-by-line against 20260824000006 and confirmed the preserved logic is byte-for-byte unchanged.

Ruling: R1 (phase 2a) — a FACTUAL CORRECTION to something I have asserted repeatedly since Phase 1's R14 and written into this plan twice. I claimed a missing column grant fails SILENTLY (update affects zero rows, raises nothing). It does not. Verified directly: updating a non-granted column as authenticated raises ERROR: permission denied for table profiles, and it aborts the whole statement even when a granted column appears in the same SET list. A granted column updates 1 row normally. The belief was wrong, it is in the migration comment and the plan, and a future maintainer reasoning from it would design a test that checks rows-affected instead of catching an exception. Fixing the comment in the migration and the plan text. Cost if wrong: none - this is a correction toward measured behaviour.
Task 2: fix round 1/5 dispatched (F1 correct the false silent-failure premise, F2 assertion 4 proves no exception but never reads the value back).
Task 2: fix round 1/5 complete (2 addressed, 0 open; commits e768b7f..ed750b3). Re-review traced the non-vacuousness itself rather than trusting the claim: line 28 sets the row false, nothing between there and the update touches the column, so the read-back is a real proof. plan(4) still matches 4 assertions.
Task 2: minor (noted, accepted): replacing lives_ok(update) with a bare update means a genuine permission-denied regression now aborts the test transaction with a hard SQL error rather than a graceful pgTAP failure. Accepted tradeoff for a non-vacuous assertion.
Task 2: complete (commits fd4fa65..ed750b3, review clean after 1 fix round)
Controller commit d18a65d corrected the plan: removed the false silent-failure premise in two places and recorded Task 1's two execution findings (SMS provider must be nominally enabled; test_otp keys are unprefixed) so a re-run does not rediscover them.

Task 3: dispatched (sonnet), BASE d18a65d, brief task-3-brief.md, report task-3-report.md. Adds public.rpc_claim_person, the service_role door onboarding needs to link a signed-up user to their person row.
Task 3: DONE at 980fd92, Files=21 Tests=176 PASS. RED confirmed first. Controller verified the grant surface directly: auth=false anon=false svc=true, and the client-callable set is unchanged at exactly four names.
Task 3: review — spec ✅, quality Approved, 0 critical, 0 important, 1 minor. The reviewer read the pre-existing private.claim_person to confirm the wrapper is not transposed and that the upsert is genuine (insert ... on conflict (phone_e164_hash) do update), so idempotency is real rather than assumed.
Task 3: minor (deferred): the test's 'grant select on ids to authenticated' is dead — no assertion queries the temp table after the role switch. Came from my brief verbatim, harmless.
Task 3: complete (commits d18a65d..980fd92, review clean)

Task 4: dispatched (sonnet), BASE 980fd92, brief task-4-brief.md, report task-4-report.md. The create-on-select door: mints a person and a celebration edge together, honours suppression by returning null, and lets M0's guard trigger reject self-celebration.
Task 4: DONE_WITH_CONCERNS at b8b8d21, Files=22 Tests=182 PASS. Both allowlists verified live and unchanged: private = can_see_person,is_staff,my_person_id; public = my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token.

Ruling: R2 (phase 2a) — MY BRIEF WAS WRONG and the implementer was right to deviate. I claimed self-celebration would be rejected by M0's celebrations_guard trigger, so add_celebration need not check it. That trigger tests new.person_id = private.my_person_id(), which reads auth.uid() — and in a service_role context there is NO JWT session, so auth.uid() is NULL, my_person_id() is NULL, the comparison yields NULL rather than true, and THE GUARD NEVER FIRES. Verified directly: a raw self-edge insert with no session SUCCEEDS. The implementer added an explicit profile_id = p_celebrator check raising the same P0001 message, which I confirmed rejects self-celebration through add_celebration. Cost if wrong: none — the explicit check is strictly more protection, and it is the only protection available in a session-less path.

Task 4: CARRY FORWARD (load-bearing, wider than this task): every RLS policy and trigger in this schema that depends on auth.uid() is INERT under service_role. That is by design for RLS — service_role is meant to bypass it — but celebrations_guard is a business-rule trigger, not a policy, and it silently provides no protection on any service_role path. Tasks 5 and 6 introduce exactly such paths. Any future service_role RPC that inserts into public.celebrations must replicate the explicit self-check; the trigger will not do it. Worth a schema-level fix in a later phase (make the guard compare against the row's own celebrator rather than the session), but not this plan's scope.
Task 4: review (opus) — spec ✅, quality NEEDS WORK, 0 critical, 4 important, 3 minor.

Ruling: R3 (phase 2a) — IMPORTANT 1 ACCEPTED, reproduced by the controller. The explicit self-check the implementer added closes only the CLAIMED case. If a user has signed up but not yet claimed their person row (signup creates the profile; claiming is a separate onboarding call), their row has profile_id NULL, the predicate yields NULL, and a self-edge is inserted. claim_person later sets profile_id on that very row by phone-hash conflict, so the edge becomes a self-edge RETROACTIVELY and permanently — celebrations_guard is BEFORE INSERT only and nothing re-validates. Reproduced end to end: person row absent -> add_celebration with own number returns a person id -> 1 edge -> after claim_person, a self-edge exists. Consequences: the user appears in their own my_celebrates() list and the fan-out reminds them of their own birthday. Import-before-claim is a realistic ordering (skipped step, failed claim, re-import). Fix inside the function: also reject when the resolved person's phone hash equals the celebrator's own. Cost if wrong: a user who genuinely shares a number with themselves is refused, which is the intent.

Ruling: R4 (phase 2a) — IMPORTANTS 2, 3 and 4 ACCEPTED, all test-strength, all cheap. (2) rpc_add_celebration has ZERO coverage: six parameters, three same-typed smallint defaults, so a transposition of birth_month/birth_day would pass all 182 tests and ship a silently wrong birthday. (3) the suppression assertion proves only that null came back, not that no edge was created — that is the privacy-critical behaviour of the whole task and it is the one assertion not testing it. (4) idempotency uses lives_ok, so a regression returning null on the retry path would read to the app as 'suppressed, skip' and stay green.

Ruling: R5 (phase 2a) — MINOR 5 taken with the importants: the test comment still says M0's guard trigger raises P0001, which is exactly the disproven assumption. Left alone it would lead the next reader to delete the explicit check as redundant, re-opening R2 and R3. Minors 6 and 7 accepted as-is: suppression short-circuiting the self-check creates no edge either way, and the extra lookup keys on the primary key already in hand.
Task 4: fix round 1/5 dispatched (F1 unclaimed self-edge, F2 wrapper coverage, F3 suppression creates-nothing, F4 idempotency return value, F5 stale comment).
Task 4: fix round 1/5 at c5b5cbb, Files=22 Tests=184 PASS.

Ruling: R6 (phase 2a) — MY PROPOSED F1 FIX WAS WRONG, and I wrote a wrong justification for it. I told the implementer to compare the resolved person's phone hash against the celebrator's own hash, and explicitly reasoned that a NULL sub-select result 'is correct — there is then no own-hash to collide with'. That is precisely the unclaimed case the finding was about: add_celebration CANNOT know an unclaimed user's own phone number, because the phone lives in auth.users, not in profiles or people. The implementer reproduced the scenario against my SQL and it still produced a permanent self-edge. Its alternative — have claim_person delete any retroactive self-edge at claim time, since claim time is the first moment both the profile and the phone are known — is correct and is the only place the information exists. Verified: person row absent -> add_celebration with own number returns an id -> after claim_person, NO self-edge. Done via create-or-replace inside the NEW migration, so no existing migration was edited (confirmed: one file changed, 153 insertions).

Ruling: R7 (phase 2a) — the claim-time fix is UNTESTED and that must not stand. The implementer stayed inside my stated plan(8)/Tests=184 contract and flagged the gap rather than exceeding it, which was the right call on its part — but the mechanism that closes R3, the sharpest bug in this phase, currently has no assertion. A future edit removing the delete-at-claim passes all 184. Dispatching one more round for a single assertion. Cost if wrong: one assertion and a count bump.
Task 4: fix round 2/5 dispatched (F6 assert the claim-time self-edge cleanup).

Ruling R8: The claim-time delete is narrow and correct — it keys on
`celebrator_profile_id = p_profile_id AND person_id = v_id`, so it removes only
the claimer's own edge to the row they just claimed. Verified against the live
DB: two other users celebrating a number still have both edges after the number's
owner claims it. Cost if wrong: signing up would silently wipe the celebrations
other people had recorded for you — the worst possible onboarding bug.

Ruling R9: `private.claim_person`'s `create or replace` preserves its contract.
Byte-diffed against the original in 20260824000001: identical but for the six
inserted delete lines — return value, upsert-on-phone-hash, all five coalesce
merges, `security definer`, `set search_path=''`, and the revoke from
public/anon/authenticated all survive. Cost if wrong: a dropped revoke leaks a
private function to `authenticated`.

Ruling R10: Accepting two non-blocking residuals rather than reopening Task 4.
(a) The `phone_e164_hash = (select ... where profile_id = p_celebrator)` arm in
`add_celebration` is dead — `people.phone_e164_hash` and `people.profile_id` are
both UNIQUE, so if the hashes match, the first arm already matched. Harmless, but
its comment oversells it as covering the unclaimed case, which it does not — the
claim-time cleanup does. (b) F3's suppression assertion counts edges via a person
named 'Opted Out'; since `suppress_person` hard-deletes the row, a stronger form
would count by `celebrator_profile_id`. Both are cosmetic; neither changes behaviour.

Carry-forward (for the final whole-branch review): `private.enqueue_reminders`
(20260824000006_reminders.sql:69-99) joins celebrations to people with NO
self-exclusion. Today the only way to hold a self-edge is the transient window
between `add_celebration` and `claim_person`; if a cron tick lands inside it, the
user gets an outbox row reminding them of their own birthday, and the claim-time
delete removes the edge but not the already-enqueued row. Pre-existing from
Phase 1, not introduced here.

Carry-forward (standing): any future direct-insert path into `public.celebrations`
needs its OWN explicit self-celebration check. M0's `celebrations_guard` compares
against `private.my_person_id()`, which reads `auth.uid()`; under `service_role`
there is no session, so the comparison is NULL and the guard never fires.

Task 4: complete (b8b8d21..a0a28c8, 2 fix rounds, suite Files=22 Tests=185 PASS;
re-review verdict: all of F1-F6 addressed, no new breakage).

Ruling R11: Task 5's implementer died to an API rate limit after writing both
files and clearing Steps 1-2. Rather than re-dispatch, the controller ran the
remaining verifications directly and committed the implementer's unmodified code.
Justification: the code was already written verbatim from the brief and what
remained was running curl and psql, not judgment. The task review still runs
normally, so the quality gate is intact. Cost if wrong: a controller who verifies
their own dispatch is less independent than a fresh agent — mitigated by the fact
that the reviewer sees the diff, not my runs.

Ruling R12: Added a verification the brief did not ask for — signing in as one
number and sending a request body naming a DIFFERENT number. The attacker got
their own person row (109), not the victim's (108). The brief proved the phone
comes from the session by construction (the function reads no body); this proves
it by experiment. Cost if wrong: none, it is an extra assertion.

Task 5: complete (a0a28c8..58bed59, no fix rounds, suite Files=22 Tests=185 PASS;
review pending at time of writing).

Ruling R13 (SECURITY, the milestone's most serious finding so far): Task 5's
review found that `enable_confirmations = false` — set by Task 1, and the Supabase
default — makes GoTrue run with SMS_AUTOCONFIRM=true. Under that,
`PUT /auth/v1/user {"phone": ...}` rewrites `auth.users.phone` AND stamps
`phone_confirmed_at` with no OTP whatsoever. Since `claim_profile` trusts the
session phone, a signed-in user could point their session at ANY number and claim
its person row.

I reproduced it end to end rather than taking the reviewer's word: an attacker
signed in as +919999000001 with a real OTP, rewrote their phone to an unclaimed
victim's number, called claim_profile, and received the victim's person row (56)
together with its 2 inbound celebration edges. That is total account takeover of
anyone who has not signed up yet — precisely the population whose rows carry
orphan edges.

Fixed by `enable_confirmations = true` (commit 1c26c34). Re-ran the identical
attack: the victim's row stays unclaimed with both edges intact, and the attacker
gets their own empty row. Confirmed `GOTRUE_SMS_AUTOCONFIRM=false` in the
container, that the test_otp map still works, and that OTP signup/signin and
claim_profile's happy path are unaffected.

Note for whoever configures the hosted project: config.toml is NOT applied by
`supabase db push`. This setting must be set in the dashboard separately, or the
hole ships to production while local looks correct.

Cost if wrong: none — confirmations are strictly safer, and the only price is
that the OTP round trip is now mandatory, which is what the product wants anyway.

Ruling R14: Fixed three error-path defects the review raised in claim_profile
(commit dabf341) rather than parking them, since all three live in the file the
task created and each fix is small and independently verifiable.
(a) The renumbering collision (people_profile_id_key, 23505) returned a bare 500,
    which the app cannot distinguish from a transient fault — it would retry
    forever. Now 409. Verified the same request returns 500 before, 409 after.
(b) The E.164 normalisation was applied but never asserted. `private.phone_hash`
    is a raw HMAC with no normalisation of its own, so any deviation hashes
    differently, mints a NEW person row, and orphans the user's real edges with
    nothing failing at runtime. Now asserted.
(c) A null person_id could ride inside a 200. Unreachable today; guarded because
    the sibling upsert_person returns null for suppressed numbers.

Ruling R15: NOT fixing the underlying renumbering semantics in Phase 2a. Making
`claim_person` release a profile's prior link needs a product decision M1 has not
made — what happens to the old person row and to the edges of people who still
have the user's old number in their address book. M1 ships no change-number flow,
so the 409 is unreachable from the app today. Carried forward to M2.
Cost if wrong: a user who changes their number cannot re-claim; they get a clear
409 instead of a hang, and no data is corrupted.

Task 5: complete (a0a28c8..dabf341, 1 fix round, suite Files=22 Tests=185 PASS).

Ruling R16 (Task 6 review, CRITICAL — confirmed by my own repro): `add_celebrations`
performs no E.164 validation, and `private.phone_hash` is a bare HMAC with no
normalisation. Reproduced in psql against a claimed user:

  E164 self-import      -> blocked ('you cannot celebrate yourself')
  unprefixed self-import -> NOT BLOCKED
  spaced self-import     -> NOT BLOCKED
  edges owned by user: 2 | distinct people rows for the same human: 3

Two harms. (a) The self-celebration guard compares phone_e164_hash, so any
non-E.164 spelling of your own number slips past it — and claim_person's
retroactive cleanup misses it too, since that deletes by the E.164-hash person id.
The self-edge is permanent. (b) One human imported in two formats becomes two
person rows; only the E.164 one is ever claimed, so the other's inbound edges are
orphaned invisibly.

Ruling R17: Fixing this at the DATABASE layer (new migration 20260827000004),
not only in the Edge Function. Two reasons: pgTAP can protect a DB constraint and
cannot reach an Edge Function at all — this milestone has zero automated coverage
of any function — and validating in `private.upsert_person` / `claim_person` /
`add_celebration` covers every write path at once rather than just the HTTP one.
Deliberately NOT applying it to `resolve_contacts`: that is a lookup across a
user's entire address book, where a malformed entry must simply fail to match
rather than raise and kill the batch.
Cost if wrong: a stricter write path could reject a legitimate number format we
have not anticipated. Mitigated by the regex matching claim_profile's, which is
already live on the onboarding path.

Ruling R18: The implementer's stated reason for not giving self-celebration a
distinct status was factually wrong — they argued the only alternative to the
generic P0001 was fragile message matching. The repo already uses
`using errcode` in five places (gift_lifecycle, device_tokens, gifts) and
claim_profile already branches on `error.code`. Directing them to add
`using errcode = 'P0002'` and map it to a per-contact `status: "self"`. Importing
your own number is the most likely "failure" in a real import, and it currently
looks identical to a database outage.

Ruling R19: Also fixing in this round — `added` overcounted duplicates within a
batch (two entries, same phone: reported 2, DB held 1 edge); `skipped` conflated
suppressed-permanent with failed-transient so the app could not tell "everyone
opted out" from "the database is down"; unbounded display_name (a 1MB name was
accepted); and the size check running after the per-element walk.

Task 6 fix round 1 (04dad19): implementer closed all seven findings. I verified
independently — the bypass repro now blocks all three unnormalised forms, leaving
0 self-edges and 1 people row (was 2 and 3); resolve_contacts still tolerates junk
without raising; both allowlists clean; assert_e164 not callable by authenticated.

Ruling R20: The re-review caught that the I2 fix made things WORSE at the HTTP
layer. The implementer used `P0002`, which is PL/pgSQL's assigned no_data_found.
I measured PostgREST's mapping directly with a throwaway probe function:

  P0001 -> 400   P0002 -> 500   22023 -> 400   45001 -> 400

So moving from the generic P0001 to P0002 turned a routine "that number is you"
into an HTTP 500 — the database would look like an outage to every retry and
alerting layer, which is the precise confusion I2 existed to remove, displaced
one layer up. Switched to 45001: class 45 is unassigned by Postgres, so it can
never collide with a builtin, and PostgREST renders it 400.
Cost if wrong: none — an unassigned code is strictly safer than borrowing one.

Ruling R21: Reversed the implementer's deliberate contract deviation. They deduped
`results` as well as the RPC calls, so results.length was the unique-phone count
rather than contacts.length. Deduping the CALLS is right; collapsing the RESULTS
is not — `results` carries no input index, so the obvious Flutter implementation
zips it positionally against the picked-contacts list and would misattribute every
outcome after the first duplicate. Matching by phone is no fallback either, since
the duplicate makes phone non-unique in the input too. Now every input index gets
an entry; repeats echo the first verdict under status "duplicate", and
added + skipped + failed + duplicates == contacts.length.
Deciding this now, before Phase 2b exists, is the whole point — once a client
bakes in a shape, changing it is a migration.

Ruling R22: The re-review found one of the new assertions vacuous — "not forked"
matched on `profile_id = selfguard OR phone_e164_hash = phone_hash('+91...')`,
but a forked row carries a different hash AND a null profile_id, so it satisfied
neither arm and read 1 whether or not the guard worked. Rewrote it to count the
rows a fork actually leaves. Proved it discriminates by neutering assert_e164 on
the live database: test 10 fails, and passes again after restore.

Ruling R23: Made these three fixes myself rather than dispatching a second fix
round. Each was surgical, I had verified every underlying fact first-hand, and
two agents had already been lost to API rate limits this session. The final
whole-branch review still covers this code, so the independent gate is intact.

Verified the new contract end to end with one batch exercising every status:
added / duplicate (echoing the first person_id) / suppressed / invalid_phone /
self / invalid_name / added-with-trimmed-name. 2+1+3+1 = 7 = contacts.length,
results.length = 7, and the padded name landed in the DB trimmed.

Task 6: complete (dabf341..e86cb4c, 2 fix rounds, suite Files=23 Tests=197 PASS).

Ruling R24: Directed the Task 7 implementer to consider adding pgTAP for the
cascade, and they agreed and added 23_delete_account.test.sql (plan(16)). The
brief proved the cascade with a before/after shell transcript, which nothing
re-checks once the terminal scrolls; the cascade is pure FK behaviour, which is
exactly what pgTAP CAN pin, unlike the HTTP layer. Suite 197 -> 213.

I verified the new file is not decorative — this milestone has already produced
two assertions that passed regardless of the code. Flipped people.profile_id's
FK from ON DELETE SET NULL to ON DELETE CASCADE on the live database: tests 13
("the deleter's own person row survives") and 15 ("the bystander's edge to that
person survives") both fail, and pass again after restore. The two assertions
carrying the task's whole guarantee are real.

Ruling R25 (PRIVACY, and a product decision I made rather than deferred): Task 7's
review found that deletion left the deleted user's OWN name and birthday behind.
Verified myself:

  BEFORE: people row: name=Self Entered Name month=4 day=15 year=1990
  AFTER:  people row: name=Self Entered Name month=4 day=15 year=1990 | unclaimed

The Edge Function's comment justified keeping the row because "it was built from
other people's address books" — true before a claim, false after one, because
`claim_person` overwrites people.display_name with the PROFILE's display_name and
copies the birth columns across, and `sync_person_from_profile` re-syncs on every
edit. The surviving name was the user's own, not the address-book one.

Compounding it: `private.enqueue_reminders` gates only on
`p.birth_month is not null` and never checks whether the person is still claimed.
So a user who asked to be erased kept generating birthday reminders to strangers,
under their real name and real birth date, indefinitely.

Ruled: "delete my account" must mean the app stops knowing your birthday. Keeping
the EDGE is right — other people's lists must not break — but keeping the name and
birth date is not. Fixed with a `before delete on public.profiles` trigger
(migration 20260827000005) that scrubs display_name to 'Deleted user', nulls the
three birth columns, deletes that person's addresses and queued outbox rows, and
preserves the row id and phone_e164_hash so every inbound edge survives.

Precedent that this tradeoff is acceptable in this codebase: `private.suppress_person`
already deletes the people row outright and lets celebrations cascade, so
"edges survive at any cost" was never an absolute.

Cost if wrong: a celebrator sees 'Deleted user' where a name used to be. That is
the correct thing to show, and it is reversible by changing one literal.
FLAGGED TO THE USER as a product decision, with an offer to reverse it.

Ruling R26: Also recorded, not fixed — `address_access_log.staff_profile_id` is a
SECOND `on delete restrict` FK that the brief did not document (it presented
gifts as the only one). It is worse than gifts: that table is deliberately
immutable ("an audit trail its own subject can edit is not an audit trail"), so
the reassign/anonymise escapes available for gifts are all closed for it. A staff
member who opens the ops console once could never be deleted. Inert today because
it requires a gift. Now in the KNOWN LIMIT comment for M3.

Verified after the fix: the residue repro shows name='Deleted user', all birth
columns null, bystander's edge still present. Implementer proved the new
no-reminder assertion discriminates by dropping the trigger live — tests 17/20/21
fail, with enqueue_reminders inserting 2 real outbox rows (the actual harm), and
all pass again after restore.

Implementer's one correction, accepted: F3's premise that notification_outbox
denormalises subject_name is false — it joins people live at drain time. The fix
(deleting already-queued subject-side rows) stands on its own merits regardless.

Task 7: complete (e86cb4c..39d6be0, 1 fix round, suite Files=24 Tests=224 PASS).

ALL SEVEN TASKS COMPLETE. Proceeding to the final whole-branch review.

## Final whole-branch review

Returned NOT READY with three blocking findings. I reproduced all three against
the live database before acting on any of them.

Ruling R27 (B1, inherited from M0): `celebrations_insert_own`'s `with check`
constrained `celebrator_profile_id` but left `person_id` free, and
`celebrations_guard` is BEFORE INSERT only so UPDATE bypassed it entirely. Since
`private.can_see_person` grants sight of a people row to anyone holding an edge
to it, and `people.id` is a sequential bigint, ANY authenticated user could
enumerate every user's real name and full date of birth:

  INSERT aimed at victim person 94: SUCCEEDED
  UPDATE redirecting an edge to victim: SUCCEEDED
  LEAKED -> VictimThree Real dob=11/7/1991

Fixed despite being M0's code and outside this phase's scope, because this is the
last gate before a Flutter client ships on top of it and the alternative is
knowingly merging a schema-wide PII leak. Now: no INSERT and no table-level
UPDATE for authenticated, only `update (nickname)`; guard wired to BEFORE UPDATE
as well; edges minted solely by `rpc_add_celebration`, which takes a PHONE NUMBER
rather than a caller-chosen person id.
Cost if wrong: a client path that inserted directly would break. Verified none
exists — the only two authenticated inserts in the whole suite are `throws_ok`
assertions.

PROCESS NOTE, worth more than the finding: my first B1 repro came back clean and
I nearly reported the finding as unreproducible. The test was wrong — it used a
person_id from an already-rolled-back transaction, so RLS rejected it for the
wrong reason. A test that fails to reproduce is not evidence of absence until the
test itself has been checked.

Ruling R28 (B2/B3): my own R25 fix was incomplete. Preserving `phone_e164_hash`
left the scrubbed row findable, so `claim_person`'s `on conflict` handed it to
the next owner of a recycled number — inbound edges and wish wall included — and
`upsert_person` refilled the nulled birthday on any re-import, queueing real
reminders about a deleted user. Both reproduced:

  alice person id: 76 -> bob claimed person id: 76 (same row)
  bob inherited inbound edges: 1, wishes: 1
  after re-import: month=4 day=15 | outbox rows about the deleted user: 1

Fixed by rotating the hash to two dash-stripped gen_random_uuid()s (64 lowercase
hex, matching the column's format constraint, from the platform CSPRNG rather
than random(), since this is a privacy control). Also corrected two false
comments in 20260827000005 — it listed phone_e164_hash among "what must survive"
and claimed nulling birth_month stopped future reminders, which B3 disproved.
Accepted trade-off, now written into the migration: a bystander's edge is
permanently stranded on a "Deleted user" row, and re-importing that number mints
a second row beside it. The alternative is handing a stranger's social graph to
whoever next gets the recycled number.

Ruling R29: Extended `docs/db.md` with six rules this phase paid for — the
service_role trigger inertness, the assert_e164 requirement, SQLSTATE as a public
API decision, the enable_confirmations requirement plus its hosted-dashboard
caveat, the delete-time hash rotation, and the celebrations write lockdown. The
final review flagged that db.md is the repo's designated carrier of hard-won
rules and had not been touched; leaving these only in a ledger nobody reads
during normal work would waste them.

Verified after the fixes: B1 both operations blocked (42501), 0 rows leaked;
B2 Bob gets a NEW person row, 0 inherited edges and 0 inherited wishes;
B3 anchored on the stranded row — not findable by its original phone, birthday
still NULL after re-import, 0 outbox rows about the deleted user.

Implementer's honest self-report, accepted: three assertions in file 25 pass with
AND without the rotation. They are shape guards, not proof, and are annotated as
such in the file so nobody mistakes them for the B2/B3 evidence. Reporting this
rather than hiding it is the behaviour I want.

Suite: Files=26, Tests=254, PASS from cold. Both allowlists clean. Lint findings
confined to extensions.*.

## Carried into Phase 2b (not blocking, must not be lost)

1. ZERO automated coverage of any Edge Function — pgTAP cannot reach them, and
   there is no Deno test, no CI, no lint. Everything below rests on a shell
   transcript in a report file: session-phone binding, the `+`-prefix
   normalisation, the 23505->409 mapping, every 401 gate, `add_celebrations`'
   whole status vocabulary and its `added+skipped+failed+duplicates ==
   contacts.length` contract, MAX_BATCH/MAX_NAME_LENGTH, delete_account acting on
   the session user, drain_reminders' x-drain-secret gate, and the
   never-log-error.details rule. The status vocabulary is the one Phase 2b will
   bake in and the most expensive to get wrong.
2. `enable_confirmations = true` is guarded by nothing — no test, no lint, no CI,
   and `supabase init`/CLI upgrades rewrite config.toml. It is the fix for total
   account takeover.
3. No `[functions]` block in config.toml, so all five run at `verify_jwt = true`.
   `drain_reminders` authenticates by `x-drain-secret` alone, so the planned
   pg_net cron call will 401 before reaching the handler. Decide before scheduling.
4. Spec 7.3 requires inline edit of an existing contact's birthday. There is no
   surface for it: `people` has no UPDATE policy and `upsert_person` only fills
   NULLs, and only when profile_id is null. Phase 2b needs a new RPC.
5. `add_celebrations` makes up to 500 sequential awaited RPCs (~6.2s measured for
   500 on loopback, warm). Client must chunk. Also `upsert_person`'s insert is not
   `on conflict`, so two users importing the same new number concurrently produce
   a 23505 that surfaces as generic "failed".
6. `display_name` is unbounded at the DB layer — the 128-char limit and the trim
   live only in the Edge Function, exactly the arrangement R17 argued against.
7. `guard_celebration` on UPDATE now rejects a nickname edit if the target has
   since blocked you. Intended, but the client needs an error branch on what is
   otherwise a cosmetic path.
8. `suppress_person` hard-deletes the people row while account deletion strands a
   scrubbed one. The two erasure paths now differ in kind; the asymmetry is
   deliberate but undocumented in product terms.
9. `address_access_log.staff_profile_id` is a second ON DELETE RESTRICT FK, worse
   than the gifts one because that table is deliberately immutable, so the
   reassign/anonymise escapes are closed. A staff member who opens the ops console
   once can never be deleted. Inert until M3.
10. Dead code: the `phone_e164_hash = (select ... where profile_id = p_celebrator)`
    arm in `add_celebration` is unreachable (both columns UNIQUE), and the comment
    above it still claims it is the one that bites.
11. No OPTIONS/CORS handling in any function — fine for Flutter mobile, breaks a
    Flutter web build.

PHASE 2a COMPLETE.
