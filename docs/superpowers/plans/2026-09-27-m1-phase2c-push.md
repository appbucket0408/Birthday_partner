# M1 Phase 2c (push) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a birthday reminder from the existing outbox to a real Android device, and close the push-content injection hole that turning on FCM credentials would otherwise arm.

**Architecture:** The database half of the reminder pipeline already exists and is under pgTAP; this plan adds only the two missing ends. On the client, a new narrow `PushRepository` owns the device-token lifecycle (permission, FCM token, `register_device_token`, refresh, deletion), replacing a stub inside `SettingsRepositoryImpl`. On the server, `drain_reminders` gains real FCM HTTP v1 credentials minted in-function from a service account, plus sanitisation of the attacker-controlled `display_name` it interpolates today, and a `pg_net` cron finally triggers it.

**Tech Stack:** Flutter 3.35.2 via FVM, `firebase_core`, `firebase_messaging`, Deno + WebCrypto (RSASSA-PKCS1-v1_5 / SHA-256), Postgres 17, pgTAP, `pg_cron`, `pg_net`, Supabase CLI 2.78.1.

**Spec:** `docs/superpowers/specs/2026-09-27-m1-phase2c-push-design.md`

## Global Constraints

- **Android only.** `flutterfire configure --platforms=android`. Do not register an iOS app; there is no APNs key and a registered iOS app without one delivers nothing while looking configured. (Spec §2)
- **Never run `supabase config push`**, and never add phone numbers to a hosted project's test-OTP feature. `config.toml` carries `[auth.sms.test_otp]` with twelve hardcoded-`123456` numbers. (Spec §3)
- **`[auth.sms] enable_confirmations = true`** at `supabase/config.toml` guards a reproduced total-account-takeover and is covered by no test. Never remove it. Locate it by grepping for the text, never by line number — it has moved twice.
- **Name sanitisation limit: 64 code points**, counted by iterating the string, never `.length`. Empty result becomes the literal `Someone`. (Spec §5)
- **OAuth token cache margin: 5 minutes.** Re-mint when less than 300s remain. Scope is exactly `https://www.googleapis.com/auth/firebase.messaging`. (Spec §6)
- **Drain cadence: `*/10 * * * *`.** (Spec §7)
- **Dry-run must survive.** With no `FCM_SERVICE_ACCOUNT` present the function still reports `{dryRun: true, would_send: N}`. Every existing test depends on this. (Spec §6)
- **The legacy `fcm.googleapis.com/fcm/send` endpoint is dead** (shut down by Google in 2024). Only `https://fcm.googleapis.com/v1/projects/{id}/messages:send`.
- Do not run the app, do not launch a simulator, and do not use any browser-automation tool. Task 9 is performed by the human partner.

## Review Focus

These are the failure modes the spec implies that no task's happy path would catch. Each has a test assigned to the task that owns the code.

1. **A name clamped mid-astral-character.** A `display_name` of 70 emoji clamped with `.slice(0, 64)` on UTF-16 units emits a lone surrogate and a mojibake notification. → Task 5.
2. **A permanently dead FCM token.** FCM replies `404 UNREGISTERED` for a token the OS revoked; nothing deletes the row, so every future reminder for that user burns attempts against a corpse. → Task 6.
3. **The OAuth exchange failing.** If a 5xx from `oauth2.googleapis.com` is treated as a per-message failure, one Google hiccup marks the whole batch failed and consumes `attempts` for reminders that were never attempted. → Task 6.
4. **Permission denied, then granted later in OS settings.** Nothing re-runs registration, so a user who changes their mind in Android settings silently never receives a reminder again. → Task 3.
5. **`net.http_post` never raising.** pg_net queues asynchronously and returns a request id; a wrong URL or a dead function produces a cron that reports success forever while nothing is delivered. → Task 7.

---

## File Structure

**Created:**
- `lib/repositories/push_repository.dart` — the interface. Permission, registration, deletion, tap routes.
- `lib/repositories/push_repository_impl.dart` — the only file that imports `firebase_messaging`.
- `lib/features/settings/push_cubit.dart` / `push_state.dart` — drives permission + registration from the timeline screen.
- `lib/core/push_routes.dart` — `routeForPayload`, a pure function. The testable seam for tap handling.
- `supabase/migrations/20260927000001_batch_person_id.sql` — adds `subject_person_id` to the batch.
- `supabase/migrations/20260927000002_drain_cron.sql` — `private.drain_config`, `private.trigger_drain`, the cron.
- `supabase/functions/drain_reminders/fcm.ts` — sanitisation + OAuth2 minting, importable and unit-testable.
- `supabase/functions/drain_reminders/index.test.ts` — Deno tests.
- `supabase/tests/database/32_batch_person_id.test.sql`, `33_drain_cron.test.sql`.
- `supabase/check-no-config-push.sh` — the deployment guard.
- `test/repositories/push_repository_test.dart`, `test/features/push_cubit_test.dart`, `test/core/push_routes_test.dart`.

**Modified:**
- `pubspec.yaml`, `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `lib/main.dart`, `lib/app.dart`
- `lib/repositories/settings_repository.dart` / `_impl.dart` — `deleteThisDeviceToken` moves out.
- `lib/features/settings/settings_cubit.dart` — depends on `PushRepository` for deletion.
- `lib/core/app_strings.dart`, `lib/api/api_params.dart`
- `supabase/functions/drain_reminders/index.ts`

---

### Task 1: Firebase registration and `firebase_core`

**Files:**
- Modify: `pubspec.yaml`, `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `lib/main.dart`
- Create (generated): `android/app/google-services.json`, `lib/firebase_options.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `DefaultFirebaseOptions.currentPlatform`, used by `lib/main.dart` only.

This task adds no behavior. Its whole deliverable is that the app still builds and all 303 existing tests stay green with Firebase initialised — if that is not true, nothing later in this plan can be trusted.

- [ ] **Step 1: Record the pre-change baseline**

Run and write the numbers into the commit message later:
```bash
cd ~/Desktop/Projects/birthday_app
fvm flutter test --exclude-tags contract 2>&1 | tail -3
fvm flutter analyze 2>&1 | tail -3
```
Expected: 250 tests pass, analyze clean. If either is already failing, STOP and report — do not build on a red baseline.

- [ ] **Step 2: Add the dependencies**

```bash
fvm flutter pub add firebase_core firebase_messaging
```

- [ ] **Step 3: Register the Android app with Firebase**

```bash
fvm dart pub global run flutterfire_cli:flutterfire configure \
  --project=birthdaypartner-e7b7b \
  --platforms=android \
  --android-package-name=com.birthdayapp.birthday_app \
  --yes
```
Expected: writes `lib/firebase_options.dart` and `android/app/google-services.json`.

If `flutterfire` is not on PATH, it is at `~/.pub-cache/bin/flutterfire`.

- [ ] **Step 4: Verify the generated files are Android-only**

```bash
grep -c "ios\|IOS" lib/firebase_options.dart
grep "package_name" android/app/google-services.json
```
Expected: the package name is `com.birthdayapp.birthday_app`. `firebase_options.dart` will still contain an `ios` *branch* that throws `UnsupportedError` — that is correct and expected. What must NOT be present is a populated `FirebaseOptions` const for iOS. If one exists, an iOS app was registered; delete it in the Firebase console and re-run Step 3.

- [ ] **Step 5: Wire the google-services Gradle plugin**

In `android/settings.gradle.kts`, inside the existing `plugins { }` block, after the Kotlin line:
```kotlin
    id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, inside the existing `plugins { }` block, after `dev.flutter.flutter-gradle-plugin`:
```kotlin
    id("com.google.gms.google-services")
```
The google-services plugin must come after the Flutter plugin, not before.

