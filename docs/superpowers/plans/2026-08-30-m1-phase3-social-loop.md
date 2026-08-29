# M1 Phase 3 — The Social Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop the milestone exists for — a reminder arrives, you tap it, you wish them, and both profiles record it.

**Architecture:** `view → cubit → repository → Supabase client`, unchanged from Phase 2b. What changes is discipline: three narrow repositories instead of one fat one, dependencies injected at `app.dart` instead of constructed in screens, and one shared re-entrancy guard instead of the five in three shapes Phase 2b accreted.

**Tech Stack:** Flutter 3.35.2 (FVM), Dart 3.9, `flutter_bloc`, `go_router`, `supabase_flutter`; Postgres 17 + pgTAP; Deno for Edge Function tests.

**Spec:** `docs/superpowers/specs/2026-08-29-m1-phase3-social-loop-design.md`

## Global Constraints

- **Flutter 3.35.2**, pinned in `.fvmrc`. Every command through `fvm` (`fvm flutter …`, `fvm dart …`). Never bare `flutter`.
- **All user-facing copy lives in `lib/core/app_strings.dart`.** No string literals in screens. Review-rejection criterion.
- **No one-off sub-widget classes.** Screens own their layout inline. A `StatefulWidget` split for controllers is fine.
- **New code follows spec §4.** Narrow repositories (SRP/ISP), injected dependencies with no `?? ConcreteImpl` fallback (DIP), the shared `ReentrancyGuard` mixin (OCP/DRY), domain rules as methods on value objects. **Existing code is NOT migrated** — do not refactor Phase 2b's cubits, screens or repositories.
- **These rules are not a licence to add layers.** No service layer between cubit and repository, no use-case classes wrapping a single repository call, no factories for one implementation.
- **`supabase/config.toml` must keep `[auth.sms] enable_confirmations = true`** (currently line 252, under `[auth.sms]`; a `false` under `[auth.email]` is unrelated and correct). It is the fix for a reproduced total-account-takeover bug and nothing tests it.
- **One phone number per contract-test suite** — `flutter test` runs files concurrently and a shared OTP identity produces failures in unrelated files. Existing: auth `+919999000001`/`002`, contacts `003`, graph `004` (+`006` as its second identity), settings `005`. **Phase 3 assigns four more, all added in Task 1 in a single edit:** person `+919999000007`, wish `+919999000008`, profile `+919999000009`, end-to-end `+919999000010`. One edit, not four — `config.toml` carries the account-takeover guard and every touch of it is a risk.
- **New `public` functions executable by `authenticated` extend the R3 allowlist** in `supabase/tests/database/11_rls_coverage.test.sql`. Missing this fails the suite from cold. New `private` functions extend `01_private.test.sql`.
- **SQLSTATE is a public API decision** — PostgREST maps it to an HTTP status. Class 45 is unassigned and in use here: `45001` self-celebration, `45002` no edge, `45003` person claimed. Phase 3 adds `45004`.
- **A green suite is not evidence.** Every new assertion must be watched to FAIL with its implementation reverted. Five tests on the Phase 2b branch passed against the exact bug they were written to catch.
- **In widget tests, `find.byType` defaults to `skipOffstage: true`.** Navigator marks a covered route offstage, so a duplicate-push bug is invisible to the obvious assertion. Pass `skipOffstage: false` whenever counting screens.
- **Contract tests must use `test/support/contract_test_harness.dart`** — call `setUpContractTestEnvironment()` as the first statement of `setUpAll`, before any Supabase client is constructed, and route OTP sends through its throttle. Never re-inline it: without it Flutter's test binding fakes every `dart:io` request with a 400 stub and a "contract test" reaches nothing.
- **Any route reached with `context.go` needs a deliberate way back.** `go` replaces the page stack, so `canPop()` is false and no back arrow renders. This has already trapped users twice on this project (`/import`, `/settings`).
- Read `docs/db.md` before touching anything in `supabase/`. It carries eleven rules that each shipped a bug first.

---

## File Structure

**Backend (Tasks 1–2)**

| File | Responsibility |
|---|---|
| `supabase/migrations/20260830000001_person_celebrator_count.sql` | The count function and its grants |
| `supabase/tests/database/27_person_celebrator_count.test.sql` | pgTAP proof of both access conditions |
| `supabase/functions/add_celebrations/index.ts` | Modified: fold `suppressed` into an opaque skip |
| `supabase/functions/add_celebrations/index.test.ts` | Modified: the assertion that currently pins the leak |
| `supabase/config.toml` | Modified: two more test OTP numbers |

**Flutter (Tasks 3–9)**

| File | Responsibility |
|---|---|
| `lib/core/reentrancy_guard.dart` | The shared `ReentrancyGuard` mixin |
| `lib/models/birthday.dart` | Modified: `occasionYear(DateTime)` |
| `lib/app.dart` | Modified: register the three new repositories |
| `lib/models/wish.dart` | A wish plus its resolved author |
| `lib/repositories/person_repository.dart` (+`_impl`) | `person()`, `celebratorCount()` |
| `lib/repositories/wish_repository.dart` (+`_impl`) | `wishesFor()`, `post()` |
| `lib/repositories/profile_repository.dart` (+`_impl`) | `stats()`, `celebrates()`, `celebrating()` |
| `lib/features/person/` | `person_cubit`, `person_state`, `person_screen`, `wish_compose_sheet` |
| `lib/features/profile/` | `profile_cubit`, `profile_state`, `profile_screen`, `celebration_list_screen` |
| `lib/router/app_router.dart` | Modified: `/person/:personId`, `/profile`, `/profile/celebrating`, `/profile/celebrates` |

Tests mirror `lib/` under `test/`, contract tests under `test/repositories/`.

---

## Task 1: The celebrator-count function

Spec §5.1. The person page shows "N people celebrate them" and **never a name** — the parent spec's original line would have exposed a third party's follower list to anyone who imported their phone number.

**Files:**
- Create: `supabase/migrations/20260830000001_person_celebrator_count.sql`
- Create: `supabase/tests/database/27_person_celebrator_count.test.sql`
- Modify: `supabase/tests/database/11_rls_coverage.test.sql` (R3 allowlist)
- Modify: `supabase/config.toml` (two test numbers)

**Interfaces:**
- Consumes: `private.can_see_person(bigint)`, `private.my_person_id()`, and the `tests.*` helpers in `supabase/seed.sql` (`as_user`, `as_anon`, `as_postgres`, `create_user`, `create_person`).
- Produces: `public.person_celebrator_count(p_person_id bigint) returns int`, raising `45004` when the caller cannot see the person. Task 4's `PersonRepositoryImpl.celebratorCount` calls it.

- [ ] **Step 1: Add the two test phone numbers**

In `supabase/config.toml`, inside the existing `[auth.sms.test_otp]` block, after `919999000006`:

```toml
919999000007 = "123456"
919999000008 = "123456"
919999000009 = "123456"
919999000010 = "123456"
```

All four at once. Later tasks in this phase consume them and **must not edit `config.toml` again** — it carries `enable_confirmations = true`, the fix for a reproduced total-account-takeover bug that nothing tests, and one edit is one chance to disturb it instead of four.

Then confirm `[auth.sms] enable_confirmations = true` is untouched:

```bash
awk '/^\[auth\./{sec=$0} /enable_confirmations/{print NR": "sec" -> "$0}' supabase/config.toml
```

Expected: `[auth.email] -> false` and `[auth.sms] -> true`.

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/database/27_person_celebrator_count.test.sql`:

```sql
begin;
select plan(6);

select tests.as_postgres();
select tests.create_user('counter');
select tests.create_user('stranger');
select tests.create_user('blocker');

create temporary table ids as
select
  (select id from public.profiles where handle = 'counter')   as counter,
  (select id from public.profiles where handle = 'stranger')  as stranger,
  (select id from public.profiles where handle = 'blocker')   as blocker,
  tests.create_person('+919999444401', 'Popular Person')      as popular;
grant select on ids to authenticated;

-- The counter celebrates Popular, so can_see_person lets them look.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select counter, popular, 'contacts' from ids;

