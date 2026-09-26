# M4 Phase 1 — Ops Console (Live Half) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A staff web console for the two things operable today — the product catalog and the delivery calendar — so a real city can be configured with real data.

**Architecture:** A second Flutter entry point (`lib/main_ops.dart`) built for web, reusing the app's models, `ApiClient`, `AppStrings` and Cubit patterns, but with its own router, its own `StaffAuthRepository` (email + password, not phone OTP) and its own `OpsRepository` (unfiltered reads plus writes — `GiftRepository`'s reads filter `is_active` and cannot show what staff must edit).

**Tech Stack:** Flutter 3.35.2 via FVM, Dart 3.9, `flutter_bloc` Cubits, `supabase_flutter`, Postgres 17 + pgTAP, Supabase CLI.

**Spec:** `docs/superpowers/specs/2026-09-27-m4-phase1-ops-console-design.md`

## Global Constraints

- **`[auth.sms] enable_confirmations = true` must remain at `supabase/config.toml:252`.** It guards a reproduced total-account-takeover bug covered by no test, and `supabase init` or a CLI upgrade rewrites that file. **Any task touching `config.toml` must run `grep -n enable_confirmations supabase/config.toml` and paste the output.**
- **`is_staff` is a database-administrator action only.** No screen, repository method or migration in this phase may set it (`20260822000003_profiles.sql:42`).
- **No new Dart packages.** The console reuses what `pubspec.yaml` already has.
- **Never `'$e'`.** Errors surface as `on AppFailure catch (f) => f.message`, then `catch (_) => AppStrings.somethingWentWrong`.
- **All copy in `lib/core/app_strings.dart`**, each string once, as a named `const`.
- **Repositories are narrow interfaces + impls**, registered with `RepositoryProvider` and **no `?? ConcreteImpl(...)` fallback**.
- **Every mutating action is wrapped in `ReentrancyGuard.guard(key, body)`** (`lib/core/reentrancy_guard.dart`). It claims its key **synchronously before the first await**, so a re-entrancy test must fire both calls without awaiting the first.
- **No date written to the database may come from `DateTime.now()` on the client.** Postgres runs UTC, this host runs IST; M3 Phase 1b shipped a fixture that passed by day and failed by night for exactly that reason. Dates come from an explicit user choice or a value read back from the database.
- **Every new assertion must be watched to FAIL** with its implementation reverted, then restored byte-identically (`md5`). If a revert fails for a different reason than the assertion targets, say so plainly rather than counting it as proof. Fourteen tests on this project have passed against the exact bug they were written to catch.
- **Do not run the app, launch a simulator, or use any browser-automation tool.** Verification is `supabase test db`, `fvm flutter analyze`, `fvm flutter test`, and `fvm flutter build web`.

### Environment traps (all three cost time in M3 Phase 1b)

1. `supabase test db` **without** a preceding `supabase db reset` reports a **false failure** after a container restart — fewer tests *and* a red result, looking exactly like a file aborting partway.
2. A mass contract failure (30+) usually means `supabase functions serve` died, not a regression.
3. `supabase db reset` **orphans an already-running `functions serve`**: Kong keeps a stale upstream and 502s every call, so all 18 Deno tests fail *including six this phase never touches*. Restarting serve alone does not fix it — restart Kong too (`docker restart supabase_kong_birthday_app`). The tell is that untouched suites fail.

## Review Focus

**Four of the five ways a staff user can misuse this console raise the same SQLSTATE.** `23514` is Postgres's generic CHECK-violation code, and on this schema it is shared by `products_price_positive`, `delivery_slots_window_ordered`, `delivery_slots_not_oversold`, `delivery_slots_capacity_non_negative` — plus seven explicit raises elsewhere. The console **cannot** tell them apart from the code, so each must be validated client-side with its own message. This is the same overload that caused M3 Phase 1b's Critical bug.