- [ ] **Step 6: Initialise Firebase in `lib/main.dart`**

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await ApiClient.init();
  runApp(const BirthdayApp());
}
```

`lib/main_ops.dart` is NOT touched. The ops console is a web target with no push, and pulling Firebase into its bundle works against the size constraint in the M4 spec §3.

- [ ] **Step 7: Verify nothing regressed**

```bash
fvm flutter analyze
fvm flutter test --exclude-tags contract
fvm flutter build apk --debug
fvm flutter build web -t lib/main_ops.dart
```
Expected: analyze clean; 250 tests pass; the APK builds; the ops web bundle still builds. The APK build is the real assertion here — it is what proves the Gradle plugin is wired correctly, and no Dart test can prove it.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock android/ lib/main.dart lib/firebase_options.dart
git commit -m "feat(push): register the Android app with Firebase

google-services.json is committed deliberately. It holds a client API key
that ships inside the APK regardless, so it is not a secret, and
gitignoring it would break every other clone. See spec section 4.1.

No iOS app is registered: without an APNs key it would deliver nothing
while looking configured.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `PushRepository`, extracted from `SettingsRepository`

**Files:**
- Create: `lib/repositories/push_repository.dart`, `lib/repositories/push_repository_impl.dart`
- Create: `test/repositories/push_repository_test.dart`
- Modify: `lib/repositories/settings_repository.dart`, `lib/repositories/settings_repository_impl.dart`
- Modify: `lib/features/settings/settings_cubit.dart`, `lib/app.dart`, `lib/api/api_params.dart`
- Modify: `test/features/settings_cubit_test.dart` (existing fakes gain a `PushRepository`)

**Interfaces:**
- Consumes: Task 1's `firebase_core` initialisation.
- Produces:
```dart
abstract interface class PushRepository {
  Future<bool> requestPermission();
  Future<void> registerThisDevice();
  Future<void> deleteThisDeviceToken();
  Stream<String> get notificationRoutes;
  Future<String?> initialRoute();
}
```
Tasks 3 and 5 depend on exactly these names.

- [ ] **Step 1: Write the failing test for the repository contract**

`test/repositories/push_repository_test.dart`:
```dart
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake every later task reuses. Lives in the test tree, not lib/.
class FakePush implements PushRepository {
  FakePush({this.granted = true, this.onDelete});
  bool granted;

  /// Lets a test record WHEN deletion happened relative to other calls, not
  /// merely that it did. Task 2's sign-out test needs the order.
  final void Function()? onDelete;

  int permissionCalls = 0;
  int registerCalls = 0;
  int deleteCalls = 0;
  Object? registerError;
  final routes = StreamController<String>.broadcast();
  String? initial;

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return granted;
  }

  @override
  Future<void> registerThisDevice() async {
    registerCalls++;
    if (registerError != null) throw registerError!;
  }

  @override
  Future<void> deleteThisDeviceToken() async {
    deleteCalls++;
    onDelete?.call();
  }

  @override
  Stream<String> get notificationRoutes => routes.stream;

  @override
  Future<String?> initialRoute() async => initial;
}

void main() {
  test('the fake satisfies the interface', () {
    expect(FakePush(), isA<PushRepository>());
  });
}
```
Add `import 'dart:async';` at the top.

- [ ] **Step 2: Run it to verify it fails**

```bash
fvm flutter test test/repositories/push_repository_test.dart
```
Expected: FAIL — `push_repository.dart` does not exist.

- [ ] **Step 3: Write the interface**

`lib/repositories/push_repository.dart`:
```dart
/// The device-token lifecycle. Extracted from SettingsRepository, which
/// carried `deleteThisDeviceToken` together with a hardcoded
/// `String? get _currentDeviceToken => null` -- settings triggers one end of
/// this lifecycle but does not own it.
abstract interface class PushRepository {
  /// Asks the OS for notification permission. Android 13+ treats
  /// POST_NOTIFICATIONS as a runtime permission; below 13 this resolves true
  /// without a prompt. A false result is not an error: the app works, and
  /// reminders simply do not arrive.
  Future<bool> requestPermission();

  /// Reads the FCM token and calls `register_device_token(p_token,
  /// p_platform)`. Safe to call repeatedly: the function deletes any prior
  /// row holding that token before inserting, so a reinstall or a
  /// handed-down phone reassigns cleanly.
  Future<void> registerThisDevice();

  /// Deletes this device's row. MUST be called BEFORE the session is
  /// cleared: once it is gone, `device_tokens_all_own` scopes the row to an
  /// `auth.uid()` this client no longer has, and the delete silently
  /// affects nothing while the device keeps receiving the previous user's
  /// reminders.
  Future<void> deleteThisDeviceToken();

  /// Routes from notifications tapped while the app was running.
  Stream<String> get notificationRoutes;