-- Two more celebrators, neither of whom the counter can see by name.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select stranger, popular, 'contacts' from ids;
insert into public.celebrations (celebrator_profile_id, person_id, source)
select blocker, popular, 'contacts' from ids;

-- 1. The happy path: three edges point at Popular.
select tests.as_user((select counter from ids));
select is(
  public.person_celebrator_count((select popular from ids)),
  3,
  'counts every celebrator of a person the caller can see'
);

-- 2. A block in either direction removes that celebrator from the count.
--    Deliberately BOTH directions, unlike my_celebrates() which excludes only
--    celebrators the viewer blocked: this is a number shown to both parties,
--    and a blocked relationship should contribute to neither side's total.
select tests.as_postgres();
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select blocker, counter from ids;

select tests.as_user((select counter from ids));
select is(
  public.person_celebrator_count((select popular from ids)),
  2,
  'a celebrator who blocked the caller is not counted'
);

select tests.as_postgres();
delete from public.blocks;
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select counter, blocker from ids;

select tests.as_user((select counter from ids));
select is(
  public.person_celebrator_count((select popular from ids)),
  2,
  'a celebrator the caller blocked is not counted either'
);

-- 3. The visibility gate. people.id is a sequential bigint, so without this
--    anyone could walk the id space and count any user's followers.
select tests.as_user((select stranger from ids));
select lives_ok(
  $$ select public.person_celebrator_count(
       (select popular from ids)) $$,
  'a celebrator of the person can call it'
);

select tests.as_postgres();
select tests.create_user('outsider');
select tests.as_user((select id from public.profiles where handle = 'outsider'));
select throws_ok(
  $$ select public.person_celebrator_count(
       (select popular from ids)) $$,
  '45004',
  null,
  'someone with no connection to the person cannot count their celebrators'
);

-- 4. It is an authenticated door.
select tests.as_anon();
select throws_ok(
  $$ select public.person_celebrator_count(1::bigint) $$,
  '42501',
  null,
  'anon cannot execute the function'
);

select * from finish();
rollback;
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd ~/Desktop/Projects/birthday_app
supabase db reset && supabase test db
```

Expected: `27_person_celebrator_count.test.sql` fails with `function public.person_celebrator_count(bigint) does not exist`.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20260830000001_person_celebrator_count.sql`:

```sql
-- Spec 2026-08-29 §5.1. The person page shows "N people celebrate them" and
-- NEVER a name. The parent spec's original wording ("who else celebrates them")
-- would have exposed a third party's follower list to anyone who imported their
-- phone number; a count carries the same social-proof signal with a fraction of
-- the privacy surface.
--
-- security definer, so it does its own authorisation:
--
--   1. The caller must be able to see the person. people.id is a sequential
--      bigint -- without this check, walking the id space enumerates any user's
--      follower count.
--   2. A block in EITHER direction removes that celebrator from the total.
--      This is deliberately stricter than public.my_celebrates(), which excludes
--      only celebrators the viewer has blocked: that function returns identities
--      for the viewer's own list, while this one returns a number shown on a
--      third party's page. A blocked relationship should contribute to neither
--      side's total.
--
-- 45004 is the next unassigned class-45 code (45001 self-celebration,
-- 45002 no edge, 45003 person claimed). docs/db.md: SQLSTATE is a public API
-- decision because PostgREST maps it straight to an HTTP status.
create or replace function public.person_celebrator_count(p_person_id bigint)
returns int
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_count int;
begin
  if not private.can_see_person(p_person_id) then
    raise exception 'person not visible to caller'
      using errcode = '45004';
  end if;

  select count(*)::int into v_count
  from public.celebrations c
  where c.person_id = p_person_id
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_profile_id = c.celebrator_profile_id
             and b.blocked_profile_id = auth.uid())
         or (b.blocker_profile_id = auth.uid()
             and b.blocked_profile_id = c.celebrator_profile_id)
    );

  return v_count;
end;
$$;

-- R12/R16 (docs/db.md): `revoke ... from public` also strips `authenticated`,
-- which holds EXECUTE only through the PUBLIC grant. The grant back is not
-- redundant -- without it the function is unreachable by the app.
revoke execute on function public.person_celebrator_count(bigint)
  from public, anon;
grant execute on function public.person_celebrator_count(bigint)
  to authenticated;
```

- [ ] **Step 5: Add it to the R3 allowlist**

`supabase/tests/database/11_rls_coverage.test.sql` carries an allowlist of public functions executable by `authenticated`. Add `person_celebrator_count` in alphabetical position. Without this the suite is not green from cold — Task 1 of Phase 2b hit exactly this.

- [ ] **Step 6: Run the test to verify it passes**

```bash
supabase db reset && supabase test db
```

Expected: `27_person_celebrator_count.test.sql .. ok`, whole suite green from cold at **28 files** (up from 27).

- [ ] **Step 7: Prove each guard can fail**

For each, revert the guard, run `supabase db reset && supabase test db`, and confirm **that specific assertion** fails. Restore afterwards.

1. Remove the `can_see_person` check → assertion 5 (`45004`) must fail.
2. Remove the block subquery → assertions 2 and 3 must fail.
3. Remove the `revoke ... from public, anon` → assertion 6 (`42501`) must fail.

Expected: three observed failures. If any assertion passes with its guard removed, it is testing nothing and must be rewritten before continuing.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260830000001_person_celebrator_count.sql \
        supabase/tests/database/27_person_celebrator_count.test.sql \
        supabase/tests/database/11_rls_coverage.test.sql \
        supabase/config.toml
git commit -m "feat(db): count a person's celebrators without naming them

A count carries the social-proof signal the person page needs with a
fraction of the privacy surface of a follower list. Gated on
can_see_person, since people.id is a sequential bigint."
```

---

## Task 2: Close the `suppressed` oracle

Spec §5.2. Phase 2b's final review established that `add_celebrations` returns the literal string `"suppressed"` per phone number, and that the endpoint accepts 500 arbitrary numbers per request with no rate limit and no requirement that the caller holds them in an address book. That is a bulk oracle for "did this person ask to be forgotten" over the phone-number space. The client's refusal to render the label is cosmetic; the HTTP response names it.

**Files:**
- Modify: `supabase/functions/add_celebrations/index.ts`
- Modify: `supabase/functions/add_celebrations/index.test.ts`
- Modify: `lib/models/import_outcome.dart`
- Modify: `lib/features/contacts_import/import_summary_screen.dart` (comments only)

**Interfaces:**
- Produces: the response `results[].status` vocabulary loses `suppressed` and gains nothing — suppressed rows now report the same opaque status as other non-actionable skips. The aggregate `skipped` count is unchanged.

- [ ] **Step 1: Change the Edge Function**

In `supabase/functions/add_celebrations/index.ts`, the `data === null` branch currently records `status: "suppressed"`. Change it to `status: "skipped"`, and replace the comment above it with the reason:

```typescript
    // A suppressed number is reported with the same opaque status as any other
    // non-actionable skip, NOT as "suppressed". Returning the labelled status
    // made this endpoint an oracle: it accepts 500 arbitrary numbers per
    // request with no rate limit and no requirement that the caller holds them
    // in an address book, so a labelled response let anyone enumerate who had
    // asked to be forgotten. The aggregate `skipped` count is unchanged, so the
    // count inference accepted in Phase 2b remains -- but the per-phone oracle
    // is gone.
    if (data === null) {
      record({ person_id: null, status: "skipped" });
      skipped++;
      continue;
    }
