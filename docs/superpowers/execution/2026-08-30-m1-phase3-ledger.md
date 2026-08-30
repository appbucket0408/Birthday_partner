# SDD ledger — plan: docs/superpowers/plans/2026-08-30-m1-phase3-social-loop.md

Spec: docs/superpowers/specs/2026-08-29-m1-phase3-social-loop-design.md
Branch: `m1-phase3-social-loop`, in the main checkout (no worktree — same
ruling as Phase 2b: worktrees cost this project twice before, M0's removal
nearly destroyed a ledger and Phase 2a's isolation stopped a session merging
its own work).
Controller's running notes: `.superpowers/sdd/2026-08-30-m1-phase3-social-loop/progress.md`

This is Task 9, the phase close. Tasks 1–8 are complete and individually
reviewed (see progress.md for the full per-task record, including every
implementer report and every review). This document is the cold-verification
record and the carry-forward manifest.

Task 9 itself did two small things before verification (folded in from
Task 8's review rather than deferred — see progress.md's Task 8 entry):

1. Added `test/features/profile/celebration_list_screen_test.dart`, pinning
   the Celebrates/Celebrating privacy split (`navigable` defaults `false`;
   only `/profile/celebrating` passes `true`) that was previously
   structurally correct but wholly untested. Verified the regression test
   by flipping the default to `true` and confirming it failed
   (`Expected: null, Actual: <Closure: () => void>`), then restoring it.
2. Fixed a nickname inconsistency: `TimelineScreen` rendered
   `Celebration.label` (nickname-aware) for an edge, while the profile's
   Celebrating list rendered plain `Person.displayName` for the same edge,
   per the original brief's "take a list of Person" framing. Added
   `CelebrationListScreen.peopleFromCelebrations()`, the same kind of small
   per-route mapping the screen already relies on, so `/profile/celebrating`
   substitutes each person's label. `/profile/celebrates` is untouched:
   those are incoming edges, and `my_celebrates()` deliberately never
   returns the celebrator's private nickname.

Commits: `3ad6fa8` (both fixes above), `89b1d84` (the end-to-end test).

---

## 1. Final verification numbers

All commands run from a cold `supabase db reset`, on branch
`m1-phase3-social-loop` at HEAD `89b1d84`, with the local Supabase stack
already up (colima + docker), using FVM Flutter 3.35.2 / Dart 3.9.0 and
Supabase CLI 2.78.1.

| Command | Result |
|---|---|
| `supabase db reset && supabase test db` | **28 files / 267 assertions, `Result: PASS`** — matches expectation |
| `supabase functions serve --no-verify-jwt &` then `./supabase/functions/test.sh` | **6 passed, 0 failed** (Deno) |
| `fvm flutter analyze` | **`No issues found! (ran in 1.2–1.6s)`** |
| `fvm flutter test --exclude-tags=contract` | **131 passing, 0 failed** (`All tests passed!`) |
| `fvm flutter test test/repositories test/e2e --dart-define=SUPABASE_ANON_KEY=...` | **40 passing, 0 failed** (`All tests passed!`) |

All five numbers match the brief's stated expectations (the two Flutter
counts were not given fixed targets in the brief, only "report what you
observe" — both reconcile exactly against the previous phase-close count
plus what Task 9 added, see below). No discrepancy to report.

Detail:

- `supabase db reset` applied all 30 migrations
  (20260822000001 through 20260830000001) and the seed script cleanly, with
  only an expected idempotent-extension notice
  (`extension "pgcrypto" already exists, skipping`).
- `supabase test db` ended: `All tests successful. Files=28, Tests=267 ...
  Result: PASS.` This is unchanged from Task 8's last recorded run — Task 9
  added no new migrations or pgTAP files, only Flutter/Deno-level tests.
- The Deno suite was run against `supabase functions serve --no-verify-jwt`,
  not a bare `supabase functions serve`, for the reason recorded in the
  brief and in Phase 2b's own ledger: `config.toml` carries no `[functions]`
  block, so every function serves at `verify_jwt = true` by default and an
  unauthenticated request is rejected by the API gateway before
  `add_celebrations`' own 401 guard is ever reached. All 6 tests passed,
  including `add_celebrations/index.test.ts`'s "a suppressed number is
  reported as an opaque skip, never labelled" — the test protecting the
  fix recorded in commit `0901364` (Task 2).