  /// The route from a notification that launched the app from terminated,
  /// or null. Separate from [notificationRoutes] because the tap happened
  /// before anything could subscribe.
  Future<String?> initialRoute();
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
fvm flutter test test/repositories/push_repository_test.dart
```
Expected: PASS.

- [ ] **Step 5: Add the platform param constant**

In `lib/api/api_params.dart`, in the `// device_tokens` group:
```dart
  static const platform = 'platform';
  static const rpcRegisterDeviceToken = 'register_device_token';
  static const pToken = 'p_token';
  static const pPlatform = 'p_platform';
```

- [ ] **Step 6: Write the implementation**

`lib/repositories/push_repository_impl.dart`:
```dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/logger.dart';
import '../core/push_routes.dart';
import '../core/result.dart';
import 'push_repository.dart';

/// The ONLY file in lib/ that imports firebase_messaging. Everything else
/// depends on [PushRepository], so the rest of the app is testable without
/// a Firebase binding.
///
/// Deliberately not unit-tested: FirebaseMessaging is a concrete singleton
/// backed by a platform channel, and a test double for it would assert
/// against the double rather than the plugin. This class is covered by the
/// device run in Task 9, the same way ApiClient is. Everything with real
/// logic in it lives in [routeForPayload], which IS tested.
class PushRepositoryImpl implements PushRepository {
  PushRepositoryImpl(this._client, this._messaging) {
    // Re-register internally rather than exposing a refresh stream for
    // someone else to wire up. A token rotated by the OS leaves the user
    // unreachable while the stale row still satisfies
    // next_reminder_batch's `exists` check -- so reminders are claimed and
    // burned against a dead token, which is worse than not being
    // registered at all.
    _refreshSub = _messaging.onTokenRefresh.listen((_) {
      registerThisDevice().catchError((Object e, StackTrace s) {
        Log.error('re-register after token refresh failed', e, s);
      });
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = routeForPayload(message.data);
      if (route != null) _routes.add(route);
    });
  }

  final SupabaseClient _client;
  final FirebaseMessaging _messaging;
  final _routes = StreamController<String>.broadcast();
  late final StreamSubscription<String> _refreshSub;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> registerThisDevice() async {
    final token = await _messaging.getToken();
    if (token == null) {
      throw const PermissionFailure('This device has no push token.');
    }
    try {
      await _client.rpc(
        ApiParams.rpcRegisterDeviceToken,
        params: {
          ApiParams.pToken: token,
          ApiParams.pPlatform: Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> deleteThisDeviceToken() async {
    final token = await _messaging.getToken();
    if (token == null) return;
    try {
      await _client
          .from(ApiParams.deviceTokens)
          .delete()
          .eq(ApiParams.token, token);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Stream<String> get notificationRoutes => _routes.stream;

  @override
  Future<String?> initialRoute() async {
    final message = await _messaging.getInitialMessage();
    if (message == null) return null;
    return routeForPayload(message.data);
  }
}
```

`routeForPayload` is written test-first in Task 5. So that the tree analyzes between tasks, create `lib/core/push_routes.dart` now containing exactly:
```dart
/// Written test-first in Task 5. Returning null here means a tapped
/// notification does nothing, which is the correct behaviour to ship if
/// Task 5 were somehow never completed.
String? routeForPayload(Map<String, dynamic> data) => null;
```
Task 5's first test must be watched to FAIL against this stub before it is replaced — a stub that happens to satisfy a weak test is how a feature ships dead.

- [ ] **Step 7: Remove the stub from `SettingsRepository`**

Delete `deleteThisDeviceToken` from both `lib/repositories/settings_repository.dart` and `lib/repositories/settings_repository_impl.dart`, including the `_currentDeviceToken` getter and the now-unused `ApiParams.deviceTokens`/`ApiParams.token` imports if nothing else in the file uses them.

The interface doc comment on `SettingsRepository` mentions the device token; update it to say only what the class still does.

- [ ] **Step 8: Point `SettingsCubit` at `PushRepository`**

In `lib/features/settings/settings_cubit.dart`, change the constructor and the field:
```dart
  SettingsCubit(this._settings, this._auth, this._push)
      : super(const SettingsLoading());

  final SettingsRepository _settings;
  final AuthRepository _auth;
  final PushRepository _push;
```
and in `signOut()` change `await _settings.deleteThisDeviceToken();` to `await _push.deleteThisDeviceToken();`. The ordering comment above it stays exactly as it is — it is still the whole of what makes the method correct, and this phase is what finally makes it non-vacuous.

Add the import, and update `lib/features/settings/settings_screen.dart` where the cubit is constructed to read `context.read<PushRepository>()`.

- [ ] **Step 9: Register the repository in `lib/app.dart`**

```dart
  late final PushRepository _push =
      PushRepositoryImpl(ApiClient.instance, FirebaseMessaging.instance);
```
and add to the `providers:` list:
```dart
        RepositoryProvider<PushRepository>.value(value: _push),
```
No `?? ConcreteImpl(...)` fallback, matching every other repository here.

- [ ] **Step 10: Fix the existing settings tests and add the one that matters**

`test/features/settings_cubit_test.dart` constructs `SettingsCubit` — update every construction to pass a `FakePush`. Then add:
```dart
  test('sign-out deletes the device token BEFORE clearing the session',
      () async {
    final order = <String>[];
    final push = FakePush(onDelete: () => order.add('delete'));
    final auth = FakeAuth(onSignOut: () => order.add('signOut'));
    final cubit = SettingsCubit(FakeSettings(), auth, push);
    await cubit.load();

    await cubit.signOut();

    // Not just "both were called": the ORDER is the correctness property.
    // Reversed, the delete hits RLS with no auth.uid() and silently
    // affects nothing, leaving the device receiving the previous user's
    // reminders. Until this phase no client ever held a token, so this
    // assertion could not fail. It can now.
    expect(order, ['delete', 'signOut']);
    expect(push.deleteCalls, 1);
  });
```
`FakeAuth` in this file needs the same `onSignOut` hook if it does not already have one. The assertion is on the ORDER; two independent counters would pass with the calls reversed.

- [ ] **Step 11: Verify**

```bash
fvm flutter analyze
fvm flutter test --exclude-tags contract
```
Expected: clean; all tests pass including the new ordering test.

- [ ] **Step 12: Commit**

```bash
git add lib/repositories/ lib/features/settings/ lib/app.dart lib/api/api_params.dart test/
git commit -m "feat(push): extract PushRepository and make sign-out deletion real

SettingsRepositoryImpl carried a hardcoded
\`String? get _currentDeviceToken => null\`, which made
deleteThisDeviceToken a guaranteed no-op. SettingsCubit's sign-out
ordering comment -- delete before clearing the session, because RLS
scopes the row to auth.uid() -- was therefore untestable. It is now
asserted on call order, not on two independent counters.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Permission and registration lifecycle

**Files:**
- Create: `lib/features/settings/push_cubit.dart`, `lib/features/settings/push_state.dart`
- Create: `test/features/push_cubit_test.dart`
- Modify: `lib/features/timeline/timeline_screen.dart`, `lib/core/app_strings.dart`

**Interfaces:**
- Consumes: `PushRepository` from Task 2.
- Produces: `PushCubit(PushRepository)` with `Future<void> enable()`; states `PushIdle`, `PushEnabled`, `PushDenied`, `PushFailed(String message)`.

Permission is requested on arrival at `/timeline`, not at launch. Android 13+ makes `POST_NOTIFICATIONS` a runtime permission, and prompting on the first cold frame — before the user knows what the app is — is the reliable way to be denied permanently.

- [ ] **Step 1: Write the failing tests**

`test/features/push_cubit_test.dart`:
```dart
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/settings/push_cubit.dart';
import 'package:birthday_app/features/settings/push_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repositories/push_repository_test.dart' show FakePush;

void main() {
  test('1. granted permission registers the device', () async {
    final push = FakePush(granted: true);
    final cubit = PushCubit(push);

    await cubit.enable();

    expect(push.permissionCalls, 1);
    expect(push.registerCalls, 1);
    expect(cubit.state, isA<PushEnabled>());
  });

  test('2. a denial does NOT register, and is not an error state', () async {
    final push = FakePush(granted: false);
    final cubit = PushCubit(push);

    await cubit.enable();

    // Registering a token the OS will never deliver to would create a row
    // that satisfies next_reminder_batch's `exists` check, so reminders
    // would be claimed and burned against a device that cannot receive.
    expect(push.registerCalls, 0);
    expect(cubit.state, isA<PushDenied>());
  });

  test('3. a denial followed by a later grant DOES register', () async {
    // Review Focus 4: the user denies, then turns notifications on in
    // Android settings and comes back. Nothing re-runs registration
    // unless enable() is safe to call again and actually re-asks.
    final push = FakePush(granted: false);
    final cubit = PushCubit(push);
    await cubit.enable();
    expect(cubit.state, isA<PushDenied>());

    push.granted = true;
    await cubit.enable();

    expect(push.registerCalls, 1);
    expect(cubit.state, isA<PushEnabled>());
  });

  test('4. a registration failure surfaces without losing the grant',
      () async {
    final push = FakePush(granted: true)
      ..registerError = const OfflineFailure('no connection');
    final cubit = PushCubit(push);

    await cubit.enable();

    expect(cubit.state, isA<PushFailed>());
    expect((cubit.state as PushFailed).message, 'no connection');
  });

  test('5. a second enable() while the first is in flight is ignored',
      () async {
    final push = FakePush(granted: true);
    final cubit = PushCubit(push);

    // Both fired WITHOUT awaiting the first: the guard claims its key
    // synchronously, so awaiting would release it and prove nothing.
    final first = cubit.enable();
    final second = cubit.enable();
    await Future.wait([first, second]);

    expect(push.permissionCalls, 1);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
fvm flutter test test/features/push_cubit_test.dart
```
Expected: FAIL — `push_cubit.dart` does not exist.

- [ ] **Step 3: Write the state**

`lib/features/settings/push_state.dart`:
```dart
sealed class PushState {
  const PushState();
}

final class PushIdle extends PushState {
  const PushIdle();
}

final class PushEnabled extends PushState {
  const PushEnabled();
}

/// The OS refused, or the user did. Not an error: the app works and
/// reminders simply do not arrive.
final class PushDenied extends PushState {
  const PushDenied();
}

final class PushFailed extends PushState {
  const PushFailed(this.message);
  final String message;
}
```

- [ ] **Step 4: Write the cubit**

`lib/features/settings/push_cubit.dart`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../repositories/push_repository.dart';
import 'push_state.dart';

class PushCubit extends Cubit<PushState> {
  PushCubit(this._push) : super(const PushIdle());
  final PushRepository _push;

  bool _inFlight = false;

  /// Safe to call on every arrival at the timeline. Re-asking is what lets
  /// a user who denied, then enabled notifications in Android settings,
  /// actually start receiving reminders -- on Android 13+ a second
  /// requestPermission() after the OS-level grant resolves true without a
  /// prompt, so this costs nothing in the common case.
  Future<void> enable() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final granted = await _push.requestPermission();
      if (!granted) {
        emit(const PushDenied());
        return;
      }
      await _push.registerThisDevice();
      emit(const PushEnabled());
    } on AppFailure catch (f) {
      emit(PushFailed(f.message));
    } catch (_) {
      emit(const PushFailed(AppStrings.somethingWentWrong));
    } finally {
      _inFlight = false;
    }
  }
}
```

- [ ] **Step 5: Run to verify they pass**

```bash
fvm flutter test test/features/push_cubit_test.dart
```
Expected: 5 tests PASS.

- [ ] **Step 6: Call it from the timeline screen**

In `lib/features/timeline/timeline_screen.dart`, wrap the existing body in a `BlocProvider<PushCubit>` created with `PushCubit(context.read<PushRepository>())..enable()`. The screen renders nothing new — a denial is silent, per Step 1 test 2. Do not add a banner, a dialog, or a snackbar; that is scope this phase does not have.

- [ ] **Step 7: Verify**

```bash
fvm flutter analyze
fvm flutter test --exclude-tags contract
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/ test/features/push_cubit_test.dart
git commit -m "feat(push): request permission and register on arrival at the timeline

Permission is asked after onboarding, not at launch: Android 13+ makes
POST_NOTIFICATIONS a runtime permission and a prompt on the first cold
frame is the reliable way to be denied permanently.

enable() is safe to re-run, which is what lets a user who denied and
then enabled notifications in Android settings ever receive a reminder.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Carry `subject_person_id` through the batch

**Files:**
- Create: `supabase/migrations/20260927000001_batch_person_id.sql`
- Create: `supabase/tests/database/32_batch_person_id.test.sql`
- Modify: `supabase/functions/drain_reminders/index.ts` (the `Reminder` type only)

**Interfaces:**
- Consumes: nothing.
- Produces: `rpc_next_reminder_batch` returns a seventh column, `subject_person_id bigint`. Task 5's `Reminder` type and Task 6's message builder depend on it.

**The trap in this task:** Postgres cannot `create or replace` a function whose return table changed — it raises `cannot change return type of existing function`. Both functions must be dropped first. **A `drop` discards the function's ACL, and a freshly created function is executable by `public` by default.** Forgetting to re-apply the `revoke`/`grant` pair re-opens a `security definer` function that reads every user's device tokens to `anon`.

- [ ] **Step 1: Write the failing pgTAP test**

`supabase/tests/database/32_batch_person_id.test.sql`:
```sql
begin;
select plan(4);

-- 1. The new column exists. `proargnames` includes OUT parameters, which is
-- what a `returns table` column is. (has_column does not work on a function's
-- return table -- it is for real relations only.)
select ok(
  (select p.proargnames @> array['subject_person_id']
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'next_reminder_batch'),
  'the batch must carry the person id a tapped notification routes to');

-- 2-4. THE assertions this file exists for. `drop function` takes the ACL
-- with it and a recreated function is executable by public, so a migration
-- that drops must re-apply every revoke. These are the ones that matter.
select ok(
  not has_function_privilege('anon', 'public.rpc_next_reminder_batch(int)', 'execute'),
  'anon must NOT execute the wrapper after the drop-and-recreate');
select ok(
  not has_function_privilege('authenticated', 'public.rpc_next_reminder_batch(int)', 'execute'),
  'authenticated must NOT execute the wrapper after the drop-and-recreate');
select ok(
  has_function_privilege('service_role', 'public.rpc_next_reminder_batch(int)', 'execute'),
  'service_role must still execute it -- the drain runs as service_role');

select * from finish();
rollback;
```

- [ ] **Step 2: Run to verify it fails**

```bash
supabase db reset && supabase test db
```
Expected: `32_batch_person_id.test.sql` FAILS on assertion 1.

**Environment trap:** running `supabase test db` without a preceding `db reset` produces a FALSE failure. Always reset first. And `supabase db reset` orphans a running `functions serve` — Kong then 502s everything. If a Deno suite starts failing wholesale after a reset, restart BOTH `functions serve` and Kong, not just serve.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20260927000001_batch_person_id.sql`:
```sql
-- A tapped reminder routes to /person/:personId, and the batch did not carry
-- the id -- it returned the display_name but not the row it came from, even
-- though notification_outbox has subject_person_id.
--
-- `create or replace` CANNOT do this: changing a `returns table` shape raises
-- "cannot change return type of existing function". Both the private function
-- and its public wrapper must be dropped and recreated.
--
-- DROP TAKES THE ACL WITH IT. A freshly created function is executable by
-- `public`. Every revoke/grant below is therefore mandatory, not decorative:
-- omitting them exposes a security definer function that reads every user's
-- device tokens to anon. 32_batch_person_id.test.sql asserts exactly this.
drop function if exists public.rpc_next_reminder_batch(int);
drop function if exists private.next_reminder_batch(int);

create function private.next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  subject_person_id bigint,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  with claimed as (
    update private.notification_outbox o
    set claimed_at = now(), attempts = o.attempts + 1
    where o.id in (
      select c.id
      from private.notification_outbox c
      where c.sent_at is null
        and c.attempts < 5
        and (c.claimed_at is null or c.claimed_at < now() - interval '10 minutes')
        and exists (
          select 1 from public.device_tokens d
          where d.profile_id = c.recipient_profile_id
        )
      order by c.id
      limit p_limit
      for update skip locked
    )
    returning o.id, o.recipient_profile_id, o.subject_person_id,
              o.offset_days, o.occasion_date
  )
  select cl.id, d.token, d.platform, p.display_name, cl.subject_person_id,
         cl.offset_days, cl.occasion_date
  from claimed cl
  join public.people p on p.id = cl.subject_person_id
  -- At most five devices per reminder. A user may register unlimited tokens
  -- and this join is per-token, so without a bound one reminder becomes an
  -- unbounded number of FCM calls at the user's own discretion.
  cross join lateral (
    select d2.token, d2.platform
    from public.device_tokens d2
    where d2.profile_id = cl.recipient_profile_id
    order by d2.last_seen_at desc, d2.id desc
    limit 5
  ) d
  order by cl.id;
$$;

revoke execute on function private.next_reminder_batch(int)
  from public, anon, authenticated;

create function public.rpc_next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  subject_person_id bigint,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  select * from private.next_reminder_batch(p_limit);
$$;

revoke execute on function public.rpc_next_reminder_batch(int)
  from public, anon, authenticated;
grant execute on function public.rpc_next_reminder_batch(int) to service_role;
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase db reset && supabase test db
```
Expected: all 33 files pass, `32_` among them.

- [ ] **Step 5: Confirm the existing reminders suite still passes**

`17_reminders.test.sql` exercises `next_reminder_batch` heavily and selects from it. A changed column order breaks positional access. Read its failures carefully if any appear — a `select *` into a record type is position-sensitive.

- [ ] **Step 6: Widen the TypeScript type**

In `supabase/functions/drain_reminders/index.ts`, add to `type Reminder`:
```ts
  subject_person_id: number;
```

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260927000001_batch_person_id.sql \
        supabase/tests/database/32_batch_person_id.test.sql \
        supabase/functions/drain_reminders/index.ts
git commit -m "feat(reminders): carry subject_person_id through the batch

A tapped reminder routes to /person/:personId and the batch did not
return the id. Changing a \`returns table\` shape cannot be done with
create-or-replace, so both the function and its public wrapper are
dropped and recreated -- which discards their ACLs. The test asserts
anon and authenticated are still refused afterwards, because a fresh
function is executable by public and this one reads every user's
device tokens.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Sanitise the notification name, and route a tap

**Files:**
- Create: `supabase/functions/drain_reminders/fcm.ts`
- Create: `supabase/functions/drain_reminders/index.test.ts`
- Create: `lib/core/push_routes.dart`, `test/core/push_routes_test.dart`
- Modify: `supabase/functions/drain_reminders/index.ts`, `lib/app.dart`

**Interfaces:**
- Consumes: Task 4's `subject_person_id`.
- Produces: `safeName(raw: string): string` and `reminderBody(r: Reminder): string` from `fcm.ts`; `String? routeForPayload(Map<String, dynamic> data)` from `push_routes.dart`.

`20260824000005_device_tokens.sql` states the requirement this task satisfies:

> Phase 2 MUST NOT place an unsanitised `display_name` in a notification title or body; this is the path that makes it exploitable.

`drain_reminders` violates it today. It is inert only because the function is in dry-run — **Task 6 is what arms it**, so this task must land first.

- [ ] **Step 1: Write the failing Deno tests**

`supabase/functions/drain_reminders/index.test.ts`:
```ts
// Unit tests. No server required:
//   deno test supabase/functions/drain_reminders/index.test.ts
import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { safeName } from "./fcm.ts";

Deno.test("a plain name passes through untouched", () => {
  assertEquals(safeName("Priya Sharma"), "Priya Sharma");
});

Deno.test("newlines are stripped -- they let a name forge a second line", () => {
  const forged = safeName("Priya\nTap here to verify your account");
  assertEquals(forged.includes("\n"), false);
});

Deno.test("control characters are stripped", () => {
  assertEquals(safeName("Pri\u0000ya\u007F"), "Priya");
});

Deno.test("bidi overrides are stripped", () => {
  const raw = "Priya‮reversed";
  assertEquals(safeName(raw).includes("‮"), false);
});

Deno.test("a name of only control characters becomes Someone", () => {
  // Without this, the body reads "It's 's birthday today."
  assertEquals(safeName("\u0000\u0001\u0002"), "Someone");
});

Deno.test("an empty name becomes Someone", () => {
  assertEquals(safeName("   "), "Someone");
});

Deno.test("a long name is clamped to 64 code points", () => {
  const long = "a".repeat(200);
  assertEquals([...safeName(long)].length, 64);
});

Deno.test("clamping never splits an astral character", () => {
  // Review Focus 1. 70 emoji, each ONE code point but TWO UTF-16 units.
  // `.slice(0, 64)` on units would cut the 32nd emoji in half and emit a
  // lone surrogate, which renders as a replacement character.
  const emoji = "\u{1F382}".repeat(70);
  const out = safeName(emoji);
  assertEquals([...out].length, 64);
  assertEquals(out.includes("�"), false);
  // A lone high surrogate would survive a round-trip as a replacement char.
  assertEquals(
    new TextDecoder().decode(new TextEncoder().encode(out)).includes("�"),
    false,
  );
});

Deno.test("the clamp counts code points, not characters that merely look long", () => {
  const short = "\u{1F382}".repeat(10);
  assertEquals(safeName(short), short);
  assertNotEquals(safeName(short).length, 10); // UTF-16 length is 20
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Desktop/Projects/birthday_app
deno test supabase/functions/drain_reminders/index.test.ts
```
Expected: FAIL — `./fcm.ts` does not exist.

- [ ] **Step 3: Write `fcm.ts`**

```ts
// Everything in drain_reminders that has logic worth testing. index.ts stays
// transport and orchestration only.

/// C0 and C1 control characters. Newlines are the dangerous ones: they let a
/// display_name forge what looks like a second line of app-authored text.
const CONTROL = /[\u0000-\u001F\u007F-\u009F]/g;

/// Unicode bidirectional overrides and isolates. These let a name visually
/// reorder the sentence it is interpolated into without changing a byte of
/// the surrounding template.
const BIDI = /[‪-‮⁦-⁩]/g;

const MAX_NAME_POINTS = 64;

/// people.display_name is free text the user chooses, and
/// 20260824000005_device_tokens.sql documents the reachable attack: an
/// attacker who obtains a device token reassigns it to their own account,
/// creates a celebrated person whose display_name is arbitrary text with a
/// birthday of today, and the pipeline delivers that text to the victim's
/// device as a trusted notification.
///
/// This narrows the class; it does not close it. A short, plain, printable
/// name can still read as a sentence. Closing that needs a title/body split
/// that never interpolates into app-authored prose -- spec section 10.1.
export function safeName(raw: string): string {
  const stripped = raw.replace(CONTROL, "").replace(BIDI, "").trim();
  // Spread iterates CODE POINTS. `.slice(0, 64)` on the string would work on
  // UTF-16 units and cut an emoji or a Devanagari cluster in half, emitting a
  // lone surrogate.
  const points = [...stripped];
  const clamped = points.length > MAX_NAME_POINTS
    ? points.slice(0, MAX_NAME_POINTS).join("")
    : stripped;
  const final = clamped.trim();
  return final === "" ? "Someone" : final;
}

export function reminderBody(name: string, offsetDays: number): string {
  const safe = safeName(name);
  if (offsetDays === 0) return `It's ${safe}'s birthday today.`;
  if (offsetDays === 1) return `${safe}'s birthday is tomorrow.`;
  return `${safe}'s birthday is in ${offsetDays} days.`;
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
deno test supabase/functions/drain_reminders/index.test.ts
```
Expected: 9 tests PASS.

- [ ] **Step 5: Use it in `index.ts`**

Replace the local `body()` function with an import:
```ts
import { reminderBody, safeName } from "./fcm.ts";
```
and at the call site build the message with the person id in `data`:
```ts
          body: JSON.stringify({
            message: {
              token: r.token,
              notification: {
                title: "Birthday reminder",
                body: reminderBody(r.subject_name, r.offset_days),
              },
              data: { person_id: String(r.subject_person_id) },
            },
          }),
```
Delete the old `body()` definition. `safeName` is imported for the title path in Task 6; if the linter objects to an unused import now, add it in Task 6 instead.

- [ ] **Step 6: Write the failing Dart test for tap routing**

`test/core/push_routes_test.dart`:
```dart
import 'package:birthday_app/core/push_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a valid payload routes to the person page', () {
    expect(routeForPayload({'person_id': '42'}), '/person/42');
  });

  test('a missing person_id routes nowhere', () {
    expect(routeForPayload({}), isNull);
  });

  test('a non-numeric person_id routes nowhere', () {
    // The payload is attacker-influenced in exactly the same way the name
    // is. A path segment built from unchecked text is how a tap becomes a
    // navigation to somewhere the sender chose.
    expect(routeForPayload({'person_id': '../settings'}), isNull);
    expect(routeForPayload({'person_id': 'abc'}), isNull);
    expect(routeForPayload({'person_id': ''}), isNull);
  });

  test('a negative or zero id routes nowhere', () {
    expect(routeForPayload({'person_id': '-1'}), isNull);
    expect(routeForPayload({'person_id': '0'}), isNull);
  });
}
```

- [ ] **Step 7: Run to verify it fails, then write it**

```bash
fvm flutter test test/core/push_routes_test.dart
```
Expected: the FIRST test fails; the other three pass against Task 2's stub, because the stub returns null and they assert null. **That is the point** — only the first test has any power over the stub, so it is the one that must be watched to fail. The other three gain their power once the implementation can return a non-null value, and they are what stop it returning one for `'../settings'`.

`lib/core/push_routes.dart` — replace the stub entirely:
```dart
/// Turns an FCM data payload into a route, or null.
///
/// The payload is attacker-influenced in the same way display_name is: a
/// path segment built from unchecked text is how a tapped notification
/// becomes a navigation to somewhere the sender chose. Only a positive
/// integer is accepted, and the route is rebuilt from the parsed int rather
/// than from the original string, so nothing from the payload reaches the
/// router verbatim.
String? routeForPayload(Map<String, dynamic> data) {
  final raw = data['person_id'];
  if (raw is! String) return null;
  final id = int.tryParse(raw);
  if (id == null || id <= 0) return null;
  return '/person/$id';
}
```

- [ ] **Step 8: Verify, then wire it in `lib/app.dart`**

```bash
fvm flutter test test/core/push_routes_test.dart
```
Expected: PASS.

In `_BirthdayAppState.initState()`:
```dart
  @override
  void initState() {
    super.initState();
    // A tap that launched the app from terminated happened before anything
    // could subscribe, so it is fetched rather than listened for.
    _push.initialRoute().then((route) {
      if (route != null) _router.go(route);
    });
    _tapSub = _push.notificationRoutes.listen(_router.go);
  }
```
with a `late final StreamSubscription<String> _tapSub;` field and a `dispose()` that cancels it. This wiring is NOT unit tested — it is three lines over a stream, and the logic it carries lives in `routeForPayload`, which is. Task 9 exercises it on a device.

- [ ] **Step 9: Verify everything**

```bash
deno test supabase/functions/drain_reminders/index.test.ts
fvm flutter analyze && fvm flutter test --exclude-tags contract
```

- [ ] **Step 10: Commit**

```bash
git add supabase/functions/drain_reminders/ lib/core/push_routes.dart \
        lib/app.dart test/core/push_routes_test.dart
git commit -m "feat(push): sanitise the notification name and route a tap safely

20260824000005 required that Phase 2 not put an unsanitised display_name
in a notification body, and drain_reminders did exactly that. It is inert
only because the function is in dry-run, so this lands before the task
that supplies credentials.

Clamping counts code points, not UTF-16 units: 64 emoji sliced on units
emit a lone surrogate. The tap payload gets the same treatment -- the
route is rebuilt from a parsed positive int, so nothing from the payload
reaches the router verbatim.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Real FCM v1 credentials

**Files:**
- Modify: `supabase/functions/drain_reminders/fcm.ts`, `supabase/functions/drain_reminders/index.ts`, `supabase/functions/drain_reminders/index.test.ts`

**Interfaces:**
- Consumes: `safeName`/`reminderBody` from Task 5.
- Produces: `accessToken(sa, now, fetchImpl)` and `resetTokenCache()` from `fcm.ts`.

FCM HTTP v1 authenticates with a short-lived OAuth2 bearer minted from a service account, expiring hourly. The existing `FCM_ACCESS_TOKEN` env var is a placeholder its own comment disowns: as a deployment it delivers for about an hour and then fails silently into `attempts`. `FCM_PROJECT_ID` goes away — the project id is the `project_id` field of the service-account JSON, and two sources for one value is two things to drift apart.

- [ ] **Step 1: Write the failing tests**

Append to `supabase/functions/drain_reminders/index.test.ts`:
```ts
import { accessToken, resetTokenCache } from "./fcm.ts";

// A real RSA key is required: WebCrypto will not import a fake one. Generated
// once at module load, not committed, and never leaves this process.
async function testServiceAccount() {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const b64 = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    b64.match(/.{1,64}/g)!.join("\n")
  }\n-----END PRIVATE KEY-----\n`;
  return {
    project_id: "birthdaypartner-e7b7b",
    client_email: "drain@birthdaypartner-e7b7b.iam.gserviceaccount.com",
    private_key: pem,
  };
}

Deno.test("a minted token is returned and carries the right scope", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let seenBody = "";
  const fakeFetch = ((_url: string, init: RequestInit) => {
    seenBody = String(init.body);
    return Promise.resolve(
      new Response(JSON.stringify({ access_token: "tok-1", expires_in: 3600 })),
    );
  }) as unknown as typeof fetch;

  const tok = await accessToken(sa, Date.now(), fakeFetch);

  assertEquals(tok, "tok-1");
  assertEquals(
    decodeURIComponent(seenBody).includes(
      "https://www.googleapis.com/auth/firebase.messaging",
    ),
    true,
  );
});

Deno.test("a cached token is reused rather than re-minted", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(JSON.stringify({ access_token: "tok-1", expires_in: 3600 })),
    );
  }) as unknown as typeof fetch;