```

- [ ] **Step 2: Update the Deno test that pins the leak**

`index.test.ts` currently asserts `body.results[0].status === "suppressed"` in the suppression test. That assertion **is** the leak, so it changes here. Update it to `"skipped"`, and update the test's name and comment to say what it now guards:

```typescript
Deno.test("a suppressed number is reported as an opaque skip, never labelled", async () => {
  // ... existing seeding via the direct Postgres connection is unchanged ...
  assertEquals(body.skipped, 1);
  assertEquals(body.results[0].status, "skipped");
  assertEquals(body.results[0].person_id, null);

  // The oracle guard: no response field anywhere may carry the word
  // "suppressed", or the endpoint is enumerable again.
  assertEquals(JSON.stringify(body).includes("suppressed"), false);
});
```

That last assertion is the point of this task. Keep it.

- [ ] **Step 3: Run the Deno suite**

```bash
supabase start
supabase functions serve --no-verify-jwt &
./supabase/functions/test.sh
```

`--no-verify-jwt` is required: `config.toml` has no `[functions]` block, so functions run at `verify_jwt = true` and the gateway would answer an unauthenticated request before the handler's own 401 guard is reachable.

Expected: 6 passed.

- [ ] **Step 4: Prove the new assertion is load-bearing**

Revert `status: "skipped"` back to `status: "suppressed"` in `index.ts`, re-run, and confirm the `JSON.stringify(body).includes("suppressed")` assertion **fails**. Restore. Paste the observed failure into your report — without this, the test proves nothing.

- [ ] **Step 5: Update the client to match**

In `lib/models/import_outcome.dart`, remove the `suppressed` enum member and its `'suppressed' =>` wire mapping. The `_ => ImportStatus.failed` fallback must **not** be what catches the new `"skipped"` — add an explicit `'skipped' => ImportStatus.skipped` member so a suppressed contact still lands in the neutral bucket rather than being reported as a failure:

```dart
enum ImportStatus {
  added,
  duplicate,
  skipped,
  invalidPhone,
  invalidName,
  self,
  failed;

  static ImportStatus fromWire(String value) => switch (value) {
        'added' => ImportStatus.added,
        'duplicate' => ImportStatus.duplicate,
        'skipped' => ImportStatus.skipped,
        'invalid_phone' => ImportStatus.invalidPhone,
        'invalid_name' => ImportStatus.invalidName,
        'self' => ImportStatus.self,
        _ => ImportStatus.failed,
      };
}
```

Then update the comments in `import_summary_screen.dart` and `app_strings.dart` that explain why no `suppressed` string exists — the reasoning now lives at the API layer too, not only in the UI.

- [ ] **Step 6: Run the Flutter suites and commit**

```bash
fvm flutter analyze
fvm flutter test --exclude-tags=contract
fvm flutter test test/repositories --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Any test referencing `ImportStatus.suppressed` must be updated to `ImportStatus.skipped`.

```bash
git add supabase/functions/add_celebrations/ lib/models/import_outcome.dart \
        lib/features/contacts_import/import_summary_screen.dart lib/core/app_strings.dart test/
git commit -m "fix(security): stop labelling suppressed numbers in the import response

The endpoint takes 500 arbitrary numbers per request with no rate limit,
so a labelled status made it a bulk oracle for who had asked to be
forgotten. The aggregate skipped count is unchanged."
```

---

## Task 3: Foundations — the shared guard, the occasion rule, the wish model

Spec §4.3, §4.4, §6. Three small pieces every later task depends on. This is the task where the design principles stop being prose and become code.

**Files:**
- Create: `lib/core/reentrancy_guard.dart`, `test/core/reentrancy_guard_test.dart`
- Create: `lib/models/wish.dart`
- Modify: `lib/models/birthday.dart`, `test/models/birthday_test.dart`
- Modify: `lib/api/api_params.dart` (wish column names)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `mixin ReentrancyGuard` with `@protected Future<void> guard(String key, Future<void> Function() body)` and `@visibleForTesting bool isInFlight(String key)`. Every Phase 3 cubit mixes it in.
  - `int Birthday.occasionYear(DateTime from)`.
  - `class Wish` with `Wish.fromRow(Map<String, dynamic>)`, fields `id`, `authorProfileId`, `subjectPersonId`, `body`, `occasionYear`, `createdAt`, and a mutable-free `withAuthorName(String?)` returning a copy.

- [ ] **Step 1: Write the failing guard test**

Create `test/core/reentrancy_guard_test.dart`:

```dart
import 'package:birthday_app/core/reentrancy_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class _Subject with ReentrancyGuard {
  int calls = 0;
  final _completers = <String, Completer<void>>{};

  Future<void> run(String key) => guard(key, () async {
        calls++;
        _completers[key] = Completer<void>();
        await _completers[key]!.future;
      });

  void finish(String key) => _completers[key]?.complete();
}

void main() {
  test('a second call with the same key while in flight is ignored', () async {
    final s = _Subject();
    final first = s.run('a');
    final second = s.run('a');
    s.finish('a');
    await Future.wait([first, second]);
    expect(s.calls, 1);
  });

  // The whole reason this mixin uses a keyed Set rather than one flag: a
  // double-tap on one row must not fire twice, but must not block a
  // legitimate action on a different row fired in the same instant.
  test('different keys run concurrently', () async {
    final s = _Subject();
    final a = s.run('a');
    final b = s.run('b');
    expect(s.calls, 2);
    s.finish('a');
    s.finish('b');
    await Future.wait([a, b]);
  });

  test('the key is released when the body throws', () async {
    final s = _Subject();
    await expectLater(
      s.guard('a', () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(s.isInFlight('a'), isFalse);
  });

  // The gap this exists to close: the flag must be set BEFORE the first
  // await, or two synchronous taps both pass the check.
  test('the key is claimed synchronously, before the first await', () {
    final s = _Subject();
    s.run('a');
    expect(s.isInFlight('a'), isTrue);
  });
}
```

Add `import 'dart:async';` at the top for `Completer`.

- [ ] **Step 2: Run to verify it fails**

```bash
fvm flutter test test/core/reentrancy_guard_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:birthday_app/core/reentrancy_guard.dart'`.

- [ ] **Step 3: Write the mixin**

Create `lib/core/reentrancy_guard.dart`:

```dart
import 'package:flutter/foundation.dart';

/// One place for the re-entrancy guard every cubit in this app needs.
///
/// Phase 2b grew five of these in three different shapes -- a state check in
/// PhoneCubit and ProfileSetupCubit, a bool in ImportCubit, a keyed Set in
/// TimelineCubit and SettingsCubit -- each rediscovered in review. This is the
/// keyed-Set form, which was the best of them: a double-tap on one row must not
/// fire two writes, but must not block a legitimate action on a different row
/// fired in the same instant.
///
/// A state check is NOT sufficient and must not be substituted. The state a
/// cubit emits to mark "in flight" is often emitted after the first await --
/// ImportCubit.commit does not emit ImportCommitting until the first progress
/// callback -- and that window is exactly where the double-tap lands.
///
/// Phase 2b's cubits are deliberately NOT converted to this mixin. It is
/// written so they could be, one at a time, later.
mixin ReentrancyGuard {
  final Set<String> _inFlight = {};

  /// Runs [body] unless [key] is already in flight.
  ///
  /// The key is claimed synchronously, before [body] is ever awaited, and
  /// released in a `finally` so a throwing body cannot strand it.
  @protected
  Future<void> guard(String key, Future<void> Function() body) async {
    if (!_inFlight.add(key)) return;
    try {
      await body();
    } finally {
      _inFlight.remove(key);
    }
  }

  @visibleForTesting
  bool isInFlight(String key) => _inFlight.contains(key);
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
fvm flutter test test/core/reentrancy_guard_test.dart
```

Expected: `All tests passed!` — 4 tests.

- [ ] **Step 5: Prove the synchronous claim is load-bearing**

Change `guard`'s body to `await Future<void>.delayed(Duration.zero); if (!_inFlight.add(key)) return;` — i.e. claim the key *after* an await. Re-run. Expected: **`the key is claimed synchronously, before the first await` fails**, and `a second call with the same key while in flight is ignored` fails too. Restore.

This is the exact defect the mixin exists to prevent, and it is invisible without this test.

- [ ] **Step 6: Write the failing occasion-year test**

Append to `test/models/birthday_test.dart`:

```dart
  group('occasionYear', () {
    test('on the birthday itself, it is this year', () {
      const b = Birthday(month: 4, day: 15);
      expect(b.occasionYear(DateTime(2026, 4, 15)), 2026);
    });

    test('a few days after, it is still this year', () {
      const b = Birthday(month: 4, day: 15);
      expect(b.occasionYear(DateTime(2026, 4, 20)), 2026);
    });

    test('a few days before, it is this year too', () {
      const b = Birthday(month: 4, day: 15);
      expect(b.occasionYear(DateTime(2026, 4, 10)), 2026);
    });

    // The case the rule exists for: a December birthday wished in January is
    // a belated wish for LAST December, not an early one for next.
    test('a December birthday wished in January belongs to last December', () {
      const b = Birthday(month: 12, day: 25);
      expect(b.occasionYear(DateTime(2027, 1, 5)), 2026);
    });

    test('the same birthday wished in December belongs to this December', () {
      const b = Birthday(month: 12, day: 25);
      expect(b.occasionYear(DateTime(2026, 12, 20)), 2026);
    });

    // Exactly halfway is a tie, and ties go to the past -- a wish is far more
    // often belated than six months early.
    test('a tie resolves to the past', () {
      const b = Birthday(month: 1, day: 1);
      // 2026-07-02 is 182 days after Jan 1 2026 and 183 before Jan 1 2027.
      expect(b.occasionYear(DateTime(2026, 7, 2)), 2026);
    });

    // The Feb 29 rule already in this class applies unchanged, so the client
    // and the reminder fan-out continue to agree.
    test('a Feb 29 birthday resolves through Feb 28 in a non-leap year', () {
      const b = Birthday(month: 2, day: 29);
      expect(b.occasionYear(DateTime(2027, 3, 1)), 2027);
    });
  });
```

- [ ] **Step 7: Run to verify it fails, then implement**

```bash
fvm flutter test test/models/birthday_test.dart
```

Expected: FAIL — `The method 'occasionYear' isn't defined`.

Add to `lib/models/birthday.dart`, below `groupFrom`:

```dart
  /// The year of the birthday occurrence this wish is *for*.
  ///
  /// The occurrence nearest to [from], with a tie going to the past. A
  /// December birthday wished on 5 January attaches to last December; wished
  /// on 20 December it attaches to this December. Belated and early wishes
  /// both land on the occasion the user meant, and nobody is asked a question
  /// they would not understand.
  ///
  /// Ties resolve backwards because a wish is far more often belated than six
  /// months early. [_inYear]'s Feb 29 rule applies unchanged, so this agrees
  /// with the reminder fan-out.
  int occasionYear(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final next = nextOccurrence(from);

    final thisYear = _inYear(today.year);
    final previous =
        thisYear.isAfter(today) ? _inYear(today.year - 1) : thisYear;

    final daysToNext = next.difference(today).inDays;
    final daysSincePrevious = today.difference(previous).inDays;

    return daysSincePrevious <= daysToNext ? previous.year : next.year;
  }
```

Re-run: `All tests passed!` — 7 new tests.

- [ ] **Step 8: Prove the tie rule is load-bearing**

Change `<=` to `<` in the return. Re-run. Expected: **`a tie resolves to the past` fails** and nothing else does. Restore.

- [ ] **Step 9: Write the wish model**

Add wish column names to `lib/api/api_params.dart`:

```dart
  // wishes
  static const wishes = 'wishes';
  static const authorProfileId = 'author_profile_id';
  static const subjectPersonId = 'subject_person_id';
  static const body = 'body';
  static const kind = 'kind';
  static const occasionYear = 'occasion_year';
  static const createdAt = 'created_at';
```

Create `lib/models/wish.dart`:

```dart
import '../api/api_params.dart';

/// A row in public.wishes, with its author's name resolved separately.
///
/// [authorName] is null when the viewer is not connected to the author.
/// `profiles_select_own` restricts profiles to their owner, so a wall cannot
/// read another author's profile at all; names come from the author's `people`
/// row instead, which RLS filters through private.can_see_person. An author the
/// viewer neither celebrates nor is celebrated by simply does not come back,
/// and the wish renders unattributed. That is the intended privacy outcome, not
/// a gap to work around.
class Wish {
  const Wish({
    required this.id,
    required this.authorProfileId,
    required this.subjectPersonId,
    required this.body,
    required this.occasionYear,
    required this.createdAt,
    this.authorName,
  });

  final int id;
  final String authorProfileId;
  final int subjectPersonId;
  final String body;
  final int occasionYear;
  final DateTime createdAt;
  final String? authorName;

  bool get isMine => authorName == null && false; // set by the repository

  Wish withAuthorName(String? name) => Wish(
        id: id,
        authorProfileId: authorProfileId,
        subjectPersonId: subjectPersonId,
        body: body,
        occasionYear: occasionYear,
        createdAt: createdAt,
        authorName: name,
      );

  factory Wish.fromRow(Map<String, dynamic> row) => Wish(
        id: row[ApiParams.id] as int,
        authorProfileId: row[ApiParams.authorProfileId] as String,
        subjectPersonId: row[ApiParams.subjectPersonId] as int,
        body: row[ApiParams.body] as String,
        occasionYear: row[ApiParams.occasionYear] as int,
        createdAt: DateTime.parse(row[ApiParams.createdAt] as String),
      );
}
```

**Delete the `isMine` line above before committing** — it is wrong as written and there is no caller for it. Authorship is decided by the repository comparing `authorProfileId` to the signed-in user, and Task 6's screen reads that. It appears here only as a warning: do not add a getter that guesses.

- [ ] **Step 10: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/core/reentrancy_guard.dart lib/models/wish.dart lib/models/birthday.dart \
        lib/api/api_params.dart test/core test/models
git commit -m "feat(core): the shared re-entrancy guard, the occasion rule, the wish model

Phase 2b grew five re-entrancy guards in three shapes, each rediscovered
in review. This is the best of them, in one place, for new cubits."
```

---

## Task 4: `PersonRepository` and its contract tests

Spec §4.1, §4.2, §7.1. The first repository written under the new rules: one responsibility, registered in `app.dart`, never constructed by a screen.

**Files:**
- Create: `lib/repositories/person_repository.dart`, `lib/repositories/person_repository_impl.dart`
- Create: `test/repositories/person_repository_test.dart` (imports the shared harness)
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `ApiClient.instance`, `ApiParams`, `ApiEndpoints`, `mapError`, `Person` (Task 4 of Phase 2b), `private.can_see_person` via RLS.
- Produces: `abstract interface class PersonRepository` with `Future<Person> person(int personId)` and `Future<int> celebratorCount(int personId)`. Throws `ServerFailure` with code `45004` when the caller cannot see the person. Task 6's `PersonCubit` consumes it.

- [ ] **Step 1: Write the failing contract test**

Create `test/repositories/person_repository_test.dart`. Sign in as **`+919999000007`** — every contract suite owns its own number because `flutter test` runs files concurrently.

Follow the exact shape of `test/repositories/graph_repository_test.dart`: `@Tags(['contract'])`, `setUpContractTestEnvironment()` as the first statement of `setUpAll`, OTP sends routed through the harness throttle.

Cover these four behaviours:

```dart
// 1. person() returns a person the caller celebrates, with their birthday.
//    Seed by adding a contact through ContactsRepositoryImpl, exactly as
//    graph_repository_test.dart does.
// 2. celebratorCount() returns 1 for a person only the caller celebrates.
// 3. person() on a person the caller does NOT celebrate throws — the row is
//    invisible under people_select_visible, so this surfaces as a PostgREST
//    "no rows" error rather than a class-45 code. Assert it is an AppFailure,
//    and record in your report which code actually came back.
// 4. celebratorCount() on a person the caller does NOT celebrate throws
//    ServerFailure with code '45004'. This is the assertion that matters:
//    people.id is a sequential bigint, and this is what stops the id space
//    being walked for follower counts.
```

Assertion 4 must pin the **specific** code with `.having((f) => f.code, 'code', '45004')`. A matcher accepting any `ServerFailure` would pass even if the wrong guard fired, which is exactly how a Phase 2b trial nearly went unnoticed.

- [ ] **Step 2: Run to verify it fails**

```bash
supabase start && supabase functions serve &
fvm flutter test test/repositories/person_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: FAIL — the URIs do not exist.

- [ ] **Step 3: Write the interface**

Create `lib/repositories/person_repository.dart`:

```dart
import '../models/person.dart';

/// Reads about a single person. One responsibility: this is deliberately NOT
/// folded into GraphRepository, which reads the timeline. A consumer of one
/// should not be forced to depend on the other.
abstract interface class PersonRepository {
  /// The person, if the caller may see them. RLS decides: they are visible
  /// when the caller celebrates them, when they celebrate the caller, or when
  /// they are the caller's own person row.
  Future<Person> person(int personId);

  /// How many people celebrate them. A number, never names.
  ///
  /// Throws [ServerFailure] with code '45004' when the caller cannot see the
  /// person — people.id is a sequential bigint, so the count is gated.
  Future<int> celebratorCount(int personId);
}
```

- [ ] **Step 4: Write the implementation**

Create `lib/repositories/person_repository_impl.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../models/person.dart';
import 'person_repository.dart';

class PersonRepositoryImpl implements PersonRepository {
  const PersonRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<Person> person(int personId) async {
    try {
      final row = await _client
          .from(ApiParams.people)
          .select()
          .eq(ApiParams.id, personId)
          .single();
      return Person.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<int> celebratorCount(int personId) async {
    try {
      final result = await _client.rpc(
        ApiEndpoints.rpcPersonCelebratorCount,
        params: {ApiParams.pPersonId: personId},
      );
      return result as int;
    } catch (e) {
      throw mapError(e);
    }
  }
}
```

Add to `lib/api/api_endpoints.dart`:

```dart
  static const rpcPersonCelebratorCount = 'person_celebrator_count';
```

- [ ] **Step 5: Register it in `app.dart` — do NOT let a screen construct it**

This is spec §4.2 and the point of the task. In `lib/app.dart`, add the field and the provider:

```dart
  late final PersonRepository _person = PersonRepositoryImpl(ApiClient.instance);
```

```dart
      providers: [
        RepositoryProvider<AuthRepository>.value(value: _auth),
        RepositoryProvider<PersonRepository>.value(value: _person),
      ],
```

Screens read it with `context.read<PersonRepository>()`. **No `?? PersonRepositoryImpl(...)` fallback anywhere** — that pattern in `SettingsScreen` and `TimelineScreen` is why a widget test cannot mount them without a live Supabase, and it is not repeated here.

- [ ] **Step 6: Run to verify it passes**

Expected: `All tests passed!` — 4 tests.

- [ ] **Step 7: Prove the visibility gate is real from the client**

Comment out the `can_see_person` check in `supabase/migrations/20260830000001_person_celebrator_count.sql`, run `supabase db reset`, and confirm **assertion 4 fails**. Restore.

Task 1 proved the guard from SQL; this proves the client surfaces `45004` rather than flattening it into a generic failure. They are different claims and both are needed.

- [ ] **Step 8: Commit**

```bash
git add lib/repositories/person_repository.dart lib/repositories/person_repository_impl.dart \
        lib/api/api_endpoints.dart lib/app.dart test/repositories/person_repository_test.dart
git commit -m "feat(person): the person repository, injected not constructed

One responsibility, registered in app.dart, read with context.read.
No ?? ConcreteImpl fallback -- that pattern is why two Phase 2b screens
cannot be mounted in a widget test."
```

---

## Task 5: `WishRepository` and its contract tests

Spec §7.1, §7.2. Reads a person's wall and posts to it. The read is two steps, for a reason worth understanding before you write it.

**Files:**
- Create: `lib/repositories/wish_repository.dart`, `lib/repositories/wish_repository_impl.dart`
- Create: `test/repositories/wish_repository_test.dart`
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `ApiClient.instance`, `ApiParams`, `mapError`, `Wish` (Task 3).
- Produces: `abstract interface class WishRepository` with `Future<List<Wish>> wishesFor(int personId)` and `Future<void> post({required int personId, required String body, required int occasionYear})`. Task 6's `PersonCubit` consumes both.

**Why the read is two steps.** `profiles_select_own` restricts `profiles` to `id = auth.uid()`, so the viewer cannot read another author's profile at all. `wishes` carries only `author_profile_id`, and there is **no foreign key from `wishes` to `people`**, so PostgREST cannot auto-embed the author. So: load the wishes, collect the distinct author profile ids, and resolve them in a second query against `public.people` on `profile_id in (…)`.

RLS then does the right thing with no extra work. `people_select_visible` runs `private.can_see_person`, whose branches are *my own person*, *someone I celebrate*, and *someone who celebrates me*. An author the viewer is connected to comes back and renders by name; an author they are not simply does not, and the wish renders unattributed. **This is the intended privacy outcome — do not add a function to expose the rest.**

- [ ] **Step 1: Write the failing contract test**

Create `test/repositories/wish_repository_test.dart`, signing in as **`+919999000008`**. Same shape as `test/repositories/person_repository_test.dart` — `@Tags(['contract'])`, `setUpContractTestEnvironment()` first in `setUpAll`, OTP through the harness throttle.

Cover these six behaviours:

```dart
// 1. post() then wishesFor() returns the wish, with its body and occasionYear.
// 2. wishesFor() returns newest first.
// 3. post() to a person the caller does NOT celebrate is refused.
//    wishes_insert_own requires a celebration edge. Assert an AppFailure and
//    record the actual code in your report.
// 4. The author's own name resolves: a wish the caller wrote on a person they
//    celebrate comes back with authorName set to the caller's display name
//    (the caller's own person row is visible via can_see_person's first branch).
// 5. A wish by an author the caller is NOT connected to comes back with
//    authorName == null, and the wish itself still comes back. Build this by
//    signing in as a second identity, having it celebrate and wish the same
//    person, then signing back in as the first. THIS IS THE PRIVACY ASSERTION
//    — it proves the wall does not leak names outside the viewer's graph.
// 6. A body over 500 characters is refused by the DB check constraint
//    (wishes_body_length). Assert ServerFailure with code '23514'.
```

Assertion 5 is the one this task exists for. Assertion 6 must pin `23514` specifically.

- [ ] **Step 2: Run to verify it fails**

```bash
supabase start && supabase functions serve &
fvm flutter test test/repositories/wish_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: FAIL — the URIs do not exist.

- [ ] **Step 3: Write the interface**

Create `lib/repositories/wish_repository.dart`:

```dart
import '../models/wish.dart';

/// The wish wall. One responsibility: reading and writing wishes.
abstract interface class WishRepository {
  /// A person's wall, newest first, with author names resolved where the
  /// viewer is connected to the author and null where they are not.
  Future<List<Wish>> wishesFor(int personId);

  /// Posts a wish. RLS refuses unless the caller celebrates [personId].
  /// [occasionYear] comes from `Birthday.occasionYear`, never from the user.
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  });
}
```

- [ ] **Step 4: Write the implementation**

Create `lib/repositories/wish_repository_impl.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/wish.dart';
import 'wish_repository.dart';

class WishRepositoryImpl implements WishRepository {
  const WishRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Wish>> wishesFor(int personId) async {
    try {
      final rows = await _client
          .from(ApiParams.wishes)
          .select()
          .eq(ApiParams.subjectPersonId, personId)
          .order(ApiParams.createdAt, ascending: false);

      final wishes = (rows as List)
          .map((r) => Wish.fromRow(r as Map<String, dynamic>))
          .toList();
      if (wishes.isEmpty) return wishes;

      // Second step, and it cannot be avoided: profiles_select_own restricts
      // profiles to their owner, and there is no FK from wishes to people, so
      // PostgREST cannot embed the author. Resolve names from `people`, where
      // RLS filters to authors already in the viewer's graph. Anyone else
      // comes back missing and their wish renders unattributed -- intended.
      final authorIds =
          wishes.map((w) => w.authorProfileId).toSet().toList(growable: false);

      final people = await _client
          .from(ApiParams.people)
          .select('${ApiParams.profileId}, ${ApiParams.displayName}')
          .inFilter(ApiParams.profileId, authorIds);

      final names = <String, String>{
        for (final p in people as List)
          (p as Map<String, dynamic>)[ApiParams.profileId] as String:
              p[ApiParams.displayName] as String,
      };

      return wishes
          .map((w) => w.withAuthorName(names[w.authorProfileId]))
          .toList(growable: false);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  }) async {
    final authorId = _client.auth.currentUser?.id;
    if (authorId == null) throw const AuthFailure('no session');
    try {
      await _client.from(ApiParams.wishes).insert({
        ApiParams.authorProfileId: authorId,
        ApiParams.subjectPersonId: personId,
        ApiParams.body: body,
        ApiParams.occasionYear: occasionYear,
      });
    } catch (e) {
      throw mapError(e);
    }
  }
}
```

Note `kind` is not written — it defaults to `'message'`. `'cake'` is written only by `private.post_cake_wish` in M3, and no client path may set it.

- [ ] **Step 5: Register it in `app.dart`**

```dart
  late final WishRepository _wish = WishRepositoryImpl(ApiClient.instance);
