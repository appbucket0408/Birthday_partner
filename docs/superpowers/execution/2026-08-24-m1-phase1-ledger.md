# SDD ledger — plan: docs/superpowers/plans/2026-08-24-m1-phase1-data-and-backend.md

Spec: docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md (read)
Worktree: .claude/worktrees/m0-schema-and-rls on branch worktree-m0-schema-and-rls
BASE at start: d1d9704

## Pre-flight scan

### Cross-task pairs (shared file or interface)

| Tasks | Produced -> Consumed | Finding |
|---|---|---|
| T1 -> T7 | 11_rls_coverage private-RLS assertion -> private.notification_outbox | clean; T7 enables RLS on the new table |
| T2 -> T7 | people.birth_month/birth_day -> enqueue_reminders matching | clean; smallint on both sides |
| T2 -> T8 | people.birth_month/birth_day -> resolve_contacts return columns | clean |
| T2 -> T3..T8 | tests.create_person 5-arg form, claim_person unchanged -> fixtures | clean; every later task uses the new form, and claim_person's signature is deliberately preserved |
| T2 -> 02/03/08/10 tests | new column set -> M0 fixtures | clean; all call sites enumerated in T2's steps |
| T3 -> T5 | celebrations_select_incoming -> my_birthday_stats | clean; stats reads wishes only, not edges |
| T4 -> T5 | wishes author-visibility -> wishes_sent count | clean; T4 precedes T5, so the count is correct by the time it is asserted |
| T6 -> T7 | device_tokens -> next_reminder_batch join | clean; T7 asserts empty-then-nonempty around a token insert |
| T7 -> T9 | enqueue_reminders() zero-arg default -> cron command | clean |
| T7 -> T11 | next_reminder_batch / mark_* -> drain Edge Function | CONFLICT — see R2 |
| T8 -> T10 | private.resolve_contacts(text[]) -> resolve_contacts Edge Function | CONFLICT — see R2 |
| T5 -> all | public.my_birthday_stats granted to authenticated | clean, but exposed a gap — see R3 |

### Per-task self-consistency

| Task | Finding |
|---|---|
| T1 | clean; plan(2)->plan(3) matches the one added assertion |
| T2 | clean; plan(13) matches 13 assertions after the half-date guard was added during plan self-review |
| T3 | clean; plan(4) matches 4 |
| T4 | clean; plan(3) matches 3 |
| T5 | clean; plan(4) matches 4 |
| T6 | clean; plan(5) matches 5 |
| T7 | clean; plan(8) matches 8, raised to plan(9) by T9 |
| T8 | clean; plan(5) matches 5 |
| T9 | clean; modifies T7's test file only |
| T10 | DEFECT — calls .schema("private").rpc(); see R2 |
| T11 | DEFECT — calls .schema("private").rpc(); see R2 |

## Rulings

Ruling: R1 — execute Phase 1 on the existing worktree and branch
(worktree-m0-schema-and-rls) rather than creating a new one. M1 Phase 1 depends
on M0's unmerged migrations, the M1 spec and plan commits already live on this
branch, and a second worktree would drive the SAME Docker containers anyway
because project_id is committed in config.toml. Cost if wrong: the branch name
understates its contents; a future merge brings M0 and M1 Phase 1 across
together, which is the likely intent regardless.

Ruling: R2 — LOAD-BEARING. Tasks 10 and 11 as written cannot work. Both call
`admin.schema("private").rpc(...)`, but PostgREST exposes only the schemas in
config.toml's `[api] schemas = ["public", "graphql_public"]`. Verified against
the running stack: a POST with `Content-Profile: private` returns
PGRST106 "Invalid schema: private. Only the following schemas are exposed:
public, graphql_public".
Rejected fix: adding `private` to `[api] schemas`. That would destroy the
property the spec explicitly banks on — that the private schema is unreachable
through the API by construction, not merely by grant.
Chosen fix: each private function an Edge Function needs gets a thin `public`
wrapper, `security definer`, revoked from public/anon/authenticated and granted
to `service_role` ONLY. Verified end to end: the wrapper returns its value for
the secret key and 42501 "permission denied for function" for the publishable
key. Tasks 7 and 8 create the wrappers; Tasks 10 and 11 call them without a
schema qualifier. Cost if wrong: four extra small functions to maintain, and a
schema-cache reload is required after the migration (M0's pgrst_ddl_watch event
trigger already does this automatically).

Ruling: R3 — add a `public`-schema function allowlist assertion mirroring M0's
R13 private one. R2's wrappers live in `public`, where a new function is
PUBLIC-executable by default exactly as in `private`, and the existing R13
assertion does not look there — so a forgotten revoke on a service_role wrapper
would hand every signed-in user a server-side entry point with nothing to catch
it. Current state verified: `ops_get_delivery_address` is the only public
function authenticated may execute; after Task 5 the expected set is
'my_birthday_stats,ops_get_delivery_address'. Cost if wrong: one more allowlist
string to edit deliberately when a genuinely client-callable function is added.

## Progress

Plan amended for R2 and R3 before execution (commit 0e790af). Assertion target
moves 141 -> 142. Progression the tasks must hit:
96 -> 98 (T1) -> 112 (T2) -> 116 (T3) -> 119 (T4) -> 123 (T5) -> 128 (T6)
-> 136 (T7) -> 141 (T8) -> 142 (T9).

Environment verified before Task 1: colima up, supabase stack healthy,
`supabase test db` = Files=12, Tests=96, PASS from a cold reset.

Task 1: dispatched (haiku), BASE 0e790af, brief task-1-brief.md,
report task-1-report.md. Task text carries the complete SQL, so this is
transcription plus two test runs and a throwaway probe.
Task 1: DONE at 00534b9, Files=12 Tests=98 PASS. Real RED observed on the
  private-RLS assertion ("Unexpected records: (probe_no_rls)"). Controller
  verified independently: no stray probe objects remain, plan(4), allowlist
  string is 'ops_get_delivery_address', suite PASS.
Task 1: review clean — spec compliant, 0 critical, 0 important, 2 minor.
Task 1: minor (deferred): the private-table RLS query duplicates the public one,
  differing only in the schema literal; could collapse to
  `nspname = any(array['public','private'])`. Brief mandated the SQL verbatim,
  so not an implementer defect. Cleanup candidate for a later task.
Task 1: minor (deferred): the public-function query does not filter p.prokind,
  so a future aggregate or procedure in public with stray EXECUTE-to-PUBLIC
  would also be flagged. Not a bug today — no such objects exist — but worth
  knowing if public ever gains procedures.
Task 1: controller resolved the reviewer's one ⚠️ (what do R3/R13 refer to):
  they are ruling IDs, R13 from the M0 ledger and R3 from this plan's, and both
  are written up in docs/db.md. Not a gap.
Task 1: complete (commits 0e790af..00534b9, review clean)

Task 2: dispatched (sonnet), BASE 00534b9, brief task-2-brief.md,
report task-2-report.md. Largest task in the phase: one new migration plus
seed.sql and four test-file edits, and the only task that rewrites working M0
code. Carried the two verified traps (trigger dependency, R14 grant list) and
the instruction not to touch 07_gifts/09_wishes.
Task 2: DONE at a15e8b6, Files=13 Tests=112 PASS. Controller verified
  independently: trigger recreated as `update of display_name, birth_month,
  birth_day, birth_year`; profiles column grants are exactly (handle,
  display_name, city, avatar_url, birth_month, birth_day, birth_year) with
  is_staff correctly absent; both old columns gone; no stale
  upsert_person(text,text,date) overload; leap predicate correct by hand
  (1900 common, 2000 leap, 2024 leap, 2100 common); half-date, Apr 31 and
  Feb 29+2001 each rejected by the right named constraint, Feb 29+2000 accepted.
Task 2: review (opus) — spec ✅, quality Approved, 0 critical, 2 important,
  4 minor. Both importants are PLAN-MANDATED: the brief specified the SQL, so
  they are mine to rule on, not implementer defects.