  const now = Date.now();
  await accessToken(sa, now, fakeFetch);
  await accessToken(sa, now + 60_000, fakeFetch);

  assertEquals(calls, 1);
});

Deno.test("a token inside the 5-minute margin is re-minted", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ access_token: `tok-${calls}`, expires_in: 3600 }),
      ),
    );
  }) as unknown as typeof fetch;

  const now = Date.now();
  await accessToken(sa, now, fakeFetch);
  // 3600s minus 4 minutes: inside the margin, so it must re-mint rather
  // than hand FCM a token that expires mid-batch.
  const tok = await accessToken(sa, now + (3600 - 240) * 1000, fakeFetch);

  assertEquals(calls, 2);
  assertEquals(tok, "tok-2");
});

Deno.test("a failed exchange throws rather than returning a bad token", async () => {
  // Review Focus 3. If this returned undefined, index.ts would send
  // `Bearer undefined` to FCM for every message in the batch and mark each
  // one failed -- burning `attempts` on reminders that were never attempted.
  resetTokenCache();
  const sa = await testServiceAccount();
  const fakeFetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 }),
    )) as unknown as typeof fetch;

  let threw = false;
  try {
    await accessToken(sa, Date.now(), fakeFetch);
  } catch (_) {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("a failed exchange is not cached", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return calls === 1
      ? Promise.resolve(new Response("{}", { status: 500 }))
      : Promise.resolve(
        new Response(JSON.stringify({ access_token: "ok", expires_in: 3600 })),
      );
  }) as unknown as typeof fetch;

  try {
    await accessToken(sa, Date.now(), fakeFetch);
  } catch (_) { /* expected */ }
  const tok = await accessToken(sa, Date.now(), fakeFetch);

  assertEquals(tok, "ok");
  assertEquals(calls, 2);
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
deno test supabase/functions/drain_reminders/index.test.ts
```
Expected: FAIL — `accessToken` is not exported.

- [ ] **Step 3: Implement minting in `fcm.ts`**

Append:
```ts
export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/// Re-mint when less than this remains. A token that expires mid-batch
/// fails every message after the boundary, and those failures consume
/// `attempts` on reminders that were perfectly deliverable.
const EXPIRY_MARGIN_MS = 5 * 60 * 1000;