```

```dart
        RepositoryProvider<WishRepository>.value(value: _wish),
```

No fallback construction in any screen.

- [ ] **Step 6: Run to verify it passes**

Expected: `All tests passed!` — 6 tests.

- [ ] **Step 7: Prove the privacy assertion is load-bearing**

Change the second query's `.inFilter` to resolve names through a path RLS does not filter — for this trial only, replace the `people` lookup with a hard-coded map returning a name for every author id. Re-run and confirm **assertion 5 fails** (an unconnected author now has a name). Restore.

If assertion 5 passes with names hard-coded, it is not testing the privacy boundary and must be rewritten.

- [ ] **Step 8: Commit**

```bash
git add lib/repositories/wish_repository.dart lib/repositories/wish_repository_impl.dart \
        lib/app.dart test/repositories/wish_repository_test.dart
git commit -m "feat(wish): the wall repository, with author names filtered by RLS

A wall cannot read another author's profile -- profiles_select_own sees
to that -- so names come from people rows, which can_see_person filters
to the viewer's own graph. Authors outside it render unattributed."
```

---

## Task 6: The person page and the compose sheet

Spec §7.1, §7.2. The screen a timeline row finally leads to.

**Files:**
- Create: `lib/features/person/person_cubit.dart`, `person_state.dart`, `person_screen.dart`, `wish_compose_sheet.dart`
- Create: `test/features/person/person_cubit_test.dart`, `test/features/person/person_screen_test.dart`
- Modify: `lib/router/app_router.dart`, `lib/features/timeline/timeline_screen.dart`, `lib/core/app_strings.dart`

**Interfaces:**
- Consumes: `PersonRepository` (Task 4), `WishRepository` (Task 5), `ReentrancyGuard` (Task 3), `Birthday.occasionYear` (Task 3).
- Produces: `PersonCubit(PersonRepository, WishRepository)` with `load(int personId)` and `postWish(String body)`; `PersonState` = `PersonLoading | PersonLoaded(person, celebratorCount, wishes, posting) | PersonError(message)`.

- [ ] **Step 1: Add the strings**

Append to `lib/core/app_strings.dart`:

```dart
  // Person page
  static const personCelebratorCountTemplate = '%s people celebrate them';
  static const personCelebratorCountOne = '1 person celebrates them';
  static const personNoBirthday = 'No birthday recorded yet';
  static const personWallEmpty = 'No wishes yet. Be the first.';
  static const personWriteWish = 'Write a wish';
  static const wishAuthorUnknown = 'Someone who celebrates them';
  static const wishHint = 'Say something nice';
  static const wishPost = 'Post';
  static const wishTooLong = 'A wish can be at most 500 characters.';
  static const wishEmpty = 'Write something first.';
  static const wishPostFailed = 'That wish could not be posted.';
```

- [ ] **Step 2: Write the failing Cubit test**

Create `test/features/person/person_cubit_test.dart` with fakes for both repositories. Cover:

```dart
// 1. load() emits PersonLoading then PersonLoaded with the person, the count
//    and the wishes.
// 2. A person with no birthday still loads — the page must render, because
//    the timeline's inline edit is how a missing birthday gets fixed.
// 3. A failing celebratorCount surfaces as PersonError with a human message,
//    never a Dart type dump. Assert the message does not contain 'Instance of'
//    AND that a non-AppFailure falls back to AppStrings.somethingWentWrong —
//    the second is the assertion that actually discriminates, because
//    AppFailure.toString() would satisfy the first on its own.
// 4. postWish() derives occasionYear from the person's birthday rather than
//    taking it as an argument. Assert the fake recorded the year that
//    Birthday.occasionYear returns for the injected clock.
// 5. postWish() reloads the wall on success, so the new wish appears.
// 6. A second postWish() while the first is in flight is ignored. Assert the
//    fake recorded ONE post. This is the ReentrancyGuard mixin doing its job.
```

Assertion 4 is the point of the design: the user is never asked which year.

`PersonCubit` takes `{DateTime Function() now}` for the same reason `TimelineCubit` does — a test reading the real clock passes in April and fails in October.

- [ ] **Step 3: Run to verify it fails, then write the state and cubit**

`lib/features/person/person_state.dart` — a sealed hierarchy matching the shape of `lib/features/timeline/timeline_state.dart`.

`lib/features/person/person_cubit.dart` — **mixes in `ReentrancyGuard`** and routes every action through `guard`:

```dart
class PersonCubit extends Cubit<PersonState> with ReentrancyGuard {
  PersonCubit(this._people, this._wishes, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const PersonLoading());

  final PersonRepository _people;
  final WishRepository _wishes;
  final DateTime Function() _now;

  Future<void> load(int personId) => guard('load', () async { … });

  Future<void> postWish(String body) => guard('post', () async { … });
}
```

`postWish` reads the loaded person's birthday, calls `birthday.occasionYear(_now())`, posts, then reloads the wall. When the person has no birthday it must not post — the affordance is hidden in that case (Step 4), so reaching it is a bug; emit the generic failure rather than inventing a year.

Error handling follows the shape established in `timeline_cubit.dart`: `on AppFailure catch (f) => emit(PersonError(f.message))`, then `catch (_) => emit(const PersonError(AppStrings.somethingWentWrong))`. **Never `'$e'`** — that shipped `Instance of 'ServerFailure'` to users in Phase 2b.

- [ ] **Step 4: Write the screen and the sheet**

`person_screen.dart`: an AppBar with the person's name and **a working back affordance** — `/person/:personId` is reached with `context.go`, which replaces the stack, so `automaticallyImplyLeading` finds nothing to pop and no arrow renders. Supply `leading` explicitly, navigating to `/timeline`. This trap has now bitten this project twice.

Body: birthday (or `personNoBirthday`), the celebrator count (using `personCelebratorCountOne` when the count is exactly 1 — "1 people celebrate them" is the kind of thing that gets noticed), then the wall newest-first. Each wish shows its body, `authorName ?? AppStrings.wishAuthorUnknown`, and its occasion year. Empty wall shows `personWallEmpty`.

A `FloatingActionButton` reading `personWriteWish` opens the sheet — **shown only when the person has a birthday and the viewer celebrates them**, hidden otherwise rather than disabled, because there is nothing the user could do on this screen to enable it.

`wish_compose_sheet.dart`: a modal bottom sheet with one `TextField` (`maxLength: 500`, so the counter renders), and a post button keyed `Key('wish_post')`. It reads `PersonCubit` from context and calls `postWish`. After an awaited close, **check `mounted` before touching `context`** — Task 8 of Phase 2b shipped exactly that bug.

Layout inline; no extracted row widget unless the build method becomes genuinely unreadable.

- [ ] **Step 5: Wire the route and the timeline row tap**

In `lib/router/app_router.dart`:

```dart
      GoRoute(
        path: '/person/:personId',
        builder: (_, state) => PersonScreen(
          personId: int.parse(state.pathParameters['personId']!),
        ),
      ),
