# SDD ledger — plan: docs/superpowers/plans/2026-08-29-m1-phase2b-flutter-app.md

Spec: docs/superpowers/specs/2026-08-29-m1-phase2b-flutter-app-design.md
Branch: `m1-phase2b-flutter-app`, in the main checkout (no worktree — spec §3,
approved by Sachin; worktrees cost this project twice before: M0's removal
nearly destroyed the execution ledger, and Phase 2a's isolation stopped that
session merging its own work).
Controller's running notes: `.superpowers/sdd/2026-08-29-m1-phase2b-flutter-app/progress.md`

This is Task 14, the phase close. All 13 implementation tasks are complete
and individually reviewed (see progress.md for the full per-task record).
This document is the cold-verification record and the carry-forward manifest.

---

## 1. Final verification numbers (Task 14, Step 1)

All commands run from a cold `supabase db reset`, on branch
`m1-phase2b-flutter-app` at HEAD `56446e0`, with the local Supabase stack
already up (`supabase start`), using FVM Flutter 3.35.2 / Dart 3.9.0 and
Supabase CLI 2.78.1.

| Command | Result |
|---|---|
| `supabase db reset && supabase test db` | **27 files / 261 assertions, `Result: PASS`** — matches expectation |
| `supabase functions serve --no-verify-jwt &` then `./supabase/functions/test.sh` | **6 passed, 0 failed** (Deno) |
| `fvm flutter analyze` | **`No issues found! (ran in 1.9s)`** |
| `fvm flutter test --exclude-tags=contract` | **72 passing** — matches expectation |
| `fvm flutter test test/repositories --dart-define=SUPABASE_ANON_KEY=...` | **24 passing** — matches expectation |

All five numbers match the brief's stated expectations exactly. No
discrepancy to report for Step 1.

Detail:

- `supabase db reset` completed cleanly, applying all 28 migrations
  (20260822000001 through 20260829000001) and the seed script, with no
  errors other than an expected idempotent-extension notice.
- `supabase test db` output ended: `All tests successful. Files=27,
  Tests=261 ... Result: PASS`.