- `fvm flutter analyze` reported `No issues found!` against the full `lib/`
  and `test/` tree, both before and after this session's own edits.
- `fvm flutter test --exclude-tags=contract` printed `All tests passed!`
  ending at `+131`. Task 8 closed at 127 non-contract; this session's four
  new tests in `celebration_list_screen_test.dart` (two for the privacy
  split, two for the nickname fix) account for the difference exactly
  (127 + 4 = 131).
- `fvm flutter test test/repositories test/e2e
  --dart-define=SUPABASE_ANON_KEY=...` (anon key pulled fresh from
  `supabase status -o json` after the reset) printed `All tests passed!`
  ending at `+40`. Task 7 closed the repository contract suite at 39; this
  session's one new file, `test/e2e/social_loop_test.dart`, adds exactly
  one test (39 + 1 = 40). Exercised suites: `auth_repository_test.dart`,
  `contacts_repository_test.dart`, `graph_repository_test.dart`,
  `person_repository_test.dart`, `profile_repository_test.dart`,
  `settings_repository_test.dart`, `wish_repository_test.dart`, and
  `test/e2e/social_loop_test.dart` — each on its own dedicated phone number
  (see the per-suite pool below), so no cross-suite interference occurred at
  default concurrency.
- The e2e test signed in as `+919999000010` (added to
  `[auth.sms.test_otp]` in Task 1, unused by every other suite), claimed,
  added a celebration through `ContactsRepository`, confirmed it was
  readable through `GraphRepository.celebrations()` with its birthday
  intact, posted a wish through `WishRepository` using
  `Birthday.occasionYear(DateTime.now())` (the same derivation
  `PersonCubit.postWish` uses in the real app), and confirmed
  `ProfileRepository.stats()` carried a row for that exact occasion year
  with `wishesSent == 1`.

Phone number pool at phase close (one number per contract suite, per the
Phase 2b convention this project has followed since Task 9 of that phase):
auth 001/002, contacts 003, graph 004/006, settings 005, person 007,
wish 008/011, profile 009/012, **e2e 010**.

Total suite size at phase close: 28 pgTAP files / 267 assertions, 6 Deno
tests, 131 non-contract + 40 contract Flutter tests (171 Flutter tests
total).

---

## 2. Config guard

```
$ awk '/^\[auth\./{sec=$0} /enable_confirmations/{print NR": "sec" -> "$0}' supabase/config.toml
209: [auth.email] -> enable_confirmations = false
252: [auth.sms] -> enable_confirmations = true
```

Line 209 (`false`) is under `[auth.email]` — unrelated, correct as `false`.
Line 252 (`true`) is under `[auth.sms]` — **this is the guard**, and it
still reads `true`. `git diff --stat supabase/config.toml` against `main`
was checked and the file was not touched by this session at all (Task 9's
brief forbade editing it, and no relaxation was needed this time — unlike
Tasks 5 and 7, which each needed one line added for a dedicated test
number).

This line is the fix for a reproduced total-account-takeover bug from
Phase 2a (Ruling R13, recorded in
`docs/superpowers/execution/2026-08-27-m1-phase2a-ledger.md`): with
`enable_confirmations = false`, GoTrue runs with `SMS_AUTOCONFIRM=true`,
and `PUT /auth/v1/user {"phone": ...}` silently rewrites and confirms a
session's phone number with no OTP at all, letting an attacker point their
session at an unclaimed victim's number and claim their person row
outright. It is guarded by no test and no CI. `supabase init` or a CLI
upgrade rewrites this file, and this phase specifically adds test phone
numbers to it, so it is the phase most likely of any so far to disturb this
line by accident — it must be re-checked by hand at every future phase
close until it is guarded some other way.

---

## 3. Per-task commit range

Derived from `git log --oneline main..HEAD` (`main` at `91cf50d`, HEAD at
`89b1d84`).