Ruling: R4 — FIX the weakened year invariant (review important #1). The new
`*_birth_year_sane` allows a FUTURE date of birth: month 12, day 31, year 2026
passes on 2026-08-24, where M0's `birthday <= current_date` forbade it. The spec
does literally say "between 1900 and the current year", but that wording was
shorthand for "a date of birth is in the past", not a deliberate weakening —
the spec calls the column a date of birth throughout, and a future DOB is
nonsense data that breaks age display. Fix on both tables by adding a same-year
month/day bound.
Deliberately NOT using `make_date(birth_year, birth_month, birth_day) <=
current_date`, which the reviewer suggested: make_date RAISES on an invalid date
such as (2001,2,29), CHECK evaluation order is not guaranteed, and the existing
"Feb 29 + non-leap is rejected with 23514" assertion could start failing with a
datetime error instead. A row comparison on (birth_month, birth_day) has no such
hazard. Cost if wrong: a same-year birthday entered on the day itself is
accepted, one entered for tomorrow is not — which is the intended behaviour.
Keeping `current_date` in the CHECK is consistent with M0's existing pattern;
the reviewer's note about non-immutability is real but pre-existing and out of
scope here.

Ruling: R5 — FIX the missing propagation assertion (review important #2). This
task widened the sync trigger's `update of` list from one column to three, and
the reviewer's observation is exact: removing `birth_day` from that list would
leave the whole suite green while public.people silently went stale. Coverage
for a silent-staleness path is worth one assertion. It goes in
12_birthday_model.test.sql, not 02_profiles.test.sql, because it needs a claimed
person row and 02_profiles' user has none.

Ruling: R6 — also fix minor #4, despite minors normally staying out of the loop.
`create or replace function tests.create_person` with a new argument list leaves
the old `(text, text, date)` overload in place, so re-running seed.sql against
an already-seeded database makes the two-argument calls in 03_people_graph
ambiguous (42725). That is a workflow the controller itself used during M0 to
avoid a full reset, so the hazard is real rather than theoretical, and the fix
is one line beside changes already being made. Cost if wrong: one redundant
`drop function if exists`.

Ruling: R7 — also fold in minor #5's substance as two real assertions rather
than deferring it. The leap predicate's century rules (2000 accepted because
divisible by 400, 1900 rejected because divisible by 100 but not 400) are the
interesting half and are currently unasserted; the controller and the reviewer
each verified them by hand, and turning that manual check into a permanent guard
costs two assertions. NOT taking the reviewer's other half of #5 (that
`throws_ok(..., null, ...)` pins only the SQLSTATE) — that pattern is used
throughout M0 and changing it here alone would be inconsistent.

Task 2: minor (deferred): #3 — upsert_person's readable guard checks only
  month/day pairing, so (null, null, 1995) still dies on the
  *_birth_year_needs_parts constraint message rather than the friendly one. No
  bad data results; only the diagnostic is worse than intended.
Task 2: minor (deferred): #6 — *_birth_day_valid (1..31) is subsumed by
  *_birth_day_in_month and is dead validation cost on every write; and
  birth_year >= 1900 is inclusive where M0 used > date '1900-01-01'.
Task 2: minor (deferred): reviewer's note that `current_date` in a CHECK is
  non-immutable so the constraint's meaning drifts and dump/restore is not
  guaranteed to reload. Pre-existing M0 pattern, now on two tables; worth a
  dedicated decision before any hosted deploy.
Task 2: fix round 1/5 dispatched (F1=R4 year invariant both tables, F2=R5
  propagation assertion, F3=R6 drop stale seed overload, F4=R7 two century
  assertions). 12_birthday_model plan(13) -> plan(16); suite 112 -> 115.
Controller: plan renumbered for the fix round (112 -> 115) and briefs 3-9
  re-extracted so they carry the corrected expectations. New progression:
  96 -> 98 (T1) -> 115 (T2) -> 119 (T3) -> 122 (T4) -> 126 (T5) -> 131 (T6)
  -> 139 (T7) -> 144 (T8) -> 145 (T9).
Task 2: fix round 1/5 complete (4 addressed, 0 open; commits a15e8b6..6c8141f).
  Re-review: all four ADDRESSED, no new breakage, downstream renumbering
  internally consistent (+3 everywhere). Controller verified independently:
  future DOB rejected on both tables by the correctly-named constraints; past,
  year-less and same-year-past rows still accepted.
  Note: the controller's plan-renumbering edit was swept into 6c8141f because it
  sat in the working tree while the implementer committed. Content is correct and
  controller-authored; the lesson is not to edit tracked files while a subagent
  is live.

Ruling: R8 — take one more round on F2, even though the re-review passed it.
The re-reviewer filed this as an out-of-scope observation, but it goes to whether
F2 achieved its purpose at all: the new assertion updates birth_month, birth_day
and birth_year in a SINGLE statement, and Postgres fires an `update of a, b, c`
trigger when ANY listed column is touched, with NEW carrying every column's
value. So if birth_day were dropped from the trigger's column list, the other
two would still fire it, NEW.birth_day would still be correct, and the assertion
would still pass — which is exactly the silent-staleness scenario R5 existed to
catch. The guard as written does not guard.
Fix: make it a two-step update whose SECOND statement changes ONLY birth_day,
then assert '7-5-1990'. That detects a missing birth_day in the column list, and
still proves month and year propagated from the first update. Chosen over adding
a second assertion so the plan count stays at 16 and no downstream renumbering
is needed. Cost if wrong: none; it is strictly more detection for the same
assertion count.
Task 2: fix round 2/5 dispatched (F5=R8 strengthen the propagation assertion).
Task 2: fix round 2/5 complete (1 addressed, 0 open; commits 6c8141f..66298ad).
  Real RED demonstrated by narrowing the trigger to exclude birth_day:
  "have: 7-4-1990 / want: 7-5-1990", then green after restore. The guard now
  actually detects the failure mode R5 was written for.
  Re-review: F5 ADDRESSED, no new breakage, plan count still 16, no other
  assertion weakened.
Task 2: complete (commits 00534b9..66298ad, review clean after 2 fix rounds)

Task 3: dispatched (sonnet), BASE 66298ad, brief task-3-brief.md,
report task-3-report.md. RLS policy work — this project's defects concentrate
here, so mid-tier rather than cheapest despite the brief carrying complete SQL.
Task 3: DONE at bc258ee, Files=14 Tests=119 PASS. Controller verified
  independently: both SELECT policies coexist (Postgres ORs permissive policies),
  migration contains zero grant statements, 11_rls_coverage untouched. Also
  probed three edge cases directly, all correct:
    - a user with NO claimed person row (my_person_id() NULL) sees 0 edges;
    - viewer blocks their fan -> fan excluded from the list;
    - fan blocks the viewer -> viewer STILL sees the fan (the intended
      asymmetry; the insert-side direction is already handled by M0's
      guard_celebration trigger).
Task 3: review clean — spec ✅, 0 critical, 0 important, 1 minor.
Task 3: minor (deferred): no assertion covers the viewer-with-no-person-row
  case. Controller verified it by hand (0 edges, no leak) and the reviewer
  confirmed it sound by inspection: celebrations.person_id is NOT NULL, so
  `person_id = NULL` is never true. Deferring rather than adding an assertion —
  it rests on fundamental SQL NULL semantics rather than app logic, and would
  cost a full downstream renumbering pass. Would only regress if someone
  rewrote the predicate with coalesce or `is not distinct from`.
Task 3: complete (commits 66298ad..bc258ee, review clean)

Task 4: dispatched (sonnet), BASE bc258ee, brief task-4-brief.md,
report task-4-report.md. Replaces an RLS policy so an author keeps sight of
their own wishes after the graph changes — the "track record that forgets" bug.
Task 4: DONE at 126aaad, Files=15 Tests=122 PASS. RED was exactly as the brief
  predicted — assertions 1 and 2 green, only assertion 3 failed (have:0 want:1),
  which is what makes the failure unambiguously about authorship.
  Controller verified independently: live predicate is
  ((author_profile_id = (SELECT auth.uid())) OR (SELECT
  private.can_see_person(wishes.subject_person_id))); the recreated policy kept
  `to authenticated` and stayed permissive; anon reads 0 wishes; zero grants;
  09_wishes and 11_rls_coverage both zero-diff.