```

Add `/person/:personId` to the `signedIn` set alongside `/timeline`, `/import` and `/settings`, or the guard will redirect away from it.

In `lib/features/timeline/timeline_screen.dart`, give each row an `onTap` navigating to `/person/${celebration.person.id}`. Rows currently have only an overflow menu, so tapping one does nothing.

- [ ] **Step 6: Write the widget test**

`test/features/person/person_screen_test.dart`, with a mocked `PersonCubit`:

```dart
// 1. A wish by an unconnected author renders AppStrings.wishAuthorUnknown.
// 2. The celebrator count uses the singular string when the count is 1.
// 3. The compose FAB is absent when the person has no birthday.
// 4. The back affordance is present and enabled.
```

If any assertion counts screens, pass `skipOffstage: false`.

- [ ] **Step 7: Prove the occasion-year derivation is load-bearing**

Break `postWish` to pass `_now().year` instead of `birthday.occasionYear(_now())`. Re-run the Cubit tests and confirm **assertion 4 fails** for the December-birthday-in-January case. Restore.

- [ ] **Step 8: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/features/person lib/router/app_router.dart \
        lib/features/timeline/timeline_screen.dart lib/core/app_strings.dart test/features/person
git commit -m "feat(person): the person page and the compose sheet

The occasion year is derived from the birthday, never asked. A December
birthday wished in January is a belated wish for last December."
```

---

## Task 7: `ProfileRepository` and its contract tests

Spec §4.1, §7.3.

**A correction to the spec, made here rather than silently.** §4.1 lists `ProfileRepository` as owning `stats()`, `celebrates()` **and `celebrating()`**. The third is wrong: `GraphRepository.celebrations()` already returns exactly that list, and duplicating it would trade one SOLID violation for a DRY one. `ProfileRepository` owns `stats()` and `celebrates()`; the Celebrating list screen reuses `GraphRepository`.

**Files:**
- Create: `lib/models/birthday_stat.dart`
- Create: `lib/repositories/profile_repository.dart`, `lib/repositories/profile_repository_impl.dart`
- Create: `test/repositories/profile_repository_test.dart`
- Modify: `lib/app.dart`, `lib/api/api_endpoints.dart`, `lib/api/api_params.dart`

**Interfaces:**
- Consumes: `ApiClient.instance`, `mapError`, `Person`, and the existing `public.my_birthday_stats()` / `public.my_celebrates()` from M1 Phase 1.
- Produces: `class BirthdayStat` (`year`, `wishesSent`, `wishesReceived`, `birthdaysCelebrated`); `abstract interface class ProfileRepository` with `Future<List<BirthdayStat>> stats()` and `Future<List<Person>> celebrates()`.

- [ ] **Step 1: Write the model**

`lib/models/birthday_stat.dart`:

```dart
import '../api/api_params.dart';

/// One year of the profile's track record, from public.my_birthday_stats().
///
/// [birthdaysCelebrated] counts DISTINCT people wished that year, which differs
/// from [wishesSent] once a cake post and a typed message can both land on the
/// same person in the same year. Dormant until M3 — the function already
/// computes it distinctly.
class BirthdayStat {
  const BirthdayStat({
    required this.year,
    required this.wishesSent,
    required this.wishesReceived,
    required this.birthdaysCelebrated,
  });

  final int year;
  final int wishesSent;
  final int wishesReceived;
  final int birthdaysCelebrated;

  factory BirthdayStat.fromRow(Map<String, dynamic> row) => BirthdayStat(
        year: row[ApiParams.statYear] as int,
        wishesSent: row[ApiParams.wishesSent] as int,
        wishesReceived: row[ApiParams.wishesReceived] as int,
        birthdaysCelebrated: row[ApiParams.birthdaysCelebrated] as int,
      );
}
```

Add to `lib/api/api_params.dart`:

```dart
  // my_birthday_stats
  static const statYear = 'stat_year';
  static const wishesSent = 'wishes_sent';
  static const wishesReceived = 'wishes_received';
  static const birthdaysCelebrated = 'birthdays_celebrated';

  // my_celebrates
  static const celebratorPersonId = 'celebrator_person_id';
```

Add to `lib/api/api_endpoints.dart`:

```dart
  static const rpcMyBirthdayStats = 'my_birthday_stats';
  static const rpcMyCelebrates = 'my_celebrates';
```

- [ ] **Step 2: Write the failing contract test**

Create `test/repositories/profile_repository_test.dart`, signing in as **`+919999000009`** — already added in Task 1. Do not edit `config.toml`.

Cover:

```dart
// 1. stats() returns an empty list for a fresh account with no wishes.
// 2. After posting a wish, stats() has a row for that occasion year with
//    wishesSent == 1. Seed via WishRepository, not raw SQL — this proves the
//    function reflects what the app actually writes.
// 3. celebrates() is empty for an account nobody celebrates.
// 4. celebrates() returns the celebrator with their name once a second
//    identity celebrates the caller. can_see_person's third branch ("they
//    celebrate me") is what makes that name readable — this asserts it.
// 5. A celebrator the caller has blocked does not appear in celebrates().
```

Assertion 4 is the one that proves the profile's Celebrates list can render names at all.

- [ ] **Step 3: Run to verify it fails, then write the interface**

`lib/repositories/profile_repository.dart`:

```dart
import '../models/birthday_stat.dart';
import '../models/person.dart';

/// The signed-in user's own profile data. One responsibility.
///
/// Deliberately does NOT own the Celebrating list: GraphRepository.celebrations()
/// already returns it, and the profile's list screen reuses that rather than
/// duplicating the query here.
abstract interface class ProfileRepository {
  /// The per-year track record, newest year first.
  Future<List<BirthdayStat>> stats();

  /// The people who celebrate the signed-in user, excluding anyone they have
  /// blocked. A celebrator with no claimed person row is omitted — there is
  /// no name to show.
  Future<List<Person>> celebrates();
}
```

- [ ] **Step 4: Write the implementation**

`lib/repositories/profile_repository_impl.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../models/birthday_stat.dart';
import '../models/person.dart';
import 'profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<BirthdayStat>> stats() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyBirthdayStats);
      final stats = (rows as List)
          .map((r) => BirthdayStat.fromRow(r as Map<String, dynamic>))
          .toList();
      stats.sort((a, b) => b.year.compareTo(a.year));
      return stats;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Person>> celebrates() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyCelebrates);

      // my_celebrates() returns identities only — a profile id and a person id,
      // never a name, because a row-level policy exposing incoming edges would
      // also hand over the celebrator's private nickname and the source that
      // reveals how they found you. Names come from `people`, where
      // can_see_person's "they celebrate me" branch makes exactly these rows
      // visible. The left join means celebrator_person_id can be null for a
      // celebrator who has not claimed their own row; those are dropped.
      final personIds = (rows as List)
          .map((r) => (r as Map<String, dynamic>)[ApiParams.celebratorPersonId])
          .whereType<int>()
          .toList(growable: false);
      if (personIds.isEmpty) return const [];

      final people = await _client
          .from(ApiParams.people)
          .select()
          .inFilter(ApiParams.id, personIds);

      return (people as List)
          .map((p) => Person.fromRow(p as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      throw mapError(e);
    }
  }
}
```

- [ ] **Step 5: Register in `app.dart`, run, and prove assertion 4**

Add the field and `RepositoryProvider<ProfileRepository>.value(...)`. No fallback construction.

Then break assertion 4: change `celebrates()` to return `const []` unconditionally and confirm that test fails. Restore. Paste the output.

- [ ] **Step 6: Commit**

```bash
git add lib/models/birthday_stat.dart lib/repositories/profile_repository.dart \
        lib/repositories/profile_repository_impl.dart lib/api lib/app.dart \
        supabase/config.toml test/repositories/profile_repository_test.dart
git commit -m "feat(profile): stats and the celebrates list

Does not own the Celebrating list -- GraphRepository already returns it,
and duplicating the query would trade a SOLID violation for a DRY one."
```

---

## Task 8: The profile screen and its two lists

Spec §7.3.

**Files:**
- Create: `lib/features/profile/profile_cubit.dart`, `profile_state.dart`, `profile_screen.dart`, `celebration_list_screen.dart`
- Create: `test/features/profile/profile_cubit_test.dart`, `test/features/profile/profile_screen_test.dart`
- Modify: `lib/router/app_router.dart`, `lib/features/timeline/timeline_screen.dart`, `lib/core/app_strings.dart`