| Task | Range | Notes |
|---|---|---|
| (design + plan, pre-task) | `91cf50d..0617f10` | `4407ec1` (design), `0617f10` (plan) |
| Pre-flight scan fixes | `0617f10..c270153` | `c270153` |
| 1 — `person_celebrator_count` RPC | `c270153..ddf2bc9` | `ddf2bc9` |
| 2 — stop labelling suppressed numbers | `ddf2bc9..0901364` | `0901364`, plus `069c7cc` (spec correction: reduced, not closed) |
| 3 — re-entrancy guard, occasion rule, `Wish` model | `069c7cc..4035d48` | `4035d48` |
| 4 — person repository | `4035d48..65ae376` | `65ae376` |
| 5 — wish repository | `65ae376..bce413c` | `aeadd5b`, `f530ccd` (plan: second identity needs its own number), `bce413c` (fix round 1: dedicated number `...011`) |
| 6 — person page + compose sheet | `bce413c..84f6d0e` | `e44bedc`, `1e81b53` (plan: router match fix), `84f6d0e` (fix round 1: viewerCelebrates gate, postError fix) |
| 7 — profile repository | `84f6d0e..96acd57` | `a14d503` (plan), `05c4c31`, `40981b1` (Task 6's carried postWish-reload fix), `ac8d058` (plan: `...006` belongs to the graph suite alone), `96acd57` (fix round 1: dedicated number `...012`) |
| 8 — profile screens (header, both lists, track record) | `96acd57..865ce52` | `865ce52` |
| 9 — this phase close | `865ce52..89b1d84` | `3ad6fa8` (privacy test + nickname fix), `89b1d84` (e2e test) |

`main..HEAD` = `91cf50d..89b1d84`, 22 commits ahead of `main`, 0 behind, at
time of writing (branch runs directly off `main`, not a worktree).

---

## 4. Not verified

**No end-to-end run of the app on a real device has ever been performed for
this project, in any phase, and this phase does not close that gap.**

Concretely:

- **Every Flutter test in this repository — all 131 non-contract and all
  40 contract tests, this phase's new ones included — runs on the Dart
  VM.** None of them boot `main.dart`, mount `App`, or drive `GoRouter`
  inside a real iOS/Android runtime. The 40 contract tests do talk to a
  real local Supabase stack over real HTTP, which is a meaningfully
  stronger guarantee than a mock — but the client side of every one of
  those calls still runs on the Dart VM, not inside a device's networking,
  permissions, or lifecycle stack.
- **This phase's own end-to-end test, `test/e2e/social_loop_test.dart`, is
  repository-level and does not close this gap either — by design, and
  said so plainly rather than left to be discovered.** It drives
  `AuthRepository`, `ContactsRepository`, `GraphRepository`,
  `WishRepository`, and `ProfileRepository` directly, proving the parent
  spec's "sign in → import → timeline → wish → profile counts tick" loop
  holds at the layer that actually talks to the server. It does not mount
  a single widget, push a single route, or exercise `PersonCubit`,
  `TimelineScreen`, the compose sheet, or the profile screens that Tasks 6
  and 8 built on top of these same repositories. A defect in any of that
  wiring — a button that calls the wrong repository method, a route that
  never registers, a cubit that never rebuilds its widget — would not be
  caught by this test or by any other test in this suite, because none of
  them run above the repository seam against a real UI.
- **This is not a hypothetical risk category for this specific project.**
  Phase 2b's own ledger records that an iOS App Transport Security defect
  (no `NSAppTransportSecurity` key in `Info.plist`, silently blocking every
  cleartext request to the local Supabase stack) survived 96 passing tests
  — 72 non-contract plus 24 contract, all green throughout — and was found
  only when a human ran a simulator. No amount of Dart-VM test count, this
  phase's 171 included, is evidence against a defect of that same shape
  existing anywhere in Phase 3's new screens (the person page, the compose
  sheet, the profile screens, the three new routes). None of that surface
  has ever been exercised outside a test harness.