let cached: { token: string; expiresAtMs: number } | null = null;

/// Test seam. Module-scope cache survives between Deno.test cases in one
/// process, so without this each test would see the previous one's token.
export function resetTokenCache(): void {
  cached = null;
}

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): Uint8Array {
  // JSON.parse has already turned the file's literal \n escapes into real
  // newlines, so the PEM arrives correctly formed.
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/// Mints (or reuses) an OAuth2 bearer for FCM HTTP v1.
///
/// `now` and `fetchImpl` are injected so the cache boundary and a failed
/// exchange are testable without waiting an hour or reaching Google.
export async function accessToken(
  sa: ServiceAccount,
  now: number,
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  if (cached && cached.expiresAtMs - now > EXPIRY_MARGIN_MS) {
    return cached.token;
  }

  const iat = Math.floor(now / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: SCOPE,
    aud: TOKEN_ENDPOINT,
    iat,
    exp: iat + 3600,
  };
  const enc = new TextEncoder();
  const signingInput = `${base64url(enc.encode(JSON.stringify(header)))}.${
    base64url(enc.encode(JSON.stringify(claims)))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(signingInput),
  );
  const assertion = `${signingInput}.${base64url(new Uint8Array(sig))}`;

  const res = await fetchImpl(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!res.ok) {
    // Throwing rather than returning a falsy token is deliberate: index.ts
    // must abandon the batch, not send `Bearer undefined` for every message
    // and burn `attempts` on reminders that were never attempted.
    throw new Error(`token exchange failed: ${res.status}`);
  }
  const json = await res.json() as { access_token: string; expires_in: number };
  // Assigned only on success, so a failure is never cached.
  cached = {
    token: json.access_token,
    expiresAtMs: now + json.expires_in * 1000,
  };
  return cached.token;
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
deno test supabase/functions/drain_reminders/index.test.ts
```
Expected: 14 tests PASS.

- [ ] **Step 5: Use it in `index.ts`**

Replace the credential block:
```ts
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");

  if (!saRaw) {
    // Dry run. The rows in this batch are already CLAIMED for their
    // 10-minute lease -- next_reminder_batch claims as it reads -- so an
    // immediate second call reports zero. Expected, not a bug.
    return new Response(
      JSON.stringify({ dryRun: true, would_send: batch.length, sent: 0, failed: 0 }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  const sa = JSON.parse(saRaw) as ServiceAccount;

  // Minted ONCE for the batch, outside the loop. A failure here is not a
  // per-message failure: no message was attempted, so nothing may be marked
  // failed. Returning 500 leaves the claim lease to expire in ten minutes
  // and the next drain picks the rows up untouched.
  let bearer: string;
  try {
    bearer = await accessToken(sa, Date.now());
  } catch (e) {
    console.error("fcm token mint failed", e);
    return new Response(JSON.stringify({ error: "auth failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
```
and inside the loop use `` `Bearer ${bearer}` `` and `` `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send` ``.

Add to the imports: `import { accessToken, reminderBody, type ServiceAccount } from "./fcm.ts";`

- [ ] **Step 6: Handle a permanently dead token**

Review Focus 2. FCM replies `404` with `UNREGISTERED` for a token the OS revoked. Nothing deletes the row today, so every future reminder for that user burns attempts against a corpse. Inside the `!res.ok` branch, before marking failed:
```ts
      if (res.status === 404) {
        // UNREGISTERED: the OS revoked this token. Deleting the row is the
        // only thing that stops every future reminder for this user being
        // claimed and burned against it. The user re-registers on next
        // launch, because registerThisDevice runs on every timeline arrival.
        const { error: delError } = await admin
          .from("device_tokens").delete().eq("token", r.token);
        if (delError) {
          console.error("stale token delete failed", delError.message);
        }
      }
```

The branch itself lives in `index.ts`'s loop, which needs a live server, so
the *decision* is extracted into `fcm.ts` where it can be tested directly.
Add to `fcm.ts`:
```ts
/// FCM's 404 means UNREGISTERED: the token is permanently dead, not
/// temporarily unreachable. Retrying it is what makes a revoked token burn
/// `attempts` on every future reminder for that user.
export function isDeadToken(status: number): boolean {
  return status === 404;
}
```
```ts
Deno.test("a 404 is a dead token; a 503 is not", () => {
  assertEquals(isDeadToken(404), true);
  assertEquals(isDeadToken(503), false);
  assertEquals(isDeadToken(401), false);
});
```
and call `isDeadToken(res.status)` in the loop.

- [ ] **Step 7: Verify the dry-run path still works**

```bash
deno test supabase/functions/drain_reminders/index.test.ts
grep -n "dryRun" supabase/functions/drain_reminders/index.ts
```
Expected: 15 tests pass; `dryRun: true` still returned when `FCM_SERVICE_ACCOUNT` is absent. Every prior phase's manual check depends on this.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/drain_reminders/
git commit -m "feat(push): mint real FCM v1 credentials in the drain

FCM_ACCESS_TOKEN was a placeholder the function's own comment disowned:
v1 bearers expire hourly, so a static env var delivers for an hour and
then fails silently into attempts. The service account JSON now lives in
one secret and the bearer is minted in-function with WebCrypto, cached
with a 5-minute margin so it never expires mid-batch.

FCM_PROJECT_ID is dropped -- the id is already in the service account.

Two failure modes got tests rather than assumptions: a failed token
exchange throws and abandons the batch instead of sending
'Bearer undefined' and burning attempts on every row, and a 404 from FCM
deletes the dead token instead of retrying it forever.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Trigger the drain

**Files:**
- Create: `supabase/migrations/20260927000002_drain_cron.sql`
- Create: `supabase/tests/database/33_drain_cron.test.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: `private.drain_config`, `private.trigger_drain()`, the `reminder-drain` cron job.

The 03:00 fan-out has been filling the outbox since Phase 1 and nothing has ever drained it.

- [ ] **Step 1: Write the failing pgTAP test**

`supabase/tests/database/33_drain_cron.test.sql`:
```sql
begin;
select plan(6);

select has_table('private', 'drain_config', 'the drain needs a config row');

-- private, not public: PostgREST cannot see the private schema, so a table
-- holding a bearer secret has no API surface to mis-police.
select ok(
  not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'drain_config'
  ),
  'drain_config must NOT be in public -- it holds a bearer secret');

select ok(
  (select count(*) = 1 from cron.job where jobname = 'reminder-drain'),
  'the drain cron must be scheduled exactly once');

select is(
  (select schedule from cron.job where jobname = 'reminder-drain'),
  '*/10 * * * *',
  'every ten minutes');

-- Review Focus 5. An unconfigured environment must be a no-op, not a cron
-- firing every ten minutes against a null URL and filling the log.
select lives_ok(
  $$ select private.trigger_drain() $$,
  'trigger_drain against an EMPTY drain_config must not raise');

select ok(
  (select count(*) = 0 from net.http_request_queue),
  'and it must not have queued a request');

select * from finish();
rollback;
```

Note: `net.http_request_queue` is pg_net's own table. If the extension names it differently on this version, find the right name with `\dt net.*` and use it — the assertion is that nothing was queued, not the table's name.

- [ ] **Step 2: Run to verify it fails**

```bash
supabase db reset && supabase test db
```
Expected: `33_drain_cron.test.sql` FAILS.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20260927000002_drain_cron.sql`:
```sql
-- The 03:00 fan-out has filled notification_outbox since Phase 1 and nothing
-- has ever drained it. drain_reminders has only ever been called by hand.
create extension if not exists pg_net;

-- Single row, enforced by the primary key: a boolean PK with a check that it
-- is true admits exactly one row and no more.
--
-- private, not public, for the same reason notification_outbox is: PostgREST
-- cannot see the private schema, so a table holding a bearer secret has no
-- API surface to mis-police. No policies; service_role and the cron's own
-- definer context are the only readers.
create table private.drain_config (
  id boolean primary key default true,
  function_url text not null,
  drain_secret text not null,
  constraint drain_config_single_row check (id)
);

alter table private.drain_config enable row level security;

-- Created EMPTY. Values are inserted per environment by an operator, so no
-- secret is ever committed and the same migration applies to local and
-- hosted without edits.
create or replace function private.trigger_drain()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_config private.drain_config%rowtype;
begin
  select * into v_config from private.drain_config limit 1;
  -- An unconfigured environment must be a NO-OP. Without this the cron
  -- fires every ten minutes against a null URL and fills the Postgres log
  -- with errors that look like a broken drain rather than an unconfigured
  -- one.
  if not found then
    return;
  end if;

  perform net.http_post(
    url := v_config.function_url,
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-drain-secret', v_config.drain_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

revoke execute on function private.trigger_drain() from public, anon, authenticated;

-- Ten minutes, not once a day. The fan-out is day-granular, but a lone daily
-- drain means one transient FCM failure delays a reminder by a full day, and
-- next_reminder_batch's ten-minute claim lease already assumes re-entry on
-- roughly this scale.
--
-- unschedule first so re-running a reset does not accumulate duplicate jobs.
-- A FROM-less select is one synthesized row filtered by WHERE, so when the
-- exists() is false the target list is never evaluated and unschedule is
-- never called. This is a skip, not a call-and-ignore-the-error.
select cron.unschedule('reminder-drain')
where exists (select 1 from cron.job where jobname = 'reminder-drain');

select cron.schedule(
  'reminder-drain',
  '*/10 * * * *',
  $$ select private.trigger_drain(); $$
);
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase db reset && supabase test db
```
Expected: all 34 files pass.

- [ ] **Step 5: Document how an operator configures it**

Append to the migration as a trailing comment — it is the only place someone reading this will look:
```sql
-- To configure an environment (NOT committed, run by hand):
--   insert into private.drain_config (function_url, drain_secret)
--   values ('https://<ref>.supabase.co/functions/v1/drain_reminders',
--           '<the same value as the DRAIN_SECRET function secret>')
--   on conflict (id) do update
--     set function_url = excluded.function_url,
--         drain_secret = excluded.drain_secret;
--
-- KNOWN GAP: net.http_post queues asynchronously and returns a request id
-- without ever raising, so a wrong URL or a dead function produces a cron
-- that reports success forever while nothing is delivered. Check delivery in
-- net._http_response, not in cron.job_run_details.
```

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260927000002_drain_cron.sql \
        supabase/tests/database/33_drain_cron.test.sql
git commit -m "feat(reminders): trigger the drain every ten minutes

The fan-out has filled the outbox since Phase 1 and nothing ever drained
it. The target URL and secret live in a private single-row table rather
than in the migration, so no secret is committed and the same migration
applies to local and hosted.

An empty config is a no-op, not an error: an unconfigured environment
must not fire every ten minutes against a null URL.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The deployment guard and runbook

**Files:**
- Create: `supabase/check-no-config-push.sh`
- Create: `docs/superpowers/execution/2026-09-27-m1-phase2c-deploy-runbook.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a check that joins the verification command list.

`config.toml` holds twelve real-format phone numbers whose OTP is a hardcoded `123456`. `supabase config push` would put them on an internet-facing auth endpoint.

- [ ] **Step 1: Write the check**

`supabase/check-no-config-push.sh`:
```bash
#!/usr/bin/env bash
# Fails if any tracked file invokes `supabase config push` while
# config.toml still carries the test-OTP block.
#
# config.toml holds twelve real-format phone numbers whose OTP is a
# hardcoded "123456". `db push` does not touch config.toml; `config push`
# DOES, and would place those numbers on an internet-facing GoTrue. This
# project has already reproduced two account-takeover bugs on this surface.
#
# This guards the REPO's contents. It cannot guard an operator's shell.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! grep -q '^\[auth.sms.test_otp\]' supabase/config.toml; then
  echo "note: no [auth.sms.test_otp] block; this check is moot."
  exit 0
fi

# --  excludes this file itself and the runbook, which both name the command
# in order to forbid it.
if git grep -n -- 'config push' -- \
    ':!supabase/check-no-config-push.sh' \
    ':!docs/**' >/dev/null 2>&1; then
  echo "FAIL: a tracked file invokes 'supabase config push' while"
  echo "[auth.sms.test_otp] is present in supabase/config.toml."
  git grep -n -- 'config push' -- \
    ':!supabase/check-no-config-push.sh' ':!docs/**'
  exit 1
fi

echo "PASS: nothing in the repo runs 'supabase config push'."
```

```bash
chmod +x supabase/check-no-config-push.sh
```

- [ ] **Step 2: Verify it passes now, and that it can fail**

A guard never watched to fail is not a guard, so prove both directions:

```bash
./supabase/check-no-config-push.sh   # must print PASS

printf 'supabase config push\n' > supabase/_bait.sh
git add supabase/_bait.sh
./supabase/check-no-config-push.sh   # must print FAIL and exit 1
echo "exit=$?"
git rm -f --cached supabase/_bait.sh && rm supabase/_bait.sh
./supabase/check-no-config-push.sh   # must print PASS again
```

- [ ] **Step 3: Write the runbook**

`docs/superpowers/execution/2026-09-27-m1-phase2c-deploy-runbook.md`, covering, in order: creating the hosted project; `supabase link --project-ref <ref>`; `supabase db push`; `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat ~/path/to/key.json)" DRAIN_SECRET=<value>`; `supabase functions deploy drain_reminders`; the `insert into private.drain_config` from Task 7 Step 5; and a prominent **DO NOT RUN `supabase config push`** with the reason.