Task 4: review clean — spec ✅, 0 critical, 0 important, 2 minor.
Task 4: minor (deferred): assertion 1 would also pass under the old buggy policy
  (both branches are true while the edge exists). By design — it establishes
  fixture soundness — but worth knowing when reading the test in isolation.
Task 4: minor (deferred): the diff is byte-for-byte the brief's SQL, so this
  review validated the brief's reasoning rather than implementer judgment. The
  reviewer re-derived the fixture logic against the real people/celebrations
  schema independently, which is the mitigation.
Task 4: complete (commits bc258ee..126aaad, review clean)

Environment note: `supabase db reset` has now returned a transient
`Error status 502` on its "Restarting containers" step twice (Tasks 2 and 4).
Both times the stack was healthy afterwards and the subsequent full suite was
green. Treat it as noise, but verify with `supabase status` plus a psql probe
before trusting a run that follows one.

Task 5: dispatched (sonnet), BASE 126aaad, brief task-5-brief.md,
report task-5-report.md. First task to add a client-callable public function, so
it is also the first to widen Task 1's public allowlist — carried that
explicitly.
Task 5: DONE at 9ee10a6, Files=16 Tests=126 PASS. Controller verified: function
  is security INVOKER (prosecdef=false) with search_path="", the allowlist was
  widened (not loosened) to exactly 'my_birthday_stats,ops_get_delivery_address'
  and matches live privileges, and an unrelated third user gets 0 stat rows.
Task 5: CONTROLLER-FOUND DEFECT (important), before the review returned.
  my_birthday_stats() returns SPURIOUS all-zero year rows. The `mine` CTE selects
  every wish the caller can READ — and wishes_select_visible also exposes wishes
  authored by other people about subjects the caller can see — then groups by
  occasion_year with no filter on the caller's own involvement. Reproduced: a
  viewer who authored nothing and received nothing, but who celebrates a person
  someone else wished in 2025, gets a row "year=2025 sent=0 recv=0 celebrated=0".
  The profile's track record would list years the user had nothing to do with.
  The three counts themselves are correct (each is filtered to the caller); only
  the row SET is wrong.
  Fix: filter the CTE to the caller's own rows rather than filtering only inside
  the aggregates, which also shrinks the scan. Requires reordering so `me` is
  declared before `mine`.
Task 5: review — spec ✅, quality NEEDS WORK, 0 critical, 1 important, 2 minor.
  The reviewer independently found the SAME phantom-year defect the controller
  had already reproduced, and confirmed the three counts themselves are not
  numerically inflated (each FILTER pins author or subject), so only the row set
  is wrong. Convergence from two directions on an unprompted finding.
  Reviewer's two minors are real: (a) the fixture never wishes the same subject
  twice in a year, so a regression dropping DISTINCT from birthdays_celebrated
  would still pass; (b) assertion 4 checks only the ROW COUNT of the grouping,
  so it cannot tell a correct second-year row from a wrong row with the right
  count — which the phantom rows make more than theoretical.

Ruling: R9 — fix the migration IN PLACE rather than adding a corrective
migration, overruling the reviewer's explicit recommendation to "file a
follow-up migration ... rather than reworking Task 5". Same reasoning as M0's
R11: nothing is deployed, every database that applies this file is rebuilt from
scratch by `supabase db reset`, and the plan's append-only rule exists to protect
migrations that have been released — not one committed twenty minutes ago in the
task still under review. Shipping a function known to emit phantom rows plus a
second migration to correct it would leave two places to read for one behaviour.
Cost if wrong: if this branch were ever partially applied to a long-lived
database, that database would keep the phantom-row version; recovery is the
follow-up migration the reviewer suggested.

Ruling: R10 — fold BOTH minors into the same round without changing the
assertion count, by restructuring assertion 4 instead of adding assertions.
A 'cake' wish to an already-wished subject in the same year is inserted before
the final assertion (the partial unique index permits it, unlike a second
'message'), and assertion 4 becomes a full row-set check asserting
"<year>:3/1/2 <nextyear>:1/0/1". That single assertion then pins the grouping,
the per-row values, AND distinct-vs-total for birthdays_celebrated — because
wishes_sent becomes 3 while birthdays_celebrated stays 2, which a regression
dropping DISTINCT could not satisfy. plan(4) is unchanged, so no downstream
renumbering. Cost if wrong: one assertion carries three concerns, so its failure
message is less specific about which broke.
Task 5: fix round 1/5 dispatched (F1=R9 CTE relevance filter, F2/F3=R10
restructured assertion 4 with a cake row).
Task 5: fix round 1/5 complete (3 addressed, 0 open; commits 9ee10a6..1f50142).
  Controller verified independently after the fix: the uninvolved viewer now gets
  0 stat rows; a real author still gets 1 row with sent=1; and the branch most at
  risk from the new CTE filter — a RECIPIENT who authored nothing — correctly
  gets rows=1 sent=0 recv=1, so the subject side was not dropped.
  Re-review: all three ADDRESSED, no new breakage, plan(4) intact, assertions
  1-3 untouched, and it confirmed the new assertion cannot pass vacuously
  (string_agg over no rows yields NULL, which pgTAP's is() fails against a
  non-null expected string).
Task 5: minor (deferred): the `me` CTE's two values are re-selected via scalar
  subquery at each of four use sites rather than joined once. Style and a
  micro-perf nit, pre-existing in the original shape; not correctness.
Task 5: complete (commits 126aaad..1f50142, review clean after 1 fix round)

Task 6: dispatched (haiku), BASE 1f50142, brief task-6-brief.md,
report task-6-report.md. One table, one owner-only policy, one test file, with
the complete SQL in the brief — the cheapest tier is the right fit for
transcription plus a reset. Escalate to sonnet if it stumbles.
Task 6: DONE at 6f9e51a, Files=17 Tests=131 PASS (haiku handled it cleanly, no
  escalation needed). Controller verified: relrowsecurity=true, single policy
  device_tokens_all_own cmd=* roles=authenticated, device_tokens_profile_id_idx
  present on the FK column, and a second user reads 0 of the first user's tokens.
Task 6: CONTROLLER-FOUND ISSUE (design, not implementer) — a device token cannot
  move between accounts. Probed directly:
    - user A registers token T (ok);
    - user B on the SAME device inserting T fails with
      "duplicate key value violates unique constraint device_tokens_token_key";
    - B attempting to clear the stale row deletes 0 rows, because
      device_tokens_all_own restricts delete to the owner.
  So after an unclean sign-out, an app reinstall that reuses the token, or a
  handed-down phone, that device can never register again and the user silently
  receives no reminders. `token unique` came from the brief and ultimately from
  the spec's "owner-only RLS, the app writes it directly", which did not consider
  reassignment.
  Rejected fix: replacing the unique constraint with unique (profile_id, token).
  That would let two accounts hold the same token and the drain would then send
  A's reminders to B's device — a privacy leak, strictly worse than the bug.
  Correct fix is a security-definer registration function that deletes any row
  holding the token before inserting for the caller (possession of the token
  proves you are on that device). Holding the ruling until the review returns so
  it can be decided once, with the reviewer's view included.
Task 6: review — spec ✅, quality NEEDS WORK, 0 critical, 2 important, 1 minor.
  The reviewer independently reached the same token-reassignment conclusion the
  controller had probed, and added a coverage gap the controller missed: the
  policy is `for all` precisely so the app can insert on sign-in, update
  last_seen_at, and delete on sign-out — but the tests exercise only INSERT and
  SELECT. A refactor narrowing the policy to `for select, insert` would pass all
  five assertions.