- No simulator was launched and no browser-automation tool was used in
  this session, per this task's explicit constraints.

---

## 5. Carried forward

Every line from `.superpowers/sdd/2026-08-30-m1-phase3-social-loop/progress.md`
marked `minor (deferred)`, and every line beginning `Ruling:`, reproduced
here with its reasoning intact rather than just its headline. Grouped by
where it was recorded. Two of these — the CelebrationListScreen privacy
test and the nickname inconsistency, both from Task 8's review — were this
task's own Part A and are now addressed; they are still reproduced below
verbatim, as recorded, with a note added rather than being silently dropped.

### Pre-flight / cross-cutting

- **Ruling (no worktree):** no worktree, same as Phase 2b. Worktrees cost
  this project twice (M0's removal nearly destroyed a ledger; 2a's
  isolation stopped the session merging its own work). Cost if wrong: no
  isolation from the shared checkout.
- **Ruling (F1 — GraphRepository not registered):** `GraphRepository` was
  not registered in `app.dart`; Phase 2b's `TimelineScreen` constructs it
  with a `?? GraphRepositoryImpl(...)` fallback, and Task 8's `ProfileCubit`
  consumes it and would find no provider. Decided: Task 8 registers
  `GraphRepository` in `app.dart` additively. Not the forbidden migration —
  `TimelineScreen`'s existing fallback is left untouched, and adding a
  provider changes no existing behaviour. Plan amended. Cost if wrong:
  `TimelineScreen` and `ProfileCubit` would hold two different instances of
  a stateless repository, which is harmless.
- **Ruling (F2 — `@protected` misuse in the guard test):** Task 3's guard
  test called `s.guard(...)` from outside the mixing class; `guard` is
  `@protected`, so the analyzer raises `invalid_use_of_protected_member`
  and Global Constraints require `fvm flutter analyze` clean. Decided: the
  test drives the mixin only through `_Subject`'s own public methods;
  `_Subject` gains a `runThrowing()` for the throw case. Plan amended. Cost
  if wrong: the task fails analyze on its first run and burns a fix round
  on something the scan could catch.
- **Ruling (F3 — a deliberately wrong `Wish.isMine` in the brief's code
  block):** Task 3's `Wish` code block contained an `isMine` getter that is
  deliberately wrong, with prose telling the implementer to delete it
  before committing — exactly the class of thing the review rubric treats
  as a defect, and an implementer transcribing the block verbatim would
  very likely ship it. Decided: remove the line; keep the warning as a
  comment in the file so the reasoning survives without the trap. Plan
  amended. Cost if wrong: none — the guidance is preserved, only the
  executable trap is gone.

### Task 1 (`person_celebrator_count`)

- **Ruling (NULL-vs-false trap, security defect found by the
  implementer):** `private.can_see_person` returned NULL, not false, for a
  caller who had not claimed a person row, because
  `p_person_id = private.my_person_id()` is NULL when `my_person_id()` is
  NULL, and `NULL or false or false` is NULL — plpgsql's `if not NULL then`
  never branches, so the brief's bare `if not private.can_see_person(...)`
  never raised 45004 for an unclaimed caller, who could count anyone's
  celebrators. Fixed with `coalesce(..., false)`. The reviewer's Minor —
  that the NULL-vs-false trap belongs in `docs/db.md` rather than only an
  inline comment — was accepted despite minors normally staying out of the
  loop, because `docs/db.md` is this repo's designated carrier of rules
  that each shipped a bug first (it already holds an identically-shaped
  lesson about `auth.uid()` being NULL under `service_role`), and the next
  person to write `if not can_see_person(...)` in imperative code
  reintroduces this exact leak otherwise. Landed at `docs/db.md:175-185`.
  Cost if wrong: one paragraph in a docs file.

### Task 2 (stop labelling suppressed numbers)