- The Deno suite was run with `supabase functions serve --no-verify-jwt`
  specifically (not the brief's original bare `supabase functions serve &`)
  per the task instructions here and per Task 2's ruling recorded in
  progress.md: `config.toml` carries no `[functions]` block, so every
  function serves at `verify_jwt = true` by default, and an unauthenticated
  request is rejected by the gateway before `add_celebrations`' own 401
  guard is ever reached. `--no-verify-jwt` is required to test the
  *handler's* guard rather than the gateway's. All 6 Deno tests passed,
  including "a suppressed number is reported as a bare skip, never named as
  a failure" and "rejects a request with no Authorization header".
- `fvm flutter analyze` reported `No issues found!` against the full
  `lib/` and `test/` tree.
- `fvm flutter test --exclude-tags=contract` printed `All tests passed!`
  ending at `+72`.
- `fvm flutter test test/repositories --dart-define=SUPABASE_ANON_KEY=...`
  (anon key pulled fresh from `supabase status -o json` after the reset)
  printed `All tests passed!` ending at `+24`, exercising
  `auth_repository_test.dart`, `graph_repository_test.dart`,
  `contacts_repository_test.dart` and `settings_repository_test.dart`
  concurrently against the freshly-reset local stack — each suite using its
  own dedicated phone number per the one-number-per-suite convention
  (auth 001/002, contacts 003, graph 004+006, settings 005), so no
  cross-suite interference occurred.

Total suite size at phase close: 27 pgTAP files / 261 assertions, 6 Deno
tests, 72 non-contract + 24 contract Flutter tests (96 Flutter tests total).

---

## 2. Config guard (Task 14, Step 2)

```
$ grep -n -A1 'enable_confirmations' supabase/config.toml
209:enable_confirmations = false
210-# If enabled, users will need to reauthenticate or have logged in recently to change their password.
--
252:enable_confirmations = true
253-# Template for sending OTP to users
```

Confirmed by section header:

```
$ grep -n '^\[auth' supabase/config.toml
...
202:[auth.email]
240:[auth.sms]
...
```

Line 209 (`false`) is under `[auth.email]` (starts line 202) — unrelated,
correct as `false`. Line 252 (`true`) is under `[auth.sms]` (starts line
240) — **this is the guard**, and it still reads `true`. This is the fix for
a reproduced total-account-takeover bug from Phase 2a (Ruling R13, recorded
in `docs/superpowers/execution/2026-08-27-m1-phase2a-ledger.md`): with
`enable_confirmations = false`, GoTrue runs with `SMS_AUTOCONFIRM=true`, and
`PUT /auth/v1/user {"phone": ...}` silently rewrites and confirms a session's
phone number with no OTP at all, which let an attacker point their session
at an unclaimed victim's number and claim their person row outright. It is
guarded by no test and no CI. `supabase init` or a CLI upgrade rewrites this
file, so this line must be re-checked by hand at every future phase close
until it is guarded some other way.

---

## 3. Per-task commit range

Derived from `git log --oneline main..HEAD` (32 commits, `main` at
`5f8afa4`, HEAD at `56446e0`).

| Task | Range | Commits |
|---|---|---|
| (design + plan, pre-task) | `5f8afa4..437ab39` | `ec1a0c9`, `437ab39` |
| 1 — birthday-edit RPC | `d9fb345..40bc1ab` | `d9fb345`, `40bc1ab` |
| 2 — `add_celebrations` Deno tests | `828a746..1ad6ea0` | `828a746`, `032070e`, `08b3f10`, `1ad6ea0` |
| 3 — Flutter scaffold, `api/` layer | `1ad6ea0..d14a074` | `d14a074` |
| 4 — models | `d14a074..7ea70b5` | `7ea70b5` |
| 5 — auth/identity repository | `7ea70b5..fbef90a` | `e7747ed`, `af4cdbc`, `fbef90a` |
| 6 — router / onboarding guard | `fbef90a..c63869c` | `c63869c` |
| 7 — phone entry + OTP | `c63869c..a134599` | `91d54e4`, `e71c4da`, `907aeea`, `a134599` |
| 8 — profile setup | `aa7d48b..13ad508` | `aa7d48b`, `12856d8`, `13ad508` |
| 9 — contacts device read / normalisation / commit | `13ad508..32edcb6` | `32edcb6` (plus follow-on plan amendments `59dd4f9`, `7ef3750`) |
| 10 — import disclosure/pick/fill/summary | `32edcb6..5684aca` | `41fca06`, `5684aca` |
| 11 — graph reads + row actions | `5684aca..e4a5ac3` | `08fedc4`, `e4a5ac3` |
| 12 — timeline | `e4a5ac3..464528c` | `464528c` |
| 13 — settings | `5bfc962..b29b961` | `5bfc962`, `b29b961` |
| 14 — phase close (ATS fix + this ledger) | `b29b961..HEAD` | `56446e0` (ATS fix), this ledger's commit |

`main..HEAD` = `5f8afa4aa7bd..56446e0fde17`, 32 commits ahead, 0 behind at
time of writing (branch runs directly off `main`, not a worktree — see the
brief's Step 5, deliberately out of scope for this session).

---

## 4. Not verified

**No end-to-end manual run of the app was performed in this phase.** Task
14 Step 3 (sign in with `+919999000001` / `123456`, complete setup, import,
timeline, confirm the disclosure screen precedes the OS contacts prompt) was
explicitly deferred by the user and was **not** executed in this session —
no simulator was launched, no browser-automation tool was used.

Concretely, this means:

- **Onboarding, import, and settings have never been exercised against a
  running app.** Every one of the 96 Flutter tests (72 non-contract + 24
  contract) runs on the **Dart VM**, not on a device or simulator — none of
  them boot `main.dart`, mount `App`, or drive `GoRouter` end to end inside
  a real iOS/Android runtime.
- One attempted run did happen mid-phase (recorded in progress.md,
  "Task 14: user ran the simulator and reported 'simulator succeeded, auth
  failed'"), and it surfaced a real, previously-undetected defect: iOS App
  Transport Security silently blocked every cleartext request to the local
  Supabase stack, because `ios/Runner/Info.plist` had no
  `NSAppTransportSecurity` key at all. Every one of the 96 Dart-VM tests
  passed throughout, because none of them go through iOS's network stack.
  This is fixed in commit `56446e0` (`NSAllowsLocalNetworking`, deliberately
  not `NSAllowsArbitraryLoads` — see §5 below), but the OTP round trip
  itself (dummy code `123456` end to end through a live simulator) was
  never subsequently re-confirmed once the fix landed, because the user
  asked to park verification at that point.
- **This is exactly the failure class that let the ATS defect survive
  96 passing tests.** Another defect of that same class — something that is
  invisible to a Dart-VM test harness and only manifests when the real OS
  network/permission/lifecycle stack is involved — could still be present
  anywhere in onboarding, import, or settings. This is **not** a soft
  residual risk; it is the single largest known gap this phase is closing
  with. It must be the first thing Phase 2c does: a real manual (or
  device-driven, non-browser-automated) walkthrough of sign-in → setup →
  import → timeline → settings, on an actual simulator or device.

---

## 5. Carried into Phase 2c and Phase 3

Every `minor (deferred)` line, every line beginning `Ruling:`, and the
Task 10 residual privacy risk recorded in progress.md, grouped by task.
Reasoning is preserved verbatim in substance, not just the headline.

### Cross-cutting / pre-flight rulings (apply before Task 1 began)

- **No worktree.** Ruling: this phase runs on a branch in the main checkout
  rather than a worktree — the spec's §3 decision, approved by Sachin.
  Worktrees cost this project twice before: M0's removal nearly destroyed
  the execution ledger, and Phase 2a's isolation stopped that session
  merging its own work. Cost if wrong: no isolation from the shared
  checkout; mitigated by the branch and by `main` being 2 commits behind at
  the start.
- **F1 (Task 2 test/DB mismatch).** Task 2's `count invariant` test expected
  `self` for the caller's own number, but `private.add_celebration`'s
  self-guard only fires once the person row is claimed or carries the
  caller's phone hash — a signed-in-but-unclaimed user got `added`, and
  `claim_person` deletes the self-edge retroactively. Ruling: `signedInUser()`
  must call `claim_profile` after verifying OTP so the caller has a person
  row and `self` is reachable. Plan text amended. Cost if wrong: the
  assertion would have failed on first run, one cheap fix round, but would
  have looked like an implementer error rather than a plan defect.
- **F2 (Task 6 router placeholders).** Task 6's `app_router.dart` referenced
  five screen classes with no imports or stubs. Ruling: Task 6 defines the
  five as private placeholder widgets inside `app_router.dart`; each later
  screen task deletes its placeholder and adds the real import. Plan
  amended. Cost if wrong: Task 6 would not compile, blocking Tasks 7–13.
- **F3 (Task 4 column-name literal).** Task 4's `Person.fromRow` read the
  literal `'profile_id'`, contradicting the plan's own claim that
  `ApiParams` is the single source for column names. Ruling: add
  `ApiParams.profileId` in Task 3 and use it. Plan amended. Cost if wrong:
  cosmetic only.

### Task 1 (birthday-edit RPC)

- Minor (deferred): `rpc_update_person_birthday` unconditionally sets
  `birth_year` from `p_birth_year` (default null), so a month/day-only call
  nulls an existing year. Correct as specified — Task 11's
  `GraphRepository.updateBirthday` takes a whole `Birthday` (which always
  carries a year), so the interface already prevents a partial call from
  reaching the RPC. Still worth knowing for any future direct caller of the
  RPC.
- Minor (deferred): the revoke list includes `anon` redundantly (revoking
  from `public` already strips it). Harmless, brief-verbatim.

### Task 2 (`add_celebrations` Deno tests)

- Ruling (brief defect #1): `supabase functions serve --no-verify-jwt=false`
  was the wrong invocation. `config.toml` has no `[functions]` block, so all
  five functions run at `verify_jwt = true` by default and the gateway
  answers an unauthenticated request before the handler's own `if (!auth)`
  guard is reachable. Decided: serve with `--no-verify-jwt`, and understand
  the 401 test as covering the *handler's* guard — the gateway's own 401 in
  the default config is an additive layer, not the thing under test. This is
  parent carry-forward item #3 from the Phase 2a ledger surfacing early;
  **Phase 2c still owns the decision of whether `verify_jwt` stays on for
  `drain_reminders`.**
- Ruling (brief defect #2): trial 1 claimed two tests fail on a broken
  build; only the count-invariant one actually does, since the
  repeat-occurrence test asserts on counters and `person_id`, not the status
  string. Plan amended; expectation-only, no code cost.
- Ruling: the `suppressed` review finding stands and is not disproportionate,
  even though pgTAP already proves the DB half
  (`21_add_celebration.test.sql:53-69`) — the untested sliver was the HTTP
  mapping null → `"suppressed"`/skipped, and Task 10's privacy rule (a
  suppressed number must be a bare skip, never named) depends on exactly
  that mapping regressing safely. Remedy: seed the suppression via a direct
  Postgres connection, since `private.suppress_person` has zero callers over
  HTTP and suppression is otherwise unreachable from the test suite. Cost if
  wrong: one extra dependency and a second connection mode in an otherwise
  pure-HTTP suite.
- Ruling: two Minor findings stayed deferred per the skill's default, except
  the cleanup-comment Minor, which shared a comment block with an Important
  fix and would otherwise have been left half-corrected.
- Minor (deferred): the suppression test connects as the `postgres`
  superuser, so it would not work unmodified against a remote `DB_URL`.
- Minor (deferred): Deno is not preinstalled — a portability gap for CI.

### Task 3 (Flutter scaffold, `api/` layer)

- Ruling RESOLVED (publishableKey): `Supabase.initialize(anonKey:)` is
  deprecated in the resolved `supabase_flutter` 2.17.2 in favour of
  `publishableKey`. Verified directly against the library source
  (`supabase.dart:80-102` coalesces `publishableKey ?? anonKey` into one
  effective key before use; `api_key.dart:23-38` only warns, and only for
  keys starting with `sb_`, which a legacy anon JWT does not) — the
  substitution is correct, not a deprecation-silencer masking a real
  incompatibility. No action; verified against primary source, not assumed.
- Minor (deferred): `ApiClient.anonKey` field name vs. the `publishableKey`
  parameter it now feeds — cosmetic naming drift, no interface depends on
  it.
- Minor (deferred): `ApiClient.anonKey` has no `defaultValue`, so a missing
  `--dart-define` resolves to `''` and `Supabase.initialize` accepts it
  silently; the failure surfaces later as an opaque 401 with nothing
  pointing at the missing define. Inherited from the plan, not
  implementer-introduced. **Worth fixing before Phase 2c does its first
  real device run** — this is exactly the kind of failure mode Phase 2c's
  first task (§4 above) needs to rule out quickly rather than misdiagnose.

### Task 5 (auth/identity repository)

- Ruling (plan defect, cross-task): the verbatim contract test could not
  reach real Supabase at all without three non-obvious fixes —
  `HttpOverrides.global = null` (`AutomatedTestWidgetsFlutterBinding` fakes
  every `dart:io` request with a 400 stub otherwise), an in-memory
  `SharedPreferencesStorePlatform`, and accounting for the OTP send-cooldown
  (`max_frequency = 5s`). The first is the dangerous one: without it, a
  "contract test" would silently talk to nothing while appearing to pass —
  which defeats the entire reason the spec chose real Supabase over fakes.
  Extracted to `test/support/contract_test_harness.dart`, imported by every
  later contract suite (Tasks 9, 11, 13).
- Ruling: `deleteAccount` semantics — once the Edge Function succeeds, the
  account is gone, so a failing `signOut` afterward must **not** be reported
  as failure; log it and force a local sign-out instead, or the user retries
  against an already-deleted account. Cost if wrong: a device could retain a
  stale local session for a deleted account, which is strictly better than
  reporting a completed deletion as failed.
- Minor (deferred): `claimProfile`'s `res.data as Map` cast degrades to a
  generic `ServerFailure` on a malformed 2xx body — diagnostics lost, but
  nothing leaks.
- Minor (deferred): the taken-handle test leaks one `profiles` row per
  `db reset` — unfixable client-side (no service-role key available to the
  test), now honestly documented rather than hidden.
- Minor (deferred): the fresh-profile test comment calls the first delete
  "a no-op the first time", which is imprecise — it always performs a real
  delete.

### Task 6 (router / onboarding guard)

- Ruling (controller process defect): a dispatch that says "actually run
  the app" without naming a device target let an implementer choose
  `flutter run -d chrome`, then try to drive a *second* Chrome via a
  Playwright MCP tool, which raised a browser-access permission dialog on
  the user's machine and hung for 30 minutes. No exposure occurred (the
  dialog was never granted), but **every future instruction to run the app
  must name the device target and forbid browser-automation tooling.** This
  is the direct precedent for why this Task 14 session was told not to
  touch a simulator or any browser-automation tool at all.
- Ruling: the review's finding about a missing `/otp` route was correct
  about the text and wrong about the remedy — the router stands as written.
  Task 7 reaches `OtpScreen` via `Navigator.push` + `BlocProvider.value`
  carrying the live `PhoneCubit`, so a URL-addressable `/otp` would render a
  screen with no phone number in memory — broken by construction. Bouncing
  `#/otp` to `/phone` is correct. **If a future milestone needs a
  deep-linkable OTP step (M3's tokenized confirm link is a deep link, but a
  different screen), the route and a signed-out allow-list entry must be
  added then** — cheap and additive, not yet needed.
- Minor (deferred): the placeholder-shadowing comment claims a leftover
  placeholder would "silently shadow" a real screen; in Dart it is actually
  a compile-time duplicate declaration — mis-described, but the protection
  is stronger than claimed.
- Minor (deferred): `onSignedIn()`/`onProfileCompleted()` have no dedicated
  test; both are one-line delegations to `load()`, which is covered.

### Task 7 (phone entry + OTP)

- Ruling: fixed the wrong-code double-push bug with
  `ModalRoute.of(context)?.isCurrent`, not `pushReplacement` (OtpScreen has
  a back button; the user must be able to return and fix the number) and
  not a one-shot bool (needs resetting on pop; getting that wrong
  reintroduces the bug inverted). `isCurrent` is self-resetting. Cost if
  wrong: would only matter if some future route is pushed over PhoneScreen
  non-modally — no such route exists in this milestone.
- Ruling: guard `submitCode` re-entrancy in the **Cubit** (return early when
  state is `PhoneVerifying`), not the widget — the cubit holds the truth
  about what is in flight; a widget-only guard leaves the public API unsafe
  for the next caller. **This pattern was promoted and repeated in Tasks 8
  and 10** and should be the default for any future cubit with an
  in-flight async action.
- Minor (deferred): resend cooldown restarts even when `resend()` fails.
- Minor (deferred): one-frame blank subtitle on `PhoneVerified`.
- Minor (deferred, pre-existing, not introduced by the fix): if the user
  pops back to `PhoneScreen` while a `submitCode` is still in flight and it
  later resolves to a wrong-code `PhoneCodeSent`, the guard permits a fresh
  push, re-opening a screen the user had just backed out of. Identical
  before and after the isCurrent fix.
- Global Constraint promoted from this task's fix round: pass
  `skipOffstage: false` whenever counting screens in a widget test — Dart's
  `find.byType` defaults to `skipOffstage: true`, and `Navigator` marks a
  fully covered route offstage, so a buried duplicate screen is invisible to
  a naive assertion. Applies to any future widget test asserting screen
  count across a navigation boundary.

### Task 8 (profile setup)

- Ruling: the implementer's concern that `profile_setup_screen.dart` has no
  widget test is not a gap — the M1 design spec scopes widget tests to
  "the three riskiest screens only: OTP entry, import selection, timeline
  grouping." Profile setup is deliberately excluded. Cost if wrong: this
  screen's wiring is verified only by static analysis until a real manual
  run exercises it end to end — **which is precisely the gap recorded in
  §4 above and still open.**
- Ruling: swept a Minor (no synchronous re-entrancy guard in
  `ProfileSetupCubit.submit()`) into the fix round despite the skill's
  default of deferring minors, because Task 7 had just established the
  Cubit-level re-entrancy-guard convention in the same feature folder, and
  two cubits guarding differently in one folder is worse than either choice
  alone.
- Ruling: did not require a test for the `mounted`-guard fix
  (`setState` after an awaited `showDatePicker` with no `mounted` check).
  Forcing a dispose beneath an open dialog would prove more about the test
  harness than the screen, and a test that passes either way is worthless
  here. The fix is inspection-verified only. Cost if wrong: a regression
  here would not be caught automatically — it is a two-line guard in one
  method.
- Minor (deferred, pre-existing in the plan): `ProfileSetupCubit.submit()`
  has no catch-all for exceptions that are neither `ServerFailure` nor
  `AppFailure` — one would leave the cubit in `ProfileSetupSaving` forever
  with the button disabled. Currently inert: `AuthRepositoryImpl
  .completeProfile` wraps every call in try/catch and throws `mapError(e)`,
  which has an unconditional fallback returning `ServerFailure`, so no raw
  exception can currently escape the repository — **but the guarantee lives
  in a different file and could drift.** Flagged for the whole-branch
  review; carry forward to Phase 2c/3 as something to re-check if
  `AuthRepositoryImpl` or `mapError` changes.

### Task 9 (contacts device read / normalisation / commit)

- Ruling (cross-task, ratified as a Global Constraint): `flutter test` runs
  test *files* concurrently, so any contract suite reusing a phone number
  already in use by another suite produces spurious failures in files it
  never touched. Fixed by assigning one phone number per contract-test
  suite: auth 001+002 (its taken-handle test needs two), contacts 003,
  graph 004 (+006, added later — see Task 11), settings 005. This is the
  single sanctioned `config.toml` edit of this phase; **any Phase 2c/3
  contract suite needing its own signed-in identity must claim the next
  free test number in this same scheme, not reuse an existing one**, and
  must re-verify `enable_confirmations = true` still holds before
  committing. Rejected `-j 1` as an alternative fix because it is a runner
  flag every future invocation must remember, and forgetting it reproduces
  the exact confusing symptom (a failure in an unrelated file) that this
  ruling exists to prevent.

### Task 10 (import disclosure/pick/fill/summary)

- Ruling: deferred the "retry resends everything" finding despite its
  Minor-to-Important rating. The server is idempotent, so nothing
  duplicates or is lost server-side; the visible cost is a confusing
  "already in your list" count. A correct fix requires deciding how to
  merge two `ImportSummary`s so earlier successes are not lost from the
  displayed count, which is an interface change beyond this task's scope.
  **Flagged to the final review; still open for Phase 2c/3 — a user who
  retries an import currently sees inflated duplicate counts, not data
  loss.**
- Minor (deferred): the summary shows a raw E.164 number instead of a name
  on `invalid_phone`/`invalid_name` lines, on exactly the line whose whole
  purpose is to let the user go fix that contact. The pick/fill screens
  already build a phone→name map, so a low-cost fix exists if picked up.
- Minor (deferred): `ContactsRepositoryImpl` is newed up directly inside the
  import disclosure screen, while `AuthRepository` is provided through
  `RepositoryProvider` (`app.dart:26-27`). This is a **latent hard crash**
  for any future widget test that mounts that screen, since
  `ApiClient.instance` throws when uninitialised. `app.dart` was outside
  Task 10's file list, so the fix was deliberately deferred rather than
  made as a side effect. **Flagged to the final review; still open** — the
  architectural fix (route `ContactsRepository` through the same
  `RepositoryProvider` pattern as `AuthRepository`) should happen in
  Phase 2c/3 before any widget test targets that screen.
- Minor (deferred): dual `isCurrent` guards on this screen are correct but
  untested.
- Minor (deferred): `Log.error` is called as `(message, e)` with no
  `StackTrace` argument, matching existing call sites elsewhere in the
  codebase — a broader logging-hygiene item, not specific to this task.
- **Residual privacy risk (raised by the reviewer, not fixable inside this
  task, explicitly to be carried to the spec):** nothing except
  `suppressed` contributes to `ImportSummary.skipped`, so "N skipped" is
  numerically identical to "N suppressed." A one-contact test import
  therefore reveals the suppression regardless of how the count is
  labelled. This is inherent to Task 9's model (the alternative —
  falsifying the counts — is worse) and belongs in the M1 spec's open
  questions, not as a code fix in this task. **Carried forward
  unresolved: Phase 2c/3 should decide whether this is an acceptable
  product tradeoff or needs a different counting scheme (e.g. folding
  suppressed into a broader "skipped for other reasons" bucket that always
  has at least one other contributor, or simply documenting the leak as
  accepted).**

### Task 11 (graph reads + row actions)

- Ruling: the implementer added `+919999000006` as a second test identity
  inside the graph contract suite, reporting it as a gap in the plan's
  phone-number table rather than quietly taking a number. Correct: SQLSTATE
  45002 needs a caller holding no edge, while 45003 needs a person who has
  already claimed a profile, and one number cannot play both parts. Plan
  table corrected. Config now carries test numbers 001–006 (six total)
  going into Phase 2c/3 — the next new contract suite is number 007, per
  Task 9's ruling above.
- Minor (deferred): no explicit double-delete test for `stopCelebrating`;
  it is idempotent by construction (a Postgrest `DELETE` matching zero rows
  succeeds), so untested but not fragile.

### Task 12 (timeline)

- Ruling (state shape): kept the nullable `Map<TimelineGroup?, ...>` map key
  rather than adding a fifth `TimelineGroup` enum member for
  no-birthday-yet celebrations. `Birthday.groupFrom` returns non-nullable,
  so a fifth enum member could never actually be produced by it, and every
  future consumer of `TimelineGroup` would carry an unreachable case
  forever. Dart 3's exhaustive switch already forces a `null =>` arm
  wherever the key is consumed, so no safety is traded away. **Phase 2c/3
  builds on this state shape — changing it later touches the Cubit, the
  screen, and their tests, but nothing outside the timeline feature.**
- Minor (deferred, most substantive of Task 12's four): `_pickBirthday`/
  `_editNickname` conversion logic (`DateTime` → `Birthday`, nickname
  trim-to-null) has **zero coverage at any level** — the Cubit tests call
  the underlying methods directly with literal values, bypassing the
  conversion entirely. A transposed month/day in this conversion would not
  be caught by any current test. Flagged to the final review; **still open,
  worth a Phase 2c/3 test.**
- Minor (deferred): ordering within a timeline group is not stable for two
  people sharing a birthday (`List.sort` is documented non-stable in Dart).
  Cosmetic jitter only.
- Minor (deferred): `editBirthday`/`editNickname` are called post-await
  without confirming the owning `BlocProvider` is still alive — narrower
  than Task 8's disposal bug, since no `context` or `setState` is touched
  directly, but the same class of hazard.
- Minor (deferred): `timelineNoBirthdayYet` does double duty as a section
  header; a dedicated header string would read better. Cosmetic.

### Task 13 (settings)

- Minor (deferred): `api_params.dart` was modified outside the brief's
  stated file list (adds `ApiParams.token`) — justified, since it
  centralises a column name per the project's own `ApiParams` convention,
  but worth noting as a deviation for anyone auditing file-list adherence.
- Minor (deferred): the delete-confirmation dialog's confirm button is
  distinguished only by font weight, not by a hazard colour. No existing
  destructive-dialog convention exists elsewhere in the codebase to match
  or break — worth establishing one convention in Phase 2c/3 if more
  destructive actions are added.

### Task 14 (this phase close)

- Ruling: fixed the iOS ATS defect with `NSAllowsLocalNetworking`, not
  `NSAllowsArbitraryLoads`. The former relaxes cleartext only for
  local-network destinations; the latter disables ATS globally and would
  ship a real security regression for a development convenience. Safe to
  keep in production, where a hosted Supabase is HTTPS anyway, so no
  build-flavour split is needed.
- Ruling: the user stopped the Step 3 manual run-through and asked to park
  OTP verification for later. Phase 2b therefore closes without an
  end-to-end manual sign-in walkthrough — see §4 above for the full
  consequence. **This is the single most important item this phase carries
  forward: Phase 2c's first task should be the deferred manual/device
  walkthrough**, not new feature work, precisely because the ATS defect
  proved that class of bug is invisible to everything else in this suite.

---

## Suite size at phase close

27 pgTAP files / 261 assertions · 6 Deno tests · 72 non-contract + 24
contract Flutter tests (96 total) · `flutter analyze` clean · all cold from
`supabase db reset`, verified in this session on `56446e0`.

---

## Addendum: final whole-branch review and fix wave

Written after the ledger's first commit (`48253dc`), which predates the final review.

### The final review's verdict: do not merge as-is

Five Blocking, four Important. **Every blocker was invisible to the thirteen
task-scoped reviews**, because each lived *between* files rather than inside any
one task's diff. Three were siblings of the iOS App Transport Security defect,
sitting in the same two platform files.

| # | Finding | Why no review caught it |
|---|---|---|
| B1 | Settings entirely unreachable — nothing navigated to `/settings` | The route registration referenced the class, so the analyzer stayed clean |
| B2 | iOS lacked `NSContactsUsageDescription` → SIGABRT on import | No Dart-VM test can invoke `CNContactStore` |
| B3 | Android declared **no permissions at all**: no `READ_CONTACTS`, `INTERNET` only in debug/profile manifests, no cleartext exception | Same — platform manifests are invisible to the VM |
| B4 | Timeline and settings could render `Instance of 'ServerFailure'` to the user | Both failure paths had **no test at all** |
| B5 | `PhoneCubit.submitPhone` threw uncaught on `+09876543210` and four other inputs | The throwing path was untested; the parse-but-invalid path was not |

Fixed in `4e79373`, follow-up in `3cb0954`. Final: 84 non-contract + 24 contract
Flutter tests, 27 pgTAP files / 261 assertions, 6 Deno tests, analyzer clean.

### Two rulings the final review overturned

**1. The `suppressed` leak is an API oracle, not a UI inference.** The Task 10
ruling assessed it as "`N skipped` is numerically identical to `N suppressed`".
That framing was wrong. `add_celebrations` returns the literal string
`"suppressed"` **per phone number** in its `results` array, and the endpoint
accepts 500 arbitrary numbers per request — the caller need not have any of them
in an address book — with no rate limit configured. Any authenticated user with a
proxy can enumerate suppression status across the phone-number space in bulk.
The client's careful refusal to render it is cosmetic; the HTTP response names it.

**This must be closed before any hosted deployment.** Cheap partial fix: stop
returning the labelled status and fold `suppressed` into one opaque skip shared
with other non-actionable skips. That leaves only the count inference, which was
already accepted, and removes the oracle.

Adjacent, pre-existing, same shape: `resolve_contacts` returns `display_name` for
up to 500 arbitrary numbers per request — a name-enumeration oracle. Phase 2a's,
but it belongs in the same conversation.

**2. `config.toml`'s safety comment named the wrong mechanism.** It claimed the
test OTP numbers were safe because `supabase db push` does not apply config —
true, and irrelevant, because **`supabase config push` does exactly that**. One
`supabase link && supabase config push` would have shipped six real-format numbers
whose OTP is `123456` to hosted GoTrue, on an auth surface that has already
produced two account-takeover bugs. Corrected in `4e79373`.

Separately: `[auth.sms] enable_confirmations = true` is a load-bearing security
control guarded by nothing but a hand-check at each phase close, and
`supabase init` or a CLI upgrade rewrites that file. It deserves an automated
assertion in CI.

### The fix wave introduced one new defect, and it was caught

B1's fix made `/settings` reachable — with no way out. `context.go` replaces the
page stack, so `canPop()` is false and no back arrow renders; the only exits were
Sign out and Delete account. The same defect class the same commit fixed for
`/import`. Closed in `3cb0954`.

Process note worth keeping: this is the second time on this branch that fixing a
navigation entry point created a navigation trap. Any future `context.go` to a
top-level route needs a deliberate way back.

### Still not verified

No end-to-end run of the app was ever completed. A human ran the simulator once and
found the ATS defect; the sign-in flow was then deferred by decision. Contacts
import remains unexercised — simulators carry no address book. **Phase 2c should
begin with a physical-device run**, not with new features.

Concrete candidates a device run would catch that no VM test can, from the final
review:

1. Session restore across a cold launch — every contract suite installs an
   in-memory `SharedPreferences`, so supabase_flutter's real persistence path has
   never executed.
2. The imperative `Navigator.push` stack versus go_router's redirect, when
   `onSignedIn()` flips the target while a pageless route sits on top.
3. A real-sized address book — `readDeviceContacts` parses every number on the UI
   isolate; the fakes return three.
4. iOS 18 limited-contacts access: `requestAccess` returns granted while
   `getContacts` returns only a user-selected subset, silently.
5. Keyboard-inset overflow — `PhoneScreen` and `ImportDisclosureScreen` are plain
   `Column`s with no scroll view; VM widget tests run at 800×600 with no keyboard.