Ruling: R11 — FIX the untested half of the `for all` policy (review important
#1). Four assertions: owner updates their own row, a non-owner update affects
zero rows, owner deletes their own row, a non-owner delete affects zero rows.
Non-owner cases assert ZERO ROWS AFFECTED rather than an error, because RLS
filters rather than raising for update and delete — the same distinction R17
forced in M0's addresses test. Cost if wrong: four cheap assertions.

Ruling: R12 — ADD a registration function now rather than deferring the token
problem to Phase 2 (review important #2, and the controller's own probe).
`token unique` plus owner-only RLS makes the device unable to ever re-register
after an unclean sign-out, an app reinstall that reuses the token, or a
handed-down phone; the user then silently receives no reminders, which is the
worst failure shape for a reminder app.
Considered and rejected: (a) unique (profile_id, token) — two accounts could then
hold one token and the drain would deliver A's reminders to B's device, a privacy
leak strictly worse than the bug; (b) an app-side `on conflict (token) do update`
upsert — the conflict path needs UPDATE on the EXISTING row, which owner-only RLS
denies to the new user, so it cannot work; (c) deferring to Phase 2 — the table's
only correct usage contract belongs with the table, and Phase 2 would meet this
as a silent no-push bug in app code where it is far harder to diagnose.
Chosen: `public.register_device_token(p_token text, p_platform text)`,
security definer, which deletes any row holding that token and then inserts for
the caller. Possession of a device push token is the proof that you are on that
device, which is the standard basis for this operation. Named without the `rpc_`
prefix deliberately — the `rpc_*` family added in Tasks 7 and 8 is service_role
only, whereas this one is client-callable, so the prefix would mislead.
This widens the public allowlist to a third entry, which is exactly the
deliberate act R3's guard exists to force.
Cost if wrong: an attacker holding a stolen device token could redirect that
device's reminders to their own account. Accepted: the token is device-specific
and not user-visible, and the same trust assumption underlies every push
registration scheme. Phase 2 may restructure the call site; the function is
trivial to change before anything ships.
Task 6: fix round 1/5 dispatched (F1=R11 four policy-coverage assertions,
F2=R12 register_device_token plus allowlist widening and one assertion).
plan(5) -> plan(10); suite 131 -> 136.
Task 6: fix round 1/5 complete (2 addressed, 0 open; commits 6f9e51a..138e181).
  Controller verified: register_device_token has prosecdef=true, is executable by
  authenticated and NOT by anon ("permission denied for function"), the live set
  of client-callable public functions is exactly the three in the allowlist, and
  a two-user probe leaves the token on exactly one row.
  Re-review: both ADDRESSED, no new breakage. It confirmed the non-owner
  assertions use valid data-modifying CTEs rather than the invalid bare-update-in
  -FROM form, that the owner-delete runs last so it destroys no fixture a later
  assertion needs, and that the F2 assertion proves the token MOVED (total 1 and
  all of it owned by the new account) rather than merely existing.
Task 6: minor (deferred): register_device_token is delete-then-insert, so a user
  re-registering a token they already own gets a new id and created_at. Harmless,
  but not idempotent at row identity; no test covers same-owner re-registration.
Task 6: minor (deferred): the 42501 "no signed-in user" guard inside
  register_device_token is not exercised by any assertion.
Task 6: complete (commits 1f50142..138e181, review clean after 1 fix round)

Controller note: that last re-review took ~25 minutes of wall clock for a 6.5KB
diff. Not a correctness problem, but worth knowing that scoped re-reviews are not
reliably fast; budget for it rather than assuming a stall.

Task 7: dispatched (opus), BASE 138e181, brief task-7-brief.md,
report task-7-report.md. The largest and most intricate task in the phase — the
outbox, the fan-out with December-to-January wraparound and Feb-29 handling, the
drain helpers, and the service_role rpc wrappers from R2. Chosen the most capable
model deliberately: the loop-with-data-modifying-CTE and the leap-year branch are
mine and untested, so if there is a bug the implementer has to debug my SQL
rather than transcribe it.
Task 7: DONE_WITH_CONCERNS at fadb55d, Files=18 Tests=145 PASS.

Ruling: R13 — the CONTROLLER'S PLAN WAS WRONG about the assertion count, and the
implementer was right to correct it. The brief declared plan(8) but the test body
I wrote contains 9 assertions; my own pre-flight scan compounded the error by
recording "T7 | clean; plan(8) matches 8". The implementer changed plan(8) to
plan(9) without removing or weakening anything, and raw TAP showed nine ok lines
and zero not-ok. Verified independently: the file has 9 assertion calls and
declares plan(9). True end state is 145, not the 144 my plan predicted, so
downstream expectations move +1: T8 150, T9 151. Cost if wrong: none — this is a
correction toward reality.

Both areas I flagged as likely bugs in my own SQL turned out CORRECT, verified
twice over. The implementer probed them directly and the controller re-probed
independently:
  - accumulation across the three offsets genuinely totals (a direct three-offset
    probe returned 3, and the existing assertion would already have caught an
    overwrite because only offset 7 matches on 2027-01-01);
  - the Feb-29 branch is right in all four scenarios and never double-fires —
    2027-02-28 (T-0 observed) = 1, 2027-02-21 (T-7 to Feb 28) = 1,
    2028-02-28 (T-1 to the real Feb 29) = 1, 2028-02-29 (T-0) = 1, four rows
    total with zero duplicate (occasion_date, offset_days) pairs.
Grant surface verified: all four private functions are auth=f anon=f svc=f, and
all three public rpc_* are auth=f anon=f svc=t — exactly R2's design. RLS on
private.notification_outbox is enabled, so T1's guard covers it.

Task 7: deferred (implementer-raised, controller-assessed): no timezone
  handling — enqueue_reminders uses current_date, which is UTC. Assessed as
  ACCEPTABLE for v1 rather than a defect: Task 9 schedules the fan-out at 03:00
  UTC, which is 08:30 IST, the correct calendar day and a reasonable morning
  delivery for a v1 scoped to one Indian city. It WOULD misfire for timezones
  behind UTC (US Pacific would see a T-0 on the prior evening), so this becomes
  real the moment the product leaves India. Belongs in the M1 spec's open
  questions, not a Phase 1 fix.
Task 7: deferred: `attempts < 5` in next_reminder_batch is a silent dead-letter —
  nothing reports on rows that exceed it, so a persistently failing push
  disappears with no signal. Worth an ops surface in M4.
Task 7: deferred: enqueue_reminders scans public.celebrations three times per run
  (once per offset) with no batching. Irrelevant at pilot scale, worth revisiting
  before the graph is large.
Task 7: review (opus) — spec ✅, quality NEEDS WORK, 0 critical, 5 important,
  4 minor. The strongest review of the phase. Adjudicating each:

Ruling: R14 — I1 is REJECTED AS STATED but a real defect underneath. The reviewer
claimed a partial multi-device failure lets the succeeding device get a duplicate.
Tested directly: with device A marked sent and device B marked failed, sent_at is
set, attempts=1, and a re-drain emits ZERO rows. No duplicate. What IS real is the
mirror image — device B is silently dropped FOREVER, because the successful
device already stamped sent_at for the shared outbox row. Per-device delivery
tracking is the only true fix and that is a new table; at pilot scale, with most
users on one device, the cost is not worth it now. DEFERRED with the contract
written down: delivery is at-most-once per outbox row, NOT per device. The
reviewer's sub-point that `limit p_limit` counts token-rows rather than reminders
is real and IS fixed as part of R15. Cost if wrong: a two-device user occasionally
misses a reminder on one device.

Ruling: R15 — I2 ACCEPTED and fixed; this is the actual double-send vector. Two
overlapping drains both read the same unclaimed rows and both send, and the
enqueue-side unique constraint cannot help because it guards insertion, not
delivery. `for update skip locked` ALONE is insufficient: the rpc runs as a single
implicit transaction, so the lock releases the moment the select returns and a
drain a millisecond later takes the same rows. The fix is a real claim —
`claimed_at`, set by an UPDATE ... RETURNING, with a 10-minute lease so a crashed
drain does not strand rows permanently. Claim eligibility also requires a device
to EXIST (via EXISTS, not a join), which both keeps `limit` counting reminders and
stops a device-less row being claimed and stranded — the latter matters because
the existing assertion 8 calls the batch function with no device registered, and a
naive claim would strand those rows and break assertion 9.
Cost if wrong: a drain that dies mid-send re-sends after ten minutes.

Ruling: R16 — I5 ACCEPTED and fixed. Nothing anywhere deletes celebration edges
when a block is created, so the fan-out keeps queueing reminders about someone who
has since blocked the celebrator, and the drain ships that person's display_name
into a push notification. guard_celebration blocks NEW edges and
celebrations_select_incoming filters reads, so this is the one read path in the
schema that ignores blocks. Consistency here is a privacy property, not a
preference. Cost if wrong: a reminder stops arriving for a pair where one blocked
the other, which is the intended reading of a block.

Ruling: R17 — I3 and I4 ACCEPTED and fixed. Five of the eight objects this task
creates have zero assertions, offset 1 is never exercised anywhere, and the
leap-year T-1 case (2028-02-28, the single highest-risk path in the task) existed
only in a scratch probe that was then discarded. The reviewer's line is exactly
right: two is() calls made permanent would be the most valuable lines in the file.
Also covering the table-returning wrapper, where return-type drift fails at
runtime rather than at DDL time and no guard would catch it.

Ruling: R18 — M1 and M2 ACCEPTED and fixed, both free now and awkward later.
The partial index leads with sent_at, which is constant-null across every row the
index contains; and `kind` sits outside the unique constraint, so the day a second
kind is added a reminder and the new kind for the same person/date/offset collide
and the second vanishes silently into DO NOTHING. Changing a constraint on a live
queue later is far worse than adding a column to it now.
Task 7: minor (deferred): M3 — mark_reminder_sent/failed are silent on a
  nonexistent or already-sent id (0 rows affected, success returned), and
  mark_reminder_sent will overwrite an existing sent_at.
Task 7: fix round 1/5 dispatched (R15 claim+lease, R16 blocks filter, R17 eight
  assertions, R18 index and constraint). plan(9) -> plan(17); suite 145 -> 153.
Task 7: fix round 1/5 complete (4 addressed, 0 open; commits fadb55d..70585ad).
  The implementer found THREE defects in the controller's own fixture
  instructions and corrected them while preserving every is() call and expected
  value verbatim: (a) "a sent reminder never comes back" assumed a one-row outbox
  when three rows exist by then, so marking only the first sent would have failed
  for an unrelated reason; (b) the offset-1 assertion's
  `where enqueue_reminders(...) > 0` was unconditionally broken, not merely
  fragile — the preceding delete empties the table so the qual never evaluates
  and the fan-out never runs; (c) the block assertion would have read 1 regardless
  of the block, because another fixture person's Jan 8 birthday fires at offset 7
  and has no profile to block with. The re-reviewer independently confirmed all
  three legitimate and stated what would now break each.
  Controller verified independently: suite 153; both guards zero-diff; unique key
  now includes kind; index is (attempts, id) where sent_at is null; claim cycle
  gives 1 -> 0 -> 1 after ageing the claim to 11 minutes.
  DISCRIMINATION PROVEN THE HARD WAY: the controller applied a REVERSED block
  predicate to the live database and re-ran the file — assertion 17 failed with
  "have: 1 / want: 0", then `supabase db reset` restored correctness and the suite
  returned to 153 PASS. The test genuinely pins the operand order rather than
  merely counting rows.
Task 7: CARRY FORWARD TO TASK 11 (load-bearing): private.next_reminder_batch is
  now DATA-MODIFYING (it claims). public.rpc_next_reminder_batch must therefore be
  invoked as a POST. supabase-js `.rpc()` issues POST by default so the planned
  drain is fine, but a GET-style PostgREST call would run in a read-only
  transaction and fail at RUNTIME, not at deploy. Must appear in Task 11's
  dispatch.
Task 7: minor (deferred): no committed assertion covers LEASE-EXPIRY RECLAIM —
  fixture 1 nulls claimed_at rather than ageing it, so the "even once its lease
  has expired" path is proven only by controller live probe (1 -> 0 -> 1). This is
  the mechanism that stops a crashed drain stranding rows forever, and silent
  failure there means reminders quietly stop. Cheap to close later:
  `update ... set claimed_at = now() - interval '11 minutes'` then assert the
  batch is non-empty. Flagging for the final whole-branch review to triage.
Task 7: minor (deferred): assertion 14's lives_ok on rpc_next_reminder_batch now
  has a SIDE EFFECT (it claims), inert only because a prior assertion set every
  row to attempts = 5. Reordering assertions in that file would make it mutate
  state.
Task 7: minor (deferred): mark_reminder_failed does not clear claimed_at, so a
  failed row is unretryable for the remainder of its 10-minute lease. De-facto
  backoff rather than a bug.
Task 7: complete (commits 138e181..70585ad, review clean after 1 fix round)

Task 8: dispatched (sonnet), BASE 70585ad, brief task-8-brief.md,
report task-8-report.md. Match-only contact resolution plus its service_role
wrapper — smaller and self-contained after Task 7.
Task 8: DONE at 0d0f531, Files=19 Tests=158 PASS, no SQL changes needed. It
  caught a stale expected count (144) in its own brief — the controller's later
  renumberings did not propagate into already-extracted briefs. Briefs 9-11 have
  been re-extracted; brief 9 now reads 159 correctly. Lesson: re-extract briefs
  after EVERY renumbering, not once.
  Controller verified: private.resolve_contacts executable by nobody,
  public.rpc_resolve_contacts service_role only, both guards pass unmodified, and
  resolving three unknown numbers returned 0 rows leaving public.people unchanged.
Task 8: review — spec ✅, quality NEEDS WORK, 0 critical, 2 important, 1 minor.
  The reviewer CORRECTED the controller's own analysis on a key point. The
  controller had concluded the `not exists (private.suppressions)` filter was
  unreachable dead code, because suppress_person hard-deletes the people row and
  upsert_person then refuses to recreate it (probed: returns null). The reviewer
  found the path the controller missed: private.claim_person inserts/upserts into
  public.people with NO suppression check at all, so a suppressed hash CAN
  resurface via signup. The filter is genuine defence, not dead code — but nothing
  in the suite proves it works.

Ruling: R19 — FIX the suppression assertion so it exercises the guard. As
committed, the suppressed-number assertion is behaviourally identical to the
unknown-number assertion three lines above it: there is no people row to join
against, so the not-exists clause never fires, and deleting that clause from the
migration entirely would still pass all 158 tests. A real test needs a people row
co-existing with a suppressions row for the same hash — which is exactly the
claim_person path. Cost if wrong: one more assertion.

Ruling: R20 — FIX the wrapper's zero coverage. No test calls
public.rpc_resolve_contacts at all, and the controller's live probe hit the
private function, not the wrapper — so the controller cannot claim otherwise.
Return-signature drift between wrapper and inner function fails at RUNTIME, not
at DDL time, and no grant guard would catch it. This is the second task where the
wrapper went untested; Task 7's fix round added exactly this coverage for
rpc_next_reminder_batch, so doing the same here is consistent.

Ruling: R21 — FIX the duplicate-row behaviour rather than deferring it. An
address book routinely holds one number under two entries ("Mum" and "Mother"),
and unnest with no dedupe then returns the same person twice, so the import
picker shows them twice. The reviewer rated it low impact because a caller can
dedupe by person_id, but the server is the right place for it: `select distinct`
is one word and makes the contract clean rather than pushing a wart into every
client. Cost if wrong: negligible — distinct over a small result set.

Task 8: deferred (product, for the M1 spec's open questions, NOT a code change):
  a user who suppressed their own number and LATER signs up is permanently
  invisible to contacts import, because claim_person recreates their people row
  but their hash stays in private.suppressions and resolve_contacts filters on it.
  With no search surface in v1, nobody can ever celebrate them. Defensible as
  "they opted out of being imported", but it should be a decision rather than an
  emergent behaviour — and it argues for offering such a user a way to clear their
  own suppression at signup.
Task 8: fix round 1/5 dispatched (R19 real suppression assertion, R20 wrapper
  coverage, R21 distinct). plan(5) -> plan(8); suite 158 -> 161.
Task 8: fix round 1/5 complete (3 addressed, 0 open; commits 0d0f531..7a3f8d4).
  Real RED captured for F1 by crippling the live function — only the new
  suppression assertion failed, proving it load-bearing. Controller verified:
  triplicate input resolves to 1 row, the wrapper returns the right person.
  Re-review: all three ADDRESSED, no breakage. It confirmed F1 inserts the SAME
  hash the fixture suppressed (so it passes for the right reason), that F1's
  insert lands AFTER the "creates nothing" count assertion so it cannot corrupt
  it, that F2 compares against a concrete non-null value rather than
  null-equals-null, and that `distinct` can only collapse rows from a repeated
  input — it cannot merge two people, since phone_e164_hash is unique and `phone`
  is in the output.
Task 8: minor (deferred): the original suppressed-number assertion now only
  proves suppress_person's hard delete, not the guard clause. Kept deliberately
  for that narrower purpose; F1 covers the guard.
Task 8: complete (commits 70585ad..7a3f8d4, review clean after 1 fix round)

Task 9: dispatched (haiku), BASE = current HEAD, brief task-9-brief.md,
report task-9-report.md. Small: create the pg_cron extension, schedule the daily
fan-out, one assertion on cron.job. The controller already verified pg_cron 1.6.4
is preloaded, installs without a `with schema` clause, and that cron.job is
reachable and cron.schedule works as the non-superuser postgres role.
Task 9: DONE at 9eb13eb, Files=19 Tests=162 PASS. Controller verified: the job is
  `birthday-reminder-fanout | 0 3 * * * | select private.enqueue_reminders(); |
  active=true`, and a SECOND `supabase db reset` leaves exactly one cron.job row
  with the suite still green — the unschedule guard does its job.
Task 9: review — spec ✅, quality Approved, 0 critical, 0 important, 2 minor.
  The reviewer also independently confirmed the timezone reasoning the controller
  had recorded at Task 7: IST's calendar date turns over at 18:30 UTC, so from
  00:00-18:30 UTC the UTC and IST dates agree; 03:00 UTC sits inside that window,
  so current_date is the correct IST date and the push lands 08:30 IST the same
  morning. Two independent derivations now agree.

Ruling: R22 — FIX minor #2 rather than deferring it. The assertion pins only
cron.job.schedule, so a job scheduled with the WRONG command, or with active
flipped to false, would still pass. That failure mode is "reminders silently
never fire", which is the worst shape this product has — the entire value
proposition is a notification that arrives. Strengthening it costs nothing:
assert jobname, schedule, command and active together in one assertion, so
plan(18) is unchanged and no downstream renumbering is needed. Same technique as
Task 5's row-set assertion. Cost if wrong: the assertion now fails if anyone
legitimately retimes the job, which is the correct prompt to update it
deliberately.
Also taking minor #1 — a comment explaining why the FROM-less
`select cron.unschedule(...) where exists (...)` skips the call entirely rather
than calling and swallowing an error. The idiom looks like it should error; this
codebase comments its non-obvious SQL everywhere else.
Task 9: fix round 1/5 dispatched (R22 strengthened cron assertion, plus the
  idiom comment). No assertion-count change.
Task 9: fix round 1/5 complete (2 addressed, 0 open; commits 9eb13eb..d8ffde3).
  Controller note on its own bad instruction: I asked for the RED proof via
  `update cron.job set active = false`, which is IMPOSSIBLE — postgres gets
  "permission denied for table job", because pg_cron restricts direct writes to
  its own API. The implementer sensibly proved it by unscheduling instead. I then
  proved the specific case I wanted using the sanctioned
  `cron.alter_job(jobid, active := false)`: assertion 18 failed with
  "active=false / want active=true", then restored to 162 PASS. Lesson: verify a
  proof recipe is even executable before mandating it.
  Re-review: both ADDRESSED, no breakage, plan(18) unchanged.
Task 9: complete (commits 3c85a42..d8ffde3, review clean after 1 fix round)

Task 10: dispatched (sonnet), brief task-10-brief.md, report task-10-report.md.
First TypeScript/Deno task — different harness entirely (`supabase functions
serve` plus curl rather than pgTAP), so the suite count does NOT move. Carried
the service_role/POST facts and a concrete recipe for obtaining a real user JWT,
since the brief's "get a token from supabase status" is wrong — status prints API
keys, not user tokens.
Task 10: DONE at 16944cf. Suite unchanged at Files=19 Tests=162 PASS (this task
  adds no pgTAP). All six HTTP paths exercised: GET->405, bad shape->400,
  missing auth->401, bogus auth->401, real token + known number->match with the
  right display_name, real token + unknown number->no match; and no people row
  was created. Controller verified the code calls .rpc("rpc_resolve_contacts")
  with no .schema("private"), MAX_BATCH=500, and the method/auth/shape guards.
  The brief's TypeScript needed NO changes — the first task where that held.
Task 10: review — spec ✅, quality Approved, 0 critical, 0 important, 2 minor.
  Reviewer hand-traced the input edge cases: empty array passes vacuously,
  missing key -> clean 400, null element -> clean 400, and a literal `null` body
  throws inside the try so it returns 400 rather than an unhandled 500.
  Privacy confirmed: no request body, phone array or individual number is logged
  or echoed anywhere; only error.message reaches the log and only a generic
  "resolution failed" reaches the client.
Task 10: controller resolved the reviewer's one ⚠️ (could the DB function raise an
  error whose text embeds a raw phone, which the wrapper would then log):
  20260824000007_resolve_contacts.sql contains zero `raise` or `format(` calls —
  it is a plain select over a text[] parameter — so no phone value can reach an
  error message. Not a gap.
Task 10: minor (deferred): after the Array.isArray + .some(typeof) guard,
  TypeScript narrows `phones` only to any[], not string[], because .some is not a
  type predicate. Runtime is correct; there is no compile-time protection if the
  function is refactored later.
Task 10: minor (deferred): the catch block's "invalid json" message also fires
  for valid-but-wrong-shaped JSON such as a literal null body. Status code is
  right; only the label is imprecise.
Task 10: environment facts worth keeping: the edge runtime injects LEGACY
  JWT-format SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY, not this stack's
  newer sb_publishable_/sb_secret_ keys. And `supabase test db` does NOT reset the
  database, so manual psql inserts made while testing HTTP will cause spurious
  pgTAP failures until a `supabase db reset`.
Task 10: complete (commits d8ffde3..16944cf, review clean)
Task 11: DONE at 41f6435, suite Files=19 Tests=162 PASS. Controller verified the
  three wrappers are called with no .schema("private") and no { get: true }, and
  that the POST requirement and the dry-run claim consequence are both
  explicitly commented.
Task 11: review — spec ✅, quality NEEDS WORK, 1 CRITICAL, 2 important, 2 minor.

Ruling: R23 — CRITICAL ACCEPTED. The brief specified a DEAD API. Google shut down
the legacy FCM HTTP endpoint (fcm.googleapis.com/fcm/send with a `key=SERVER_KEY`
header) in 2024; it no longer accepts traffic. So the real-send path is dead on
arrival and, the moment Phase 2 supplies credentials, every reminder would land
in the failed bucket. This is entirely my error — the reviewer is right that the
implementer should also have flagged it, but it was mine to get right.
NOT building the full FCM HTTP v1 integration now. v1 needs a service-account
private key, JWT signing and an OAuth2 token exchange — roughly sixty lines that
cannot be tested at all without real Firebase credentials, which is exactly the
speculative, untestable work the plan warns against.
Instead making the code HONEST: move to the v1 URL and body shape, take the
project id and a bearer token from env, and dry-run whenever either is absent —
so the shape is right, the path is exercisable with a stub, and the single
remaining gap (minting the token from a service account) is named in a comment
for Phase 2 rather than discovered as a silent failure. Renaming FCM_SERVER_KEY
too, since that concept no longer exists in v1.
Cost if wrong: a static FCM_ACCESS_TOKEN expires hourly and is not a deployment
strategy — it is a deliberately marked placeholder, and Phase 2 must replace it
with the service-account exchange. That is stated in the code.

Ruling: R24 — important #1 ACCEPTED. The two mark_* rpc calls are awaited but
their `.error` is never checked, unlike the batch call directly above them. A
failed mark still increments sent/failed, so the function reports success while
the outbox was never updated — silently, with no log. Cheap to fix and squarely
the class of bug that makes a queue lie about itself.

Ruling: R25 — important #2 DEFERRED, and it is Task 7's deferred I1 restated
from the drain side. Once any one device succeeds, sent_at is set and the outbox
row is permanently excluded, so a failed second device is never retried; and
last_error's final value is order-dependent. The true fix is per-device delivery
tracking, which is a new table, and the judgement from Task 7 stands at pilot
scale. Adding a comment in the loop so the behaviour is documented where someone
would meet it. Also carrying it into the final review's triage list.
Task 11: fix round 1/5 dispatched (R23 FCM v1 shape, R24 check mark_* errors,
  plus the two minors: symmetric dryRun flag in the real response, and env lookups
  that fail in the deliberate JSON shape rather than as a raw Deno 500).
Task 11: fix round 1/5 complete (4 addressed, 0 open; commits 41f6435..1bd0bd5).
  The implementer proved the v1 path is genuinely exercised rather than skipped:
  with a stub token FCM returned 401, attempts incremented 0->1, and sent_at
  stayed null. It also self-corrected its earlier "no functional correction
  needed" claim. Process finding worth keeping: `supabase functions serve` needs
  `--env-file` to pass values into the runtime; prefixed shell env vars are
  silently ignored, which first showed up as a false-negative dry run.
  Re-review: all four ADDRESSED, no breakage, both required comments present and
  accurate, and logs carry only outbox_id plus message — never the row, which
  holds a device token and a person's name.
Task 11: complete (commits 16944cf..1bd0bd5, review clean after 1 fix round)

=== ALL 11 TASKS COMPLETE ===

## Final whole-branch review (opus) — 6 blocking, 7 important

Verdict accepted almost entirely. Three findings were PROVED against the live
database by the reviewer, which is why they outrank anything a per-task review
produced. Adjudication:

Ruling: R26 — BLOCKER 1 ACCEPTED, and it is the single best find of the phase.
private.sync_person_from_profile coalesces birth_month, birth_day and birth_year
INDEPENDENTLY against the existing people row, but the new CHECK constraints
validate them as a TRIPLE. The trigger can therefore synthesise a row nobody
asked for and no constraint permits. Reviewer's live proof: people = (3,15,1985),
user sets profiles = (2,29,null), and the write aborts with
people_birth_leap_valid on a synthesised (2,29,1985). The user's own legal
profile edit is rolled back with an error the app cannot interpret — and
"edit your own birthday" is on the onboarding screen and inline on every timeline
row. Neither Task 2's review nor mine saw it because the constraints and the
trigger were examined separately; only the whole-phase view exposes it. My R4
year invariant is what made the second variant reachable. Fix: coalesce the
triple as a unit.

Ruling: R27 — BLOCKER 2 ACCEPTED. private.resolve_contacts is a security-definer
bypass of the product's central privacy invariant. M0's own comment states it:
"A person is visible if they are me, if I celebrate them, or if they celebrate
me. Nothing else. This is what keeps a stranger's birthday undiscoverable."
resolve_contacts applies no relationship check, no block check and no
can_see_person, so any signed-in user can POST 500 arbitrary numbers per request,
repeatedly, and harvest display_name plus birth_month/birth_day for every hit.
The "is this number known" half is inherent to contact discovery and stays. The
BIRTHDAY does not: the import screen needs to know only WHETHER a birthday is
missing so it can prompt for one. Fix: return has_birthday boolean instead of the
parts. My plan specified those columns, so this is mine.

Ruling: R28 — BLOCKER 3 ACCEPTED. celebrations_select_incoming exposes the whole
row, because RLS is row-level and not column-level — so the subject sees the
celebrator's private `nickname` and the `source` that reveals HOW they were found.
Reviewer's live proof: "that idiot from work | contacts". Spec §10 explicitly
refuses to reveal an import to its subject; this phase closes that door and
leaves a window beside it. Column grants cannot fix it (they are role-wide and
would blind celebrators to their own nicknames), so the incoming list becomes a
security-definer function returning only what the list needs, and the policy is
dropped. More work than the others, and worth it.

Ruling: R29 — BLOCKER 4 ACCEPTED AS A DEFERRAL, which the reviewer explicitly
permits. Spec §5 says the cron should enqueue "then trigger the drain", and only
the enqueue job exists, so the pipeline never sends and the outbox grows without
bound. But scheduling the drain NOW would be actively harmful: no FCM credentials
exist, so every run would claim a batch, drop it, and — until R31 lands — recycle
it forever. Deferring to Phase 2 alongside the credentials is correct; leaving it
UNSAID was not. Recording it here, adding it to the spec's open questions, and
correcting the plan's Definition of Done so "drain_reminders in dry-run mode" can
no longer read as end-to-end coverage.

Ruling: R30 — BLOCKER 5 ACCEPTED. The reviewer showed that changing the lease
from '10 minutes' to '10 years' passes all 162 assertions, which would strand
every crashed drain's rows permanently. This is the item the ledger explicitly
handed to this review. Two lines: age claimed_at instead of nulling it.

Ruling: R31 — BLOCKER 6 and IMPORTANT 7 ACCEPTED, fixed together because they
are the same mechanism. next_reminder_batch emits one row PER DEVICE TOKEN and
device_tokens_all_own permits unlimited inserts, so any authenticated user can
multiply their own reminders into an arbitrary number of FCM calls. And the claim
stamps claimed_at but not attempts, so a drain that dies — or today's dry run,
which claims and returns without marking — leaves attempts at 0 and those rows
recycle every ten minutes forever, meaning `attempts < 5` never engages. Fix:
bound the token join, and increment attempts AT CLAIM TIME instead of in
mark_reminder_failed, so the counter cannot double-count and a crash loop is
bounded.

Ruling: R32 — IMPORTANT 6 PROMOTED TO BLOCKING. drain_reminders never inspects
its request at all, and the publishable key is itself a valid JWT, so anyone who
unzips the app can invoke it. Alone it burns ten-minute leases; with credentials
it spends FCM quota on demand. resolve_contacts checks its caller; this must too.
Cheap, and leaving an unauthenticated trigger on the send path is not something
to carry into Phase 2.

Ruling: R33 — IMPORTANT 9 and 11 ACCEPTED. Three assertions are weaker than they
read, and the reviewer disproved the justification I wrote for one of them: for a
`language sql` function, return-type drift raises at CREATE, so `db reset` already
guards it and the lives_ok assertion checks only that the function exists. Also
fixing the guard asymmetry — Task 1 extended the RLS guard to `private` but left
the FK-index guard scanning `public` only — with the one-line collapse that also
retires T1's duplication minor.

Ruling: R34 — IMPORTANT 8 ACCEPTED as a documentation change only. The reviewer
is right that R12's risk note understates register_device_token: an attacker can
move a victim's token, then arrange attacker-chosen display_name text to arrive
as a trusted push on the victim's phone while the victim loses their own
reminders. Delete-and-reassign remains the right pattern, but the note must say
this, and Phase 2 must not put an unsanitised name in a notification body.

## Final fix wave

Dispatched once per the skill's "ONE fix dispatch" rule. Two infrastructure
failures, no logic failures:
  - attempt 1 (opus) died instantly to a session limit, zero edits made;
  - attempt 2 (sonnet) committed F1/F2/F3 and stalled mid-F5 on a stream
    watchdog, leaving F4+F5 code in the working tree with plan(18) declared
    against 19 assertions (suite RED).
Neither was a review-loop round, so the fix-round counter does not advance.
Instructions were moved to files (final-fix-brief.md, then
final-fix-handoff.md) rather than living in a prompt, so a third dispatch could
resume precisely rather than reconstruct.

Committed so far: F1 e7add52 (sync trigger replaces the birthday triple
wholesale), F2 eb5171d (resolve_contacts returns has_birthday, not the parts),
F3 f588076 (my_celebrates() replaces the incoming-edges policy; allowlist
widened to four).
Controller commit 43c5a2c recorded the deliberate deferrals in the spec's open
questions (drain not scheduled, no Settings-toggle backend, at-most-once per
outbox row, five-device bound) and corrected the plan's DoD so "dry-run mode" can
no longer read as end-to-end coverage.

Controller-found while assessing the stall: moving the attempts increment to
claim time left the "a failed delivery increments attempts" assertion HOLLOW — it
would still pass, but only because an earlier claim advanced the counter, so its
description would be false. Handed the third implementer a rewrite asserting
last_error instead (the failure's actual observable effect) plus a new assertion
that the CLAIM is what advances attempts, with instructions to verify the values
empirically rather than trust mine.

Remaining at handoff: the plan count, the attempts/last_error rewrite, the
six-device bound assertion, and F6-F9 untouched.

## === PAUSED at user's request, 24 Aug 2026 ===

STATE: branch worktree-m0-schema-and-rls, HEAD 36b0397. **THE SUITE IS RED.**
`supabase db reset && supabase test db` gives Files=19, Tests=169, FAIL.

This is the ONLY point in either milestone where the suite has been left red, so
it is deliberate and recorded rather than accidental. All work is committed —
nothing lives in a working tree.

### Resume here

Two assertions genuinely FAIL in 17_reminders.test.sql, and plan(18) is declared
against 21 assertions. Do NOT just raise the plan count — that would paper over
two real failures.

1. "claiming a reminder counts an attempt" — expects max(attempts) = 1 after one
   next_reminder_batch() call. The expected value was written by the controller
   from reasoning, not measurement. Measure what a claim actually leaves and use
   the real number.
2. "a recipient with six registered devices yields at most five rows for one
   reminder" — expects 5. The `cross join lateral ... limit 5` IS in the
   migration, so either the fixture is not producing six eligible devices, or an
   earlier assertion in the file left state that interferes. This file's
   assertions run in sequence and mutate shared state.
3. Then set plan() to the true count and confirm green.

### Then finish the fix wave — still untouched

- **F6** (blocking): `drain_reminders` never inspects its request, and the
  publishable key is a valid JWT, so anyone who unpacks the app can trigger a
  drain. Add the `x-drain-secret` / `DRAIN_SECRET` check. Spec'd in
  final-fix-brief.md. Note `supabase functions serve` needs `--env-file`.
- **F7 item 3**: 18_resolve_contacts.test.sql's "creates nothing" proof counts
  ALL rows in public.people, so a future seed.sql addition breaks it for an
  unrelated reason. Count only this file's own fixture.
- **F8**: 11_rls_coverage.test.sql's FK-index assertion still scans `public`
  only while the RLS ones cover both schemas. Merge with
  `n.nspname = any(array['public','private'])`.
- **F9**: comment only, in 20260824000005_device_tokens.sql — state that an
  attacker holding a victim's device token can deliver attacker-chosen text as a
  trusted push while the victim loses their reminders, and that Phase 2 must not
  put an unsanitised display_name in a notification body.

Then: one scoped re-review of the whole fix wave, then
superpowers:finishing-a-development-branch. There is no second fix wave — any
residual findings get adjudicated and surfaced.

### Instruction files (durable, but git-ignored — copy them out before any clean)

- final-fix-brief.md — all nine findings with their code
- final-fix-handoff.md — what was done in which commit
- progress.md — this ledger, 34 rulings

### Environment

colima + supabase running; `colima start` needs the sandbox OFF (M0's R5).
Three subagents died here to infrastructure, not logic: one session limit and
TWO stream-watchdog stalls, both while working the large 17_reminders.test.sql.
Prefer SMALL, single-purpose dispatches on that file.

## === RESUMED 26 Aug 2026 ===

CORRECTION to the pause note: it claimed two assertions in 17_reminders.test.sql
"genuinely fail". THEY DO NOT. On a fresh `supabase db reset` all 21 assertions
pass — TAP reports "All 18 subtests passed" and lists 19-21 as failures only
because they ran beyond the declared plan(18). Verified stable across two
consecutive resets.
The earlier observation of "Failed test 13 / Failed test 15" was measured against
a database the killed agent had left dirty with psql fixtures — precisely the
"`supabase test db` does NOT reset" hazard recorded at Task 10. The third agent
had in fact fixed both assertions before I stopped it; its work is in the WIP
commit 36b0397, and I under-credited it.
Net effect: the remaining work is SMALLER than the pause note implied. The only
issue in that file is a stale plan count.

Ruling: R35 — the WIP commit's message is now inaccurate (it says two assertions
fail and warns against raising the plan count). NOT amending it — the branch is
shared history and the ledger is the authoritative record. Recording the
correction here and in the commit that fixes the count, which is where anyone
reading `git log` will meet it. Cost if wrong: a reader of 36b0397 in isolation
is briefly misled, then corrected by the very next commit.

## Scoped re-review of the fix wave (opus)

F1-F6, F8, F9 ADDRESSED, each with coverage the reviewer proved discriminating
against the exact mutation the finding named. It also traced the retry
arithmetic I asked about: with attempts post-incrementing at claim time, claims
occur at attempts 0,1,2,3,4 — exactly five real delivery attempts before the cap
engages, identical to the old increment-on-failure semantics. No row loses an
attempt. Verdict: safe to merge, with residuals.

Ruling: R36 — CLOSE the four residuals rather than surfacing them, despite the
"no second fix wave" rule. This is completing the FIRST wave, not opening a
second:
  - F7 items 1 and 2 were ruled ACCEPTED in R33 and then LOST in my own 26 Aug
    handoff note, which listed only "F7 item 3" as remaining. They were dropped
    by accident, not deferred by decision, and shipping them as "closed" would
    misrepresent the record.
  - The reviewer found a REGRESSION the wave introduced: F7 item 3's scoped
    count omits the unknown number from its IN list, so the assertion titled
    "resolving unknown numbers creates no people rows" can no longer move no
    matter what resolution does to an unknown number. A fix wave that leaves a
    newly-vacuous assertion behind has not finished.
  - The docs contradiction IS load-bearing: spec §4.3 still describes F3's
    mechanism as an RLS policy, but F3 replaced it with public.my_celebrates().
    The spec is Phase 2's input, so shipping it would hand Phase 2 a
    security-relevant design that no longer exists.
Four small edits, three test lines and two docs. Cost if wrong: twenty minutes
against a branch that is otherwise ready.

Ruling: R37 — the reviewer endorsed leaving 36b0397's stale message unamended
(R35), on the grounds that the next commit contradicts it in its own message,
the ledger is authoritative, and amending shared history another worktree may
reference buys nothing. Recording the concurrence.

Carried to Phase 2, NOT fixed (recorded so they are decisions, not omissions):
  - the dry run burns retries — the claim increments attempts, so five dry-run
    invocations permanently strand a reminder at attempts=5. Harmless today
    since nothing schedules the drain, but if Phase 2 schedules it BEFORE FCM
    credentials land, every enqueued row dies within five ticks. The spec's open
    question 1 catches the scheduling half; this is the other half.
  - clearing a birthday on profiles does not clear it on people, so a user who
    deletes their DOB keeps generating reminders on the old date. Matches the
    pre-fix behaviour and what the brief specified, so not a regression — but it
    belongs beside the Settings toggle in Phase 2's backlog.
  - re-adding attempts++ to mark_reminder_failed would fail no test; the
    double-count guard is untested.
  - pg_net will need DRAIN_SECRET readable from Postgres (private.config or
    Vault) as well as in the function env, and the cron migration must not
    embed the literal.