- **Ruling (spec defect: "reduced, not closed"):** renaming `"suppressed"`
  to `"skipped"` does not close the oracle. The original spec said to fold
  it into "a shared opaque status alongside other non-actionable skips",
  but this endpoint emits seven statuses each with exactly one cause, so
  `skipped` remains a 1:1 reproducible fingerprint — anyone who learns the
  mapping regains identical bulk per-phone enumeration. Decided: keep the
  change (removing the self-explanatory word is strictly better and costs
  nothing) but amend the spec to say so plainly. Verified the capability is
  dormant: `grep -rn suppress_person supabase/functions/` returns only
  comments, no caller, so no suppression can be created through the API and
  there is nothing to enumerate yet.
- **Ruling (no fix round):** the implementer built exactly what the brief
  specified and no better implementation exists at this scope — every
  other status is deliberately actionable (`invalid_phone`/`invalid_name`
  name the contact so the user can fix it), so there is no honest bucket to
  merge `skipped` into. A real fix is rate-limiting, requiring numbers to
  plausibly come from the caller's own address book, or dropping per-phone
  outcomes for skips — and the last collides with the
  `results.length == contacts.length` contract the import screen zips
  against. Cost if wrong: if a client-reachable suppression path ships
  before this is properly closed, the bulk oracle is live again.
- Minor (deferred): the new inline comment at `index.ts:189-196` nearly
  restates the module header at `index.ts:4-7`.

### Task 3 (re-entrancy guard, occasion rule, `Wish` model)

- Minor (deferred): no `test/models/wish_test.dart`, so `Wish.fromRow`'s
  casts are unverified. Outside the brief's file list, not a missed
  requirement — Task 5's contract tests exercise `fromRow` against real
  rows.

### Task 5 (wish repository)

- **Ruling (dedicated phone number, cross-task defect):** the original
  dispatch told this suite to reuse `+919999000006` as its second identity
  — the number `graph_repository_test.dart` already holds. `flutter test`
  runs test files concurrently, and each file's `OtpSendThrottle` only
  serialises sends within its own process, so two suites sharing a number
  trips GoTrue's real cross-process 5s rate limit. Decided: fix it properly
  with a new number (`+919999000011`) rather than accepting
  `--concurrency=1`, which is a flag every future invocation must remember
  and forgetting it reproduces a confusing failure in an untouched file —
  the same reasoning that rejected it in Phase 2b.
- **Ruling (relaxing the config.toml constraint):** relaxed the "only Task
  1 edits config.toml" constraint for this one line, because the
  constraint now blocked a genuine fix and holding it would knowingly leave
  a flaky suite behind. Still in force for every other task. Required the
  implementer to re-verify `enable_confirmations = true` and paste the awk
  output. Cost if wrong: one more local-only test number in a file never
  applied to a hosted project, plus one more chance to disturb the
  account-takeover guard — mitigated by the mandatory re-check.

### Task 6 (person page + compose sheet)

- **Ruling (not a fix round — `?? GraphRepositoryImpl` fallback is
  load-bearing):** the controller's own dispatch had incorrectly told the
  implementer `GraphRepository` was "already registered in app.dart" — it
  was not; registering it was Task 8's job. So `person_screen.dart`'s
  fallback constructor is currently load-bearing, not the forbidden
  optional pattern. Decided: the fallback stays until Task 8 (which already
  registers `GraphRepository`) also deletes it and switches to
  `context.read`. `TimelineScreen`'s own fallback stays untouched —
  migrating Phase 2b code is out of scope. Cost if wrong: if Task 8
  forgets, one Phase 3 screen keeps a pattern the phase forbids, and the
  final review will catch it. (Resolved: Task 8 did delete this fallback,
  verified in its own entry below.)