State in it that hosted auth is configured by hand in the dashboard and that no test phone numbers are added there.

- [ ] **Step 4: Commit**

```bash
git add supabase/check-no-config-push.sh docs/superpowers/execution/
git commit -m "chore(deploy): guard against shipping the test-OTP block to hosted

config.toml carries twelve real-format numbers whose OTP is a hardcoded
123456. 'supabase db push' does not touch that file; 'supabase config
push' does. The check fails if any tracked file invokes it while the
block exists, and was watched to fail before being trusted.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Verification (performed by the human partner)

**Files:** none — this task produces a written record, not code.

Split per spec §3.1, because no single environment runs the whole loop: hosted has no SMS provider so no device can sign in there, and local is the only place a real phone can authenticate.

- [ ] **Step 1: Full suite on the branch**

```bash
supabase db reset && supabase test db
deno test supabase/functions/drain_reminders/index.test.ts
fvm flutter analyze
fvm flutter test --exclude-tags contract
fvm flutter build apk --debug
fvm flutter build web -t lib/main_ops.dart
./supabase/check-no-config-push.sh
grep -n 'enable_confirmations' supabase/config.toml   # must still be true
```

Then the contract suite with the stack running. **If it reports a mass failure, restart `functions serve` AND Kong before believing it** — a `db reset` orphans a running serve and Kong 502s everything, which has produced a false mass failure in two consecutive phases. A cold run has also timed out where an immediate rerun passed; timeouts are not assertions.

- [ ] **Step 2: Registration half, local, on a real Android phone**

Start the local stack, note the Mac's LAN IP, build with `--dart-define` pointing `SUPABASE_URL` at `http://<lan-ip>:54321`, install on a phone on the same wifi, sign in with one of the `[auth.sms.test_otp]` numbers, complete onboarding, and accept the notification prompt.