**Interfaces:**
- Consumes: `ProfileRepository` (Task 7), `GraphRepository` (Phase 2b), `AuthRepository.loadProfile()` (Phase 2b), `ReentrancyGuard` (Task 3).
- Produces: `ProfileCubit(ProfileRepository, GraphRepository, AuthRepository)` with `load()`; `ProfileState` = `ProfileLoading | ProfileLoaded(profile, celebratingCount, celebratesCount, wishesReceived, stats) | ProfileError(message)`.

- [ ] **Step 1: Add the strings**

```dart
  // Profile
  static const profileTitle = 'You';
  static const profileCelebrating = 'Celebrating';
  static const profileCelebrates = 'Celebrates';
  static const profileWishesReceived = 'Wishes received';
  static const profileTrackRecord = 'Track record';
  static const profileTrackRecordEmpty =
      'Your track record starts with your first wish.';
  static const profileStatSent = 'sent';
  static const profileStatReceived = 'received';
  static const profileStatCelebrated = 'birthdays';
  static const profileCelebratingEmpty = 'You are not celebrating anyone yet.';
  static const profileCelebratesEmpty = 'Nobody celebrates you yet.';
```

- [ ] **Step 2: Write the failing Cubit test**

`test/features/profile/profile_cubit_test.dart`, fakes for all three repositories:

```dart
// 1. load() emits ProfileLoading then ProfileLoaded with all three header
//    counts and the stats list.
// 2. wishesReceived comes from the CURRENT year's stat row, or 0 when there
//    is no row for this year. A clock is injected for this — reading the real
//    one makes the test pass this year and fail next.
// 3. An empty stats list still loads, with all counts zero and an empty track
//    record. A brand-new account must not see an error screen.
// 4. A failure in any one of the three repositories surfaces as ProfileError
//    with a human message. Assert a non-AppFailure falls back to
//    AppStrings.somethingWentWrong — that is the discriminating assertion.
// 5. A second load() while the first is in flight is ignored (ReentrancyGuard).
```

- [ ] **Step 3: Write the state, cubit and screens**

`ProfileCubit extends Cubit<ProfileState> with ReentrancyGuard`, `load()` routed through `guard('load', …)`, fetching the profile, stats, celebrates and celebrations. Error handling in the `timeline_cubit.dart` shape — `on AppFailure` then a `catch (_)` fallback, **never `'$e'`**.

`profile_screen.dart`: a header row of three counts. The first two are tappable, navigating to `/profile/celebrating` and `/profile/celebrates`; "Wishes received" is not tappable (M1 has no per-wish list for it). Below, the track record: one row per year, newest first, showing sent / received / birthdays. Empty state shows `profileTrackRecordEmpty`.

**An explicit back affordance** on this screen's AppBar navigating to `/timeline` — `context.go` replaces the stack, so no arrow renders by default.

`celebration_list_screen.dart`: one screen serving both lists, taking a title and a list of `Person`. Reached at `/profile/celebrating` (fed by `GraphRepository.celebrations()`, mapped to their people) and `/profile/celebrates` (fed by `ProfileRepository.celebrates()`). **Both get a back affordance to `/profile`.** Rows in the Celebrating list navigate to `/person/:id`; rows in the Celebrates list do **not** — the viewer may not be able to see those people's pages, and a row that errors on tap is worse than a row that does nothing.

- [ ] **Step 4: Wire the routes and the AppBar entry**

Add `/profile`, `/profile/celebrating` and `/profile/celebrates` to the router, and add all three to the `signedIn` set. Add a profile `IconButton` to `TimelineScreen`'s AppBar `actions`, beside the existing settings gear.

- [ ] **Step 5: Write the widget test**

`test/features/profile/profile_screen_test.dart`:

```dart
// 1. All three header counts render their values.
// 2. The track record renders one row per year, newest first.
// 3. The empty track record shows profileTrackRecordEmpty.
// 4. The back affordance is present and enabled.
```

Pass `skipOffstage: false` on anything counting screens.

- [ ] **Step 6: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/features/profile lib/router/app_router.dart \
        lib/features/timeline/timeline_screen.dart lib/core/app_strings.dart test/features/profile
git commit -m "feat(profile): header counts, both lists and the track record"
```

---

## Task 9: The end-to-end test and the phase close

The parent spec's single end-to-end test — `sign in → import → timeline → wish → profile counts tick` — has been unwritable since M1 began, because it needs the wish and the profile. It becomes writable here.

**Files:**
- Create: `test/e2e/social_loop_test.dart`
- Create: `docs/superpowers/execution/2026-08-30-m1-phase3-ledger.md`

- [ ] **Step 1: Write the end-to-end test**

`test/e2e/social_loop_test.dart`, tagged `contract` (it needs the real stack), signing in as **`+919999000010`** — already added in Task 1. Do not edit `config.toml`.

It drives the **repositories**, not the widgets: sign in, claim, add a celebration through `ContactsRepository`, read the timeline through `GraphRepository`, post a wish through `WishRepository`, then assert `ProfileRepository.stats()` shows `wishesSent == 1` for that occasion year.

This is deliberately not a widget-driven test. A widget-level E2E on the Dart VM would add mounting complexity without touching the one thing still unverified — the app on a real device — and would be slower and more brittle for it. Say so in the ledger rather than letting a reader assume it was an oversight.

- [ ] **Step 2: Full cold verification**

```bash
supabase db reset && supabase test db          # expect 28 files green from cold
supabase functions serve --no-verify-jwt &
./supabase/functions/test.sh                   # Deno
fvm flutter analyze                            # No issues found
fvm flutter test --exclude-tags=contract
fvm flutter test test/repositories test/e2e \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Report the numbers you observe. If any differs from expectation, that is a finding — do not adjust the expectation to match.

- [ ] **Step 3: Re-verify the config guard**

```bash
awk '/^\[auth\./{sec=$0} /enable_confirmations/{print NR": "sec" -> "$0}' supabase/config.toml
```

The `[auth.sms]` occurrence must read `true`. This phase adds test numbers to that file, so it is the phase most likely to disturb it.

- [ ] **Step 4: Write and commit the ledger**

`docs/superpowers/execution/2026-08-30-m1-phase3-ledger.md`, committed — a previous milestone's ledger lived in git-ignored scratch and was nearly destroyed with its worktree. It must record: the verification numbers with their commands; the config line; the per-task commit range; a **"Not verified"** section stating that no end-to-end run on a device has still ever been performed and that this phase's E2E test does not close that; and a carry-forward section listing every deferred finding, taken from the controller's running notes.

- [ ] **Step 5: Do NOT merge**

The merge decision belongs to the human. Stop here.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §4.3 shared re-entrancy guard | 3 |
| §4.4 domain rules as value objects | 3 (`Birthday.occasionYear`) |
| §4.1 narrow repositories | 4, 5, 7 |
| §4.2 injected dependencies | 4, 5, 7 (each registers in `app.dart`) |
| §5.1 celebrator count | 1 |
| §5.2 suppressed oracle | 2 |
| §6 occasion year | 3 |
| §7.1 person page | 6 |
| §7.2 compose sheet | 6 |
| §7.3 profile and lists | 8 |
| §8 testing | every task; closed out in 9 |
| §9 build order | task order |

**One spec correction made in this plan, not silently:** §4.1 gave `ProfileRepository` a `celebrating()` method. `GraphRepository.celebrations()` already returns that list, so Task 7 drops it and Task 8's list screen reuses `GraphRepository`. Trading a SOLID violation for a DRY one is not an improvement.

**Known gaps, deliberate**

- Tasks 5–9 specify tests as enumerated behaviours with reasoning rather than full source. The shapes are established in Tasks 1–4 and in Phase 2b's committed suites. **The enumerated assertions are mandatory, not suggestions.**
- `Wish.isMine` appears in Task 3's code block with an instruction to delete it before committing. That is deliberate: it marks a getter someone would otherwise add, and says why not to.

**Type consistency checked:** `ReentrancyGuard.guard`, `Birthday.occasionYear`, `Wish`, `BirthdayStat`, `PersonRepository`, `WishRepository`, `ProfileRepository` and the four `ApiEndpoints` constants are each defined once and referenced with the same names throughout. Phone numbers `+919999000007` through `010` are assigned to exactly one suite each.