- **Ruling (fix it in Task 7 — postWish's combined try/catch):** postWish's
  single try/catch wraps both the write and the post-success reload. If
  `post()` succeeds but `wishesFor()` then throws, the user is told "that
  wish could not be posted" for a wish that was posted, and a retry
  double-posts. Pre-existing in the original implementation, not one of the
  findings sent for fixing in Task 6's own round, so ruled to be fixed in
  Task 7, which touches this feature area anyway. Cost if wrong: a user
  retries a successful post and the wall shows it twice. (Resolved: landed
  in Task 7, commit `40981b1`.)
- Minor (deferred): month names in `person_screen.dart:164-167` are
  hardcoded rather than `AppStrings` constants — the only place in the app
  rendering month names as body text, so there is no existing precedent to
  follow.
- Deferred (not marked minor, kept here for completeness): no router-level
  test harness exists in this codebase, so the router-match guard fix in
  this task is unproven by any test. Pre-existing gap, its own task.

### Task 7 (profile repository)

- **Ruling (dedicated phone number, the exact same mistake repeated):** the
  controller assigned `+919999000006` as this suite's second identity — the
  number `graph_repository_test.dart` owns — for the second time, despite
  Task 5 hitting this exact collision on this exact number and the plan
  having been amended to say "a second identity needs its own number too."
  Decided: dedicated number `+919999000012`, and delete the retry-with-
  backoff wrapper the implementer had built to absorb the collision the
  controller should never have caused. Relaxed the config.toml constraint
  for one line again, with the same mandatory `enable_confirmations`
  re-check. Cost if wrong: one more local-only test number.
- Minor (deferred): assertion 4/5 timeouts are 90s, left over from the
  retry era; generous rather than broken.

### Task 8 (profile screens)

- **Ruling (fold the privacy test into Task 9 rather than deferring it):**
  `CelebrationListScreen` has no widget test for the navigate/don't-
  navigate split. The reviewer rated it Minor because the code is currently
  correct, but agreed with the implementer that "structurally enforced but
  untested" is inadequate for a privacy boundary — the whole guarantee
  reduces to one untested boolean default plus one untested call site
  passing `true`. A future refactor merging the two routes, or flipping the
  default while adding a third caller, would compile and analyze clean
  while making Celebrates rows navigate into pages the viewer cannot see.
  Cost if wrong: one small test file. **Addressed in this task** — see the
  ledger header above and `test/features/profile/celebration_list_screen_test.dart`.
- **Ruling (also fix the nickname inconsistency):** the original brief said
  the Celebrating list takes "a list of Person", so it renders
  `person.displayName` while `TimelineScreen` renders the nickname-aware
  `Celebration.label` for the same edges — a spec defect, not an
  implementer deviation. A user who nicknamed someone sees the nickname in
  one place and the raw contact name in the other. Cost if wrong: the
  Celebrates list has no nickname concept, so only the Celebrating list
  changes. **Addressed in this task** — see the ledger header above and
  `CelebrationListScreen.peopleFromCelebrations()`.
- Minor (deferred): `ProfileCubit.load()` awaits its four fetches
  sequentially rather than via `Future.wait` — correct, just slower than
  necessary.

---

## 6. The suppression oracle: reduced, not closed

Task 2 removed the literal string `"suppressed"` from `add_celebrations`'
HTTP response, replacing it with the same generic `"skipped"` status used
for other non-actionable outcomes. This is a real improvement — the
self-explanatory label is gone — but it does **not** close the underlying
oracle, and this phase's own review said so at the time (see Task 2's entry
above): the endpoint emits seven statuses and each has exactly one cause,
so `skipped` remains a 1:1 reproducible fingerprint for "this number is
suppressed." Anyone who learns the mapping regains identical bulk
per-phone enumeration to what `"suppressed"` gave them directly.

It is dormant only because there is no client-reachable path to create a
suppression: `grep -rn suppress_person supabase/functions/` returns only
comments (`delete_account`'s comment names suppression as a planned future
request type), never a caller. **It reopens in full the moment any
client-reachable path to create a suppression ships** — at that point,
`skipped` must either be folded into a broader bucket that also has other
genuine contributors, or the per-phone status vocabulary must otherwise
stop being a perfect proxy for "this specific number is suppressed." This
is unchanged from Task 2's own assessment; Task 9 re-verified the grep
result above and found nothing has changed.

---

## Suite size at phase close

28 pgTAP files / 267 assertions · 6 Deno tests · 131 non-contract + 40
contract Flutter tests (171 total) · `flutter analyze` clean · all cold
from `supabase db reset`, verified in this session at HEAD `89b1d84`.

Per Step 5 of this task's brief: **this branch is not merged.** That
decision belongs to the human.