| # | Input / condition | What a reasonable person expects | Owning task |
|---|---|---|---|
| 1 | Price entered as `0`, negative, or non-numeric | A clear "price must be greater than zero" before any write — `products_price_positive check (price_minor > 0)` would otherwise return a bare `23514` | Task 4 |
| 2 | Slot window where end ≤ start | "The window must end after it starts" — `delivery_slots_window_ordered` otherwise returns `23514`, indistinguishable from a price problem | Task 5 |
| 3 | Capacity lowered below `reserved` | "Capacity cannot go below the N already reserved" — `delivery_slots_not_oversold` otherwise returns `23514` | Task 5 |
| 4 | A second slot with the same area, date and start time | "A window already starts at that time on that date" — this one raises **`23505`**, not `23514`, so it *is* distinguishable and must be mapped separately | Task 5 |
| 5 | The session expires mid-edit | Routed back to sign-in, not a generic failure — `mapError` returns `AuthFailure` for an `AuthException` (`lib/api/api_error_mapper.dart:14-16`) | Task 3 |

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/repositories/staff_auth_repository.dart` / `_impl.dart` | Email+password sign in/out, and reading the caller's own `is_staff`. Separate from `AuthRepository`, which owns phone OTP. |
| `lib/repositories/ops_repository.dart` / `_impl.dart` | Unfiltered catalog reads plus all staff writes. Separate from `GiftRepository`, whose reads filter `is_active`. |
| `lib/main_ops.dart` | The web entry point. |
| `lib/ops/ops_app.dart` | `MultiRepositoryProvider` + `MaterialApp.router` for the console. |
| `lib/ops/ops_router.dart` | `/signin`, `/catalog`, `/slots`, plus an `errorBuilder`. |
| `lib/ops/signin/` | `signin_cubit.dart`, `signin_state.dart`, `signin_screen.dart` |
| `lib/ops/catalog/` | `ops_catalog_cubit.dart`, `ops_catalog_state.dart`, `ops_catalog_screen.dart` |
| `lib/ops/slots/` | `ops_slots_cubit.dart`, `ops_slots_state.dart`, `ops_slots_screen.dart` |
| `lib/models/product.dart` | Add `Product.parsePriceMinor(String)` — the inverse of the existing `priceLabel`, living beside it. |
| `supabase/config.toml` | `[auth.email] enable_signup = false` — the only edit. |
| `test/repositories/ops_repository_test.dart` | Contract tests against real Supabase, including the non-staff refusal. |
| `test/ops/**` | Cubit and widget tests. |
| `docs/superpowers/execution/2026-XX-XX-m4-phase1-ledger.md` | Phase close. |

**Task order matters.** Task 1 builds the data layer every screen consumes. Task 2's config change is independent and small, but must land before Task 3's sign-in screen is verified manually. Tasks 4 and 5 both consume Task 1's `OpsRepository` and are otherwise independent.

---

### Task 1: The data layer — `OpsRepository` and `StaffAuthRepository`

**Files:**
- Create: `lib/repositories/staff_auth_repository.dart`, `lib/repositories/staff_auth_repository_impl.dart`
- Create: `lib/repositories/ops_repository.dart`, `lib/repositories/ops_repository_impl.dart`
- Modify: `lib/models/product.dart` (add `parsePriceMinor`)
- Create: `test/repositories/ops_repository_test.dart`
- Create: `test/models/product_price_parse_test.dart`

**Interfaces:**
- Consumes: `SupabaseClient` via `ApiClient.instance`; `mapError(Object) → AppFailure` (`lib/api/api_error_mapper.dart:11`); models `ServiceArea`, `Product`, `DeliverySlot`; `ApiParams.serviceAreas`/`products`/`deliverySlots`/`priceMinor`/`isActive`/`slotDate`/`windowStart`/`windowEnd`/`capacity`/`reserved`/`serviceAreaId`/`name`/`id`.
- Produces, consumed by Tasks 3–5:

```dart
abstract interface class StaffAuthRepository {
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  /// The signed-in caller's own `profiles.is_staff`. False when no session.
  Future<bool> isStaff();
}

abstract interface class OpsRepository {
  Future<List<ServiceArea>> allServiceAreas();
  /// Active AND inactive — staff must see what they are about to reactivate.
  Future<List<Product>> allProductsIn(int serviceAreaId);
  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  });
  Future<Product> setProductActive(int productId, {required bool isActive});
  /// Inclusive of both bounds, ordered by slot_date then window_start.
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  });
  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  });
  Future<DeliverySlot> setSlotCapacity(int slotId, {required int capacity});
}
```

- [ ] **Step 1: Write the failing price-parse test**

`Product.priceLabel` renders paise as rupees (`lib/models/product.dart`). Its inverse belongs beside it, not in a screen. Create `test/models/product_price_parse_test.dart`:

```dart
import 'package:birthday_app/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsePriceMinor accepts rupees with and without paise', () {
    expect(Product.parsePriceMinor('849'), 84900);
    expect(Product.parsePriceMinor('849.50'), 84950);
    // The zero-padding case, the mirror of priceLabel's own trap: a naive
    // parse of '849.5' yields 8495 rather than 84950.
    expect(Product.parsePriceMinor('849.5'), 84950);
    expect(Product.parsePriceMinor(' 849 '), 84900);
  });

  test('parsePriceMinor returns null for anything that is not a positive price', () {
    // products_price_positive is `check (price_minor > 0)` --
    // 20260822000006_catalog_slots.sql:21. Zero is NOT allowed.
    for (final bad in ['', '0', '0.00', '-5', 'abc', '8.499', '1,000']) {
      expect(Product.parsePriceMinor(bad), isNull, reason: 'should reject "$bad"');
    }
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
fvm flutter test test/models/product_price_parse_test.dart
```

Expected: a compile failure — `parsePriceMinor` is not defined.

- [ ] **Step 3: Implement `parsePriceMinor`**

Add to `Product` in `lib/models/product.dart`, directly beneath `priceLabel`, with a comment saying it is that getter's inverse and naming `products_price_positive` as the reason zero is rejected. Return `int?` — `null` means "not a valid price", which the screen turns into its own message rather than letting the database answer with a bare `23514`.

Accept an optional `.` with **one or two** decimal places. Reject empty, non-numeric, more than two decimals, thousands separators, and anything `<= 0`.

- [ ] **Step 4: Run and verify green**

```bash
fvm flutter test test/models/product_price_parse_test.dart
```

Expected: 2 tests pass.

- [ ] **Step 5: Write the repository interfaces**

Create both interface files following `lib/repositories/gift_repository.dart`'s shape: `abstract interface class`, a doc comment on the class saying what one responsibility it owns and what it is deliberately *not* folded into, and a doc comment on any method whose contract is not obvious from its name.

On `OpsRepository`, `allProductsIn`'s doc must say: **unlike `GiftRepository.productsIn`, this does not filter `is_active`, because a console that hid inactive products could never show the row it exists to reactivate.**

- [ ] **Step 6: Write the implementations**

Both follow `lib/repositories/gift_repository_impl.dart`: `class XImpl implements X`, `const XImpl(this._client)`, `final SupabaseClient _client`, every method body wrapped in `try { … } catch (e) { throw mapError(e); }`.

Use `ApiParams` constants for every table and column name — never a bare string literal.

`slotsBetween` orders by `slot_date` then `window_start` (`.order(ApiParams.slotDate).order(ApiParams.windowStart)`) so the screen never has to sort.

`isStaff()` reads the caller's own row: `select is_staff from profiles where id = auth.uid()`. Return `false` when there is no session rather than throwing — a signed-out caller is not an error here.

- [ ] **Step 7: Write the contract test — the non-staff refusal is the one that matters**

Create `test/repositories/ops_repository_test.dart`, tagged `contract`, following `test/repositories/gift_repository_test.dart`'s harness exactly: the same `psql()` helper that `docker exec`s into `supabase_db_birthday_app` (it is how fixtures reach tables no repository may write), and **this suite's own phone number** — `flutter test` runs files concurrently and GoTrue's OTP rate limit is cross-process, so two suites sharing a number collide.

Assertions:

1. `allProductsIn` returns **both** an active and an inactive product — the discriminating one, since `GiftRepository.productsIn` would return only the active.
2. `slotsBetween` returns slots in date order and **excludes** one outside the range.
3. **A non-staff caller is refused on `createProduct`.** RLS (`products_staff_write`) is the boundary; assert a thrown `AppFailure`.
4. **A non-staff caller is refused on `createSlot`** and on `setSlotCapacity`.
5. A **staff** caller succeeds at `createProduct` — promote via `psql()` (`update public.profiles set is_staff = true where id = '<uuid>'`), because `authenticated` has no update grant on that column (`20260822000003_profiles.sql:54`).

**Demote at the end of the staff test** (`update ... set is_staff = false`). M3 Phase 1b left a promotion in place and it was inert only because that test happened to be last; a test added after it would inherit staff and fail a neighbour for a reason that looks nothing like the cause.

Every date in a fixture comes from a value read back from the database (`returning id, slot_date`), never from `DateTime.now()`.

- [ ] **Step 8: Run the contract suite and watch the refusals fail first**

Stack must be up. Before running: if you have just run `supabase db reset`, restart `supabase functions serve --no-verify-jwt` **and** `docker restart supabase_kong_birthday_app`.

```bash
KEY=$(supabase status 2>/dev/null | grep -i "publishable" | awk -F'│' '{print $3}' | tr -d ' ')
fvm flutter test test/repositories/ops_repository_test.dart --dart-define=SUPABASE_ANON_KEY="$KEY"
```

- [ ] **Step 9: Prove the refusals are real**

Temporarily add `to authenticated using (true) with check (true)` as a second permissive policy on `products` in a scratch migration, `supabase db reset`, and confirm assertions 3 and 4 now **fail** (the write succeeds). Remove it, reset, confirm green, and verify the migrations directory is byte-identical (`git status` clean). This proves the refusal comes from RLS rather than from something incidental.

- [ ] **Step 10: Verify and commit**

```bash
fvm flutter analyze
fvm flutter test --exclude-tags=contract
git add lib/repositories/staff_auth_repository.dart lib/repositories/staff_auth_repository_impl.dart \
        lib/repositories/ops_repository.dart lib/repositories/ops_repository_impl.dart \
        lib/models/product.dart test/repositories/ops_repository_test.dart \
        test/models/product_price_parse_test.dart
git commit -m "feat(ops): the console's data layer

OpsRepository reads unfiltered, unlike GiftRepository.productsIn, which
filters is_active -- a console built on that read could never show the
inactive product it exists to reactivate. StaffAuthRepository is separate
from AuthRepository, which owns phone OTP.

Product.parsePriceMinor is priceLabel's inverse and returns null rather
than letting products_price_positive answer with a bare 23514."
```

---

### Task 2: Close email self-signup

**Files:**
- Modify: `supabase/config.toml` (one setting)
- Create: `supabase/functions/test-signup.sh`

**Interfaces:** none consumed or produced; this task is configuration plus a manual check.

**Read before editing.** `config.toml` carries `[auth.sms] enable_confirmations = true` at line 252, guarding a reproduced account-takeover bug that no test covers, and CLI operations rewrite the whole file. Record the guard and the file's `md5` before you touch it and verify both after.

**No automated test can cover this**, exactly like `[functions.confirm] verify_jwt = false` in M3 Phase 1b: it is a gateway-level setting, and the Dart suite never reaches the signup endpoint. M3 Phase 1b solved the equivalent problem with `test-gateway.sh`, a script run manually against a specially-configured server. This task does the same. **Do not claim the setting is test-covered.**

- [ ] **Step 1: Record the guard**

```bash
grep -n "enable_confirmations" supabase/config.toml
md5 -q supabase/config.toml
```

Paste both. Line 252 must read `enable_confirmations = true`.

- [ ] **Step 2: Write the check script, and watch it FAIL against current config**

Create `supabase/functions/test-signup.sh`, executable, modelled on `test-gateway.sh`'s header style. It must state that it requires a running stack, `curl` `POST /auth/v1/signup` with a throwaway email and password and the anon key, and **fail loudly if the response indicates a user was created**. Print a one-line summary on success; exit non-zero with the observed status and body on failure.

Run it now, before changing the config:

```bash
./supabase/functions/test-signup.sh
```

Expected: **FAIL** — signup currently succeeds. Paste the output. This is the negative control, and running it first is what makes the change in Step 4 meaningful.

- [ ] **Step 3: Delete any user the negative control created**

The probe in Step 2 created a real row. Remove it so the local database is not polluted:

```bash
docker exec -i supabase_db_birthday_app psql -U postgres -c \
  "delete from auth.users where email like 'signupprobe%';"
```

Use a fixed `signupprobe+<timestamp>@example.com` shape in the script so this delete is precise.

- [ ] **Step 4: Make the change**

In `supabase/config.toml`'s `[auth.email]` block, set `enable_signup = false`, with a comment above it explaining: staff accounts are provisioned by an administrator (`admin.auth.admin.createUser` plus a DBA `update profiles set is_staff = true`), consumer accounts arrive by phone OTP, so **no path in this product needs email self-signup**; leaving it open lets a stranger occupy an `auth.users` row with no `people` row behind it, which the project has no way to clean up.

- [ ] **Step 5: Restart, re-run, and verify the guard survived**

```bash
supabase stop && supabase start
./supabase/functions/test-signup.sh
grep -n "enable_confirmations" supabase/config.toml
git diff supabase/config.toml
```

Expected: the script now **passes**; line 252 still reads `enable_confirmations = true`; the diff shows **only** the `enable_signup` line and its comment.

- [ ] **Step 6: Commit**

```bash
git add supabase/config.toml supabase/functions/test-signup.sh
git commit -m "feat(config): close email self-signup

No path in this product needs it -- staff accounts are provisioned by an
administrator, consumers arrive by phone OTP. Leaving it open let a
stranger occupy an auth.users row with no people row behind it.

Not covered by any automated suite: this is a gateway-level setting the
Dart tests never reach, the same shape as verify_jwt in M3 Phase 1b.
test-signup.sh is the manual check, and it was watched to fail against
the old config before the change."
```

---

### Task 3: The console shell and sign-in

**Files:**
- Create: `lib/main_ops.dart`, `lib/ops/ops_app.dart`, `lib/ops/ops_router.dart`
- Create: `lib/ops/signin/signin_cubit.dart`, `signin_state.dart`, `signin_screen.dart`
- Modify: `lib/core/app_strings.dart`
- Create: `test/ops/signin_cubit_test.dart`, `test/ops/ops_router_test.dart`

**Interfaces:**
- Consumes: `StaffAuthRepository` (Task 1) — `signIn`, `signOut`, `isStaff`; `ApiClient.init()`; `mapError`.
- Produces: `OpsApp` widget; `buildOpsRouter(SignInCubit)`; `SignInCubit` with `submit({email, password})` and `signOut()`; `SignInState = SignInIdle | SignInBusy | SignInReady | SignInRefused(message) | SignInError(message)`.

- [ ] **Step 1: Add the strings**

```dart
  // Ops console
  static const opsTitle = 'Ops console';
  static const opsEmail = 'Email';
  static const opsPassword = 'Password';
  static const opsSignIn = 'Sign in';
  static const opsSignOut = 'Sign out';
  static const opsNotStaff =
      'That account is not a staff account.';
  static const opsSessionExpired =
      'Your session has expired. Please sign in again.';
  static const opsCatalogTab = 'Catalog';
  static const opsSlotsTab = 'Delivery slots';
```

- [ ] **Step 2: Write the failing cubit tests**

Create `test/ops/signin_cubit_test.dart` with a fake `StaffAuthRepository`. Cover:

```
1. submit() emits SignInBusy then SignInReady when signIn succeeds and
   isStaff() returns true.
2. A successful signIn whose isStaff() is FALSE emits SignInRefused with
   AppStrings.opsNotStaff, AND calls signOut() on the fake exactly once.
   Assert the call count -- the refusal must not leave a usable session
   behind.
3. An AuthFailure from signIn surfaces its own message, not the generic one.
4. A non-AppFailure surfaces AppStrings.somethingWentWrong. Assert that exact
   string: an isA<SignInError>() check alone passes for either branch.
5. A second submit() while the first is in flight is ignored. Gate the fake on
   a Completer and fire both calls WITHOUT awaiting the first -- the guard
   claims its key synchronously, so a test that awaits proves nothing.
```

- [ ] **Step 3: Run and watch them fail**

```bash
fvm flutter test test/ops/signin_cubit_test.dart
```

Expected: compile failure — `SignInCubit` does not exist.

- [ ] **Step 4: Write the state, cubit and screen**

`SignInCubit extends Cubit<SignInState> with ReentrancyGuard`, every action through `guard(key, body)`. Error handling in the `lib/features/timeline/timeline_cubit.dart` shape — `on AppFailure catch (f)` then `catch (_)`, never `'$e'`.

**Review Focus #5:** an `AuthFailure` anywhere in the console means the session is gone. `mapError` already returns `AuthFailure` for an `AuthException` (`lib/api/api_error_mapper.dart:14-16`). The router (Step 5) sends any `AuthFailure` back to `/signin` with `AppStrings.opsSessionExpired` rather than rendering it as a generic error on whatever screen the user was on.

`signin_screen.dart`: two `TextField`s (the password one `obscureText: true`), a submit button disabled while `SignInBusy`, and the refusal/error message rendered plainly.

- [ ] **Step 5: Write the entry point, app and router**

`lib/main_ops.dart` mirrors `lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'ops/ops_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();
  runApp(const OpsApp());
}
```

`ops_app.dart` follows `lib/app.dart`: a `MultiRepositoryProvider` with `.value` providers for `StaffAuthRepository` and `OpsRepository` (**no fallback**), a `BlocProvider.value` for the `SignInCubit`, and `MaterialApp.router`.

`ops_router.dart` exposes `buildOpsRouter(SignInCubit)` with `/signin`, `/catalog`, `/slots`, a redirect sending an unauthenticated caller to `/signin`, and — unlike the consumer router, which shipped without one until M3 Phase 1a's review — **an `errorBuilder`**, so an unmatched location is not a dead end.

- [ ] **Step 6: Write the router arrival test**

Create `test/ops/ops_router_test.dart`. Assert, through the **real** `buildOpsRouter`: an unauthenticated caller at `/catalog` lands on `/signin`; and a signed-in staff caller at `/catalog` stays. Testing an inline router instead of the real one is exactly what let a dead end survive in M3 Phase 1b — assert **arrival**, not that a widget exists.

- [ ] **Step 7: Run, verify green, prove each assertion can fail**

```bash
fvm flutter analyze && fvm flutter test test/ops/
```

Three reverts, each restored byte-identically (`md5`): remove the `signOut()` call from the not-staff branch (test 2 must fail on the call count); change the non-`AppFailure` branch to `'$e'` (test 4 must fail on the exact string); remove the `guard(...)` wrapper (test 5 must fail with two recorded calls). Paste all three transcripts.

- [ ] **Step 8: Commit**

```bash
git add lib/main_ops.dart lib/ops/ lib/core/app_strings.dart test/ops/
git commit -m "feat(ops): the console shell and staff sign-in

Email and password, not phone OTP: [auth.email] enable_confirmations is
false, so an admin-provisioned account sends no email and needs no SMTP.
A non-staff account is signed out immediately -- RLS is the boundary, so
this is legibility, not security. An AuthFailure anywhere routes back to
sign-in rather than rendering as a generic error in place."
```

---

### Task 4: The catalog screen

**Files:**
- Create: `lib/ops/catalog/ops_catalog_cubit.dart`, `ops_catalog_state.dart`, `ops_catalog_screen.dart`
- Modify: `lib/core/app_strings.dart`
- Create: `test/ops/ops_catalog_cubit_test.dart`, `test/ops/ops_catalog_screen_test.dart`

**Interfaces:**
- Consumes: `OpsRepository.allServiceAreas`, `allProductsIn`, `createProduct`, `setProductActive` (Task 1); `Product.parsePriceMinor` (Task 1); `Product.priceLabel` (existing).
- Produces: `OpsCatalogCubit(OpsRepository)` with `load()`, `selectArea(int)`, `addProduct({name, flavour, size, priceText})`, `toggleActive(int productId, bool)`; `OpsCatalogState = OpsCatalogLoading | OpsCatalogLoaded(areas, selectedAreaId, products) | OpsCatalogError(message)`.

- [ ] **Step 1: Add the strings**

```dart
  static const opsAddProduct = 'Add product';
  static const opsProductName = 'Name';
  static const opsProductFlavour = 'Flavour (optional)';
  static const opsProductSize = 'Size (optional)';
  static const opsProductPrice = 'Price in rupees';
  static const opsPriceInvalid =
      'Enter a price greater than zero, with at most two decimal places.';
  static const opsNameRequired = 'A product needs a name.';
  static const opsActive = 'Active';
  static const opsInactive = 'Inactive';
  static const opsNoAreas = 'No service areas exist yet.';
  static const opsNoProducts = 'No products in this area yet.';
```

- [ ] **Step 2: Write the failing cubit tests**

```
1. load() emits Loading then Loaded with areas, the first area preselected,
   and that area's products.
2. selectArea() swaps products WITHOUT refetching areas -- assert the fake
   recorded ONE allServiceAreas() call and TWO allProductsIn() calls.
3. Loaded includes INACTIVE products. Seed the fake with one active and one
   inactive and assert both appear. This is the whole reason OpsRepository
   exists rather than reusing GiftRepository.productsIn.
4. REVIEW FOCUS #1 -- addProduct with priceText '0', '-5', 'abc' and '8.499'
   emits OpsCatalogError with AppStrings.opsPriceInvalid and calls
   createProduct ZERO times. Assert the call count: the point is that the
   write never reaches the database, where products_price_positive would
   return a bare 23514 indistinguishable from three other constraints.
5. addProduct with an empty name emits opsNameRequired and does not write.
6. A failing allServiceAreas() surfaces OpsCatalogError with a human message;
   a non-AppFailure falls back to AppStrings.somethingWentWrong -- assert that
   exact string.
7. A second addProduct() while the first is in flight is ignored. Completer-
   gated, both fired without awaiting the first; assert ONE createProduct call.
```

- [ ] **Step 3: Run and watch them fail**

```bash
fvm flutter test test/ops/ops_catalog_cubit_test.dart
```

Expected: compile failure — `OpsCatalogCubit` does not exist.

- [ ] **Step 4: Write the state, cubit and screen**

`OpsCatalogCubit extends Cubit<OpsCatalogState> with ReentrancyGuard`.

`addProduct` validates **before** writing: name non-empty, and `Product.parsePriceMinor(priceText)` non-null. Only then does it call `createProduct`.

`ops_catalog_screen.dart`: an area selector, a list of products showing name, flavour/size, `priceLabel`, and an active toggle; a form to add one. Assert on a `DropdownButton`'s `.value` in tests, never `find.text` — all its items stay mounted in an `IndexedStack` and are not `Offstage`-wrapped, so a text assertion passes regardless of selection.

- [ ] **Step 5: Write the widget test**

Create `test/ops/ops_catalog_screen_test.dart`: an inactive product renders visibly marked (`AppStrings.opsInactive`), and toggling calls `setProductActive` with the right id and value — assert a call count on a fake, not that a switch renders.

- [ ] **Step 6: Run, verify green, prove the assertions can fail**

Three reverts, each restored byte-identically: call `createProduct` before validating (test 4 must fail on the call count); make `allProductsIn` filter to active only in the fake's expectations (test 3 must fail); remove the `guard(...)` (test 7 must fail). Paste the transcripts.

- [ ] **Step 7: Commit**

```bash
git add lib/ops/catalog/ lib/core/app_strings.dart test/ops/
git commit -m "feat(ops): the catalog screen

Shows inactive products, which is the point -- GiftRepository.productsIn
filters is_active and could never display the row this screen exists to
reactivate.

Prices are validated before the write. products_price_positive would
otherwise answer with a bare 23514, the same generic code as three other
constraints on this schema, leaving the console unable to say which one
the user tripped."
```

---

### Task 5: The delivery-slot capacity editor

**Files:**
- Create: `lib/ops/slots/ops_slots_cubit.dart`, `ops_slots_state.dart`, `ops_slots_screen.dart`
- Modify: `lib/core/app_strings.dart`
- Create: `test/ops/ops_slots_cubit_test.dart`, `test/ops/ops_slots_screen_test.dart`

**Interfaces:**
- Consumes: `OpsRepository.allServiceAreas`, `slotsBetween`, `createSlot`, `setSlotCapacity` (Task 1); `DeliverySlot.remaining` and `.isBookable` (existing, `lib/models/delivery_slot.dart:26,28`).
- Produces: `OpsSlotsCubit(OpsRepository)` with `load()`, `selectArea(int)`, `setRange({from, to})`, `addSlot({slotDate, windowStart, windowEnd, capacity})`, `changeCapacity(int slotId, int capacity)`; `OpsSlotsState = OpsSlotsLoading | OpsSlotsLoaded(areas, selectedAreaId, from, to, slots) | OpsSlotsError(message)`.

- [ ] **Step 1: Add the strings**

```dart
  static const opsAddSlot = 'Add delivery window';
  static const opsSlotDate = 'Date';
  static const opsWindowStart = 'Starts';
  static const opsWindowEnd = 'Ends';
  static const opsCapacity = 'Capacity';
  static const opsReservedTemplate = '%s reserved';
  static const opsWindowOrder = 'The window must end after it starts.';
  static const opsCapacityBelowReservedTemplate =
      'Capacity cannot go below the %s already reserved.';
  static const opsCapacityNegative = 'Capacity cannot be negative.';
  static const opsDuplicateWindow =
      'A window already starts at that time on that date.';
  static const opsNoSlots = 'No delivery windows in this range.';
```

- [ ] **Step 2: Write the failing cubit tests — these are the Review Focus cases**

```
1. load() emits Loading then Loaded with areas, first area preselected, and
   that area's slots for the default range.
2. REVIEW FOCUS #2 -- addSlot with windowEnd <= windowStart (try '13:00'/'13:00'
   and '13:00'/'10:00') emits OpsSlotsError with AppStrings.opsWindowOrder and
   calls createSlot ZERO times. delivery_slots_window_ordered would otherwise
   return a bare 23514.
3. REVIEW FOCUS #3 -- changeCapacity below a slot's `reserved` emits
   OpsSlotsError with opsCapacityBelowReservedTemplate carrying the reserved
   count, and calls setSlotCapacity ZERO times. Seed the fake with a slot whose
   reserved is 3 and attempt capacity 2. delivery_slots_not_oversold would
   otherwise return a bare 23514.
4. changeCapacity to a NEGATIVE number emits opsCapacityNegative and does not
   write (delivery_slots_capacity_non_negative).
5. changeCapacity EQUAL to reserved is ALLOWED and does write -- the constraint
   is `reserved <= capacity`, so equality is legal. Without this, a fix that
   rejected `<=` instead of `<` would pass every other test.
6. REVIEW FOCUS #4 -- a ServerFailure with code '23505' from createSlot surfaces
   AppStrings.opsDuplicateWindow, NOT the generic message. This is the one
   constraint with its own distinguishable code
   (delivery_slots_unique_window), so it gets its own message.
7. Any OTHER ServerFailure surfaces its own message; a non-AppFailure falls back
   to AppStrings.somethingWentWrong -- assert that exact string.
8. A second addSlot() while the first is in flight is ignored. Completer-gated,
   both fired without awaiting; assert ONE createSlot call.
```

- [ ] **Step 3: Run and watch them fail**

```bash
fvm flutter test test/ops/ops_slots_cubit_test.dart
```

Expected: compile failure — `OpsSlotsCubit` does not exist.

- [ ] **Step 4: Write the state, cubit and screen**

`OpsSlotsCubit extends Cubit<OpsSlotsState> with ReentrancyGuard`. All three validations happen **before** the write.

Map `23505` to `opsDuplicateWindow` by checking `f is ServerFailure && f.code == '23505'`. Do **not** map bare `23514` to any specific message — four different constraints share it, so an unanticipated one is rendered as the generic failure **and logged** via `lib/core/logger.dart`, never guessed at.

**No `DateTime.now()` anywhere in this cubit or screen.** The default range comes from the user's date pickers; slot dates come from a picker or from a value read back. Postgres runs UTC and this host runs IST.

`ops_slots_screen.dart`: an area selector, two date pickers, a list showing date, window, `capacity`, `reserved` and `remaining`, an inline capacity editor, and a form to add a window.

- [ ] **Step 5: Write the widget test**

Create `test/ops/ops_slots_screen_test.dart`: a slot with `reserved: 3, capacity: 5` renders both numbers, and attempting capacity `2` shows the refusal message with `3` interpolated — proving the message carries the real count rather than a fixed string.

- [ ] **Step 6: Run, verify green, prove the assertions can fail**

Four reverts, each restored byte-identically: remove the window-order check (test 2 fails); remove the capacity-vs-reserved check (test 3 fails); change that check from `<` to `<=` (**test 5** fails — the equality case, which is why it exists); remove the `23505` branch (test 6 fails). Paste all four transcripts.

- [ ] **Step 7: Commit**

```bash
git add lib/ops/slots/ lib/core/app_strings.dart test/ops/
git commit -m "feat(ops): the delivery-slot capacity editor

Every way to misuse this screen is validated before the write, because
four of them -- price, window order, capacity below reserved, negative
capacity -- all raise 23514, Postgres's generic CHECK code, and the
console cannot tell them apart from the code alone.

The duplicate-window case is the exception: delivery_slots_unique_window
raises 23505, which IS distinguishable, so it gets its own message.
Anything else that arrives as 23514 is rendered generically and logged
rather than guessed at."
```

---

### Task 6: Phase close — web build, cold verification, ledger

**Files:**
- Create: `docs/superpowers/execution/2026-XX-XX-m4-phase1-ledger.md` (use the actual date)

- [ ] **Step 1: Build the web bundle**

This is the phase's real deliverable and **no Dart-VM test can assert it**.

```bash
fvm flutter build web -t lib/main_ops.dart --dart-define=SUPABASE_ANON_KEY=placeholder
```

Expected: a successful build into `build/web/`. Report the exit status and the bundle's size. If it fails, that is a finding — this is the project's first web target, and a toolchain problem here is exactly the unknown the M3 spec worried about.

**Do not** commit `build/`. Confirm it is gitignored; if it is not, add it.

- [ ] **Step 2: Cold verification, every suite**

```bash
supabase db reset
supabase test db                                   # expect Files=32, Tests=295, PASS
# restart serve AND kong after the reset (trap 3):
pkill -f "supabase functions serve"; nohup supabase functions serve --no-verify-jwt &
sleep 12; docker restart supabase_kong_birthday_app; sleep 8
./supabase/functions/test.sh                       # expect 18 passed
./supabase/functions/test-signup.sh                # expect pass (Task 2)
fvm flutter analyze                                # expect clean
fvm flutter test --exclude-tags=contract           # expect 207 + this phase's new tests
KEY=$(supabase status 2>/dev/null | grep -i "publishable" | awk -F'│' '{print $3}' | tr -d ' ')
fvm flutter test test/repositories test/e2e --dart-define=SUPABASE_ANON_KEY="$KEY"
```

Record counts before and after. Baselines at this phase's start: pgTAP 32/295 · Deno 18 · analyze clean · 207 non-contract · 47 contract.

- [ ] **Step 3: Verify the timezone property**

The console writes `slot_date` values. Prove no Dart-derived date leaked in:

```bash
grep -rn "DateTime.now" lib/ops/ || echo "none — every date is user-chosen or read back"
TZ='Pacific/Kiritimati' fvm flutter test test/ops/
TZ='Pacific/Midway' fvm flutter test test/ops/
```

Both must pass. That is a 25-hour spread, and it is the technique that caught M3 Phase 1b's day/night fixture.

- [ ] **Step 4: Re-verify the config guard**

```bash
grep -n "enable_confirmations" supabase/config.toml
git diff main -- supabase/config.toml
```

Line 252 must read `enable_confirmations = true`, and the whole-phase diff of that file must show **only** the `enable_signup = false` line and its comment.

- [ ] **Step 5: Write the ledger**

Follow `docs/superpowers/execution/2026-09-13-m3-phase1b-ledger.md`'s structure: final verification numbers, the config guard, per-task commit ranges, **what is not verified**, carried forward, and every ruling with its cost if wrong.

State plainly under "Not verified":

- **`[auth.email] enable_signup = false` is covered by no automated suite** — `test-signup.sh` is a manual check requiring a restarted stack, the same shape as `test-gateway.sh` for `verify_jwt`.
- **The web bundle has never been loaded in a browser.** `flutter build web` succeeding is not the same as the console working. That is a human step.
- **No device or simulator run has ever happened, in any phase.**
- **Four of M4's five specced surfaces are not built** — manifest, gift detail with logged address read, status transitions, refunds — because they need gifts past `paid`. M4 Phase 2 owns them.

Carry forward: `address_access_log.staff_profile_id` is `ON DELETE RESTRICT` on an immutable table and becomes live when Phase 2 ships the address read — the same shape as the `gifts.sender_profile_id` regression M3 Phase 1a's final review caught, so Phase 2 must decide the policy before shipping; the `23514` overload; and M3 Phase 1b's open items.

- [ ] **Step 6: Commit and STOP**

```bash
git add docs/superpowers/execution/
git commit -m "docs(ledger): M4 Phase 1 cold-verification record and carry-forwards"
```

**Do not merge. Do not touch `main`.** A whole-branch review comes first, then the merge decision is the user's.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §2 the split, and what is left out | No task builds manifest/detail/transitions/refunds; Task 6 records why |
| §3 second Flutter entry point, web build | Task 3 (entry, app, router), Task 6 Step 1 (build) |
| §4 email+password, admin-provisioned | Task 3 |
| §4 `enable_signup = false` hardening | Task 2 |
| §4.1 `is_staff` check is honesty, not the boundary | Task 3 Step 2 test 2 (signs out); Task 1 Step 7 assertions 3–5 (RLS is the boundary) |
| §5 `OpsRepository` separate, unfiltered reads | Task 1 |
| §5 `StaffAuthRepository` separate | Task 1 |
| §6 sign-in screen | Task 3 |
| §6 service areas & products | Task 4 |
| §6 delivery slots, capacity ≥ reserved | Task 5 |
| §7 one source of truth for dates | Global Constraints; Task 5 Step 4; Task 6 Step 3 |
| §8 testing | Every task's own steps |
| §9 not verified | Task 6 Step 5 |
| §10 risks | Task 6 Step 1 (web build), Task 2 (config) |
| §11 carried forward | Task 6 Step 5 |
| §12 open questions | Hosting is out of scope (Task 6 Step 1 builds, does not deploy); creating service areas stays a DBA action — no task adds it |

**Placeholder scan:** none. The ledger filename uses `2026-XX-XX` because the close date is unknown at planning time; Task 6 says to use the actual date.

**Type consistency:** `OpsRepository`'s seven method signatures are spelled identically in Task 1's interface block and in Tasks 4 and 5's Interfaces blocks. `Product.parsePriceMinor` is produced in Task 1 and consumed in Task 4. `SignInState`'s five variants are produced in Task 3 and consumed nowhere else. `DeliverySlot.remaining`/`.isBookable` are existing members, verified present at `lib/models/delivery_slot.dart:26,28`.

**Review Focus:** all five lines have a test in the owning task — #1 Task 4 Step 2 test 4; #2 Task 5 Step 2 test 2; #3 Task 5 Step 2 test 3; #4 Task 5 Step 2 test 6; #5 Task 3 Step 4 plus the router redirect in Step 5. Task 5 test 5 (capacity *equal* to reserved is allowed) was added during this review: without it, a fix that rejected `<=` rather than `<` would pass every other assertion while forbidding a legal edit.