Confirm:
```sql
select profile_id, platform, created_at from public.device_tokens;
```
Expected: exactly one row, `platform = 'android'`.

Then sign out in Settings and confirm the row is gone. That is the assertion Task 2 made testable and only a device can prove.

- [ ] **Step 3: Transport half, hosted**

Follow the Task 8 runbook. Then seed a token — the one from Step 2 works — with the service role, seed an outbox row, and wait for the cron or invoke the function directly with the `x-drain-secret` header.

Expected: a notification on the phone reading `It's <name>'s birthday today.`, and tapping it opens that person's page.

Check `net._http_response` for the actual status, not `cron.job_run_details` — pg_net never raises, so the cron reports success either way.

- [ ] **Step 4: Record the gap**

Write the ledger at `docs/superpowers/execution/2026-09-27-m1-phase2c-ledger.md`. It must state plainly that **no run exercised a token written by the app being drained by the hosted function** — the two halves were proven in different environments and the seam between them is covered by nothing. Do not describe this phase as end-to-end verified.

---

## Notes for the executor

- `fvm flutter`, never bare `flutter`. The project is pinned to 3.35.2.
- Keep the Mac awake for long runs: `caffeinate -dims &`.
- `supabase test db` without a preceding `db reset` gives a FALSE failure.
- `supabase db reset` orphans `functions serve`; restart serve **and** Kong.
- `find.byType` defaults to `skipOffstage: true`, and Navigator marks covered routes offstage.
- `find.text` on a `DropdownButton` is vacuous — items stay mounted in an `IndexedStack`. Assert `.value`.
- `23514` is Postgres's GENERIC check-violation code, raised in seven places plus every table CHECK. Never branch on it alone; key off the message. `23505` IS distinguishable.
- A green suite is not evidence. Watch each new assertion fail with its implementation reverted, then restore byte-identically.
