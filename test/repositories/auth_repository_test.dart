@Tags(['contract'])
library;

import 'dart:io';

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // AutomatedTestWidgetsFlutterBinding installs an HttpOverrides that makes
    // every dart:io HttpClient (including the one under supabase_flutter's
    // gotrue/postgrest/functions clients) return a fake empty 400 with no
    // request ever leaving the process. These are contract tests against a
    // *real* local stack on purpose, so that override has to come back off.
    HttpOverrides.global = null;
    // `flutter test` also runs with no platform channels registered, so
    // supabase_flutter's default SharedPreferences-backed session storage
    // throws MissingPluginException. An in-memory implementation sidesteps
    // that without touching what the test verifies against real Supabase.
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    await ApiClient.init();
    repo = AuthRepositoryImpl(ApiClient.instance);
  });

  // The three numbers in [auth.sms.test_otp], all with OTP 123456.
  const phoneA = '+919999000001';
  const phoneB = '+919999000002';

  // [auth.sms] max_frequency = "5s" rate-limits repeat sends to the SAME
  // number. Deleting an account resets its number's cooldown, but a test
  // that never completes verification (the wrong-code test) leaves phoneA's
  // cooldown running into the next test. Sending back-to-back through the
  // suite would otherwise be flaky rather than a real failure, so every
  // send waits out any cooldown left by the previous one instead.
  DateTime? lastOtpSentAt;
  Future<void> sendOtpRateLimited(String phoneE164) async {
    final last = lastOtpSentAt;
    if (last != null) {
      const cooldown = Duration(seconds: 6);
      final elapsed = DateTime.now().difference(last);
      if (elapsed < cooldown) {
        await Future<void>.delayed(cooldown - elapsed);
      }
    }
    await repo.sendOtp(phoneE164);
    lastOtpSentAt = DateTime.now();
  }

  tearDown(() async {
    if (ApiClient.instance.auth.currentSession != null) {
      await repo.deleteAccount().catchError((_) {});
    }
  });

  test('a full OTP round trip produces a session', () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    expect(repo.currentUserId, isNotNull);
  });

  test('a wrong code is an AuthFailure, not a crash', () async {
    await sendOtpRateLimited(phoneA);
    await expectLater(
      repo.verifyOtp(phoneE164: phoneA, token: '000000'),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('claimProfile returns a person id and is idempotent', () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');

    final first = await repo.claimProfile();
    final second = await repo.claimProfile();
    expect(first, isPositive);
    expect(second, first, reason: 'a retried onboarding must not fork identity');
  });

  // The trigger creates the row; the app never inserts one. A fresh profile is
  // therefore readable immediately and is NOT complete.
  test('a fresh profile exists, has a placeholder handle, and is incomplete',
      () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');

    final profile = await repo.loadProfile();
    expect(profile.handle, startsWith('u'));
    expect(profile.displayName, 'New user');
    expect(profile.birthday, isNull);
    expect(profile.hasCompletedOnboarding, isFalse);
  });

  test('completeProfile writes every field and flips the onboarding flag',
      () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');

    await repo.completeProfile(
      handle: 'contract_test_user',
      displayName: 'Contract Test',
      city: 'Jaipur',
      birthday: const Birthday(month: 4, day: 15, year: 1991),
    );

    final profile = await repo.loadProfile();
    expect(profile.handle, 'contract_test_user');
    expect(profile.displayName, 'Contract Test');
    expect(profile.city, 'Jaipur');
    expect(profile.birthday, const Birthday(month: 4, day: 15, year: 1991));
    expect(profile.hasCompletedOnboarding, isTrue);
  });

  // The schema enforces a unique handle. Onboarding is renaming, not naming,
  // so this branch is reachable on the very first screen a user sees.
  test('a taken handle surfaces as ServerFailure with code 23505', () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.completeProfile(
      handle: 'taken_handle',
      displayName: 'First',
      city: 'Jaipur',
      birthday: const Birthday(month: 1, day: 1),
    );
    final firstUserId = repo.currentUserId;

    await repo.signOut();
    await sendOtpRateLimited(phoneB);
    await repo.verifyOtp(phoneE164: phoneB, token: '123456');

    await expectLater(
      repo.completeProfile(
        handle: 'taken_handle',
        displayName: 'Second',
        city: 'Jaipur',
        birthday: const Birthday(month: 2, day: 2),
      ),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '23505')),
    );

    // Clean up the first user too; tearDown only reaches the current session.
    await repo.deleteAccount();
    expect(firstUserId, isNotNull);
  });

  test('signOut clears the session', () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.signOut();
    expect(repo.currentUserId, isNull);
  });
}
