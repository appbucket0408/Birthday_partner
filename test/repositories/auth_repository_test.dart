@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository repo;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    repo = AuthRepositoryImpl(ApiClient.instance);
  });

  // The three numbers in [auth.sms.test_otp], all with OTP 123456.
  const phoneA = '+919999000001';
  const phoneB = '+919999000002';

  final otpThrottle = OtpSendThrottle();
  Future<void> sendOtpRateLimited(String phoneE164) =>
      otpThrottle.run(() => repo.sendOtp(phoneE164));

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
  //
  // This must not depend on run order: earlier tests happen to leave phoneA
  // deleted via their own tearDown, which is what makes the sign-in below
  // mint a genuinely new auth user (and therefore a genuinely fresh trigger
  // row) -- but that is an accident of suite order, not something this test
  // may assume. Running this test alone (`--plain-name`) would otherwise see
  // whatever state phoneA was left in by a previous run. So the precondition
  // is established explicitly: sign in, delete whatever is there (a no-op
  // the first time this number is ever used), then sign in again to get a
  // brand-new placeholder profile regardless of what came before.
  test('a fresh profile exists, has a placeholder handle, and is incomplete',
      () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.deleteAccount();

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

    // NOTE: this does NOT clean up the first user. By this point the active
    // session is the second user's (we signed out of phoneA and into phoneB
    // above), so this deletes the second user -- which tearDown would have
    // done anyway -- and never reaches the first. The first account (still
    // holding 'taken_handle') is left behind: a client has no way to delete
    // an account it isn't signed into, by design (delete_account identifies
    // its caller from the session, never from a request body). Harmless to
    // correctness -- phone OTP re-verification returns the SAME persistent
    // user, so rerunning this test is idempotent -- but it does mean this
    // test leaves one row in public.profiles per fresh `supabase db reset`.
    await repo.deleteAccount();
    expect(firstUserId, isNotNull);
  });

  test('signOut clears the session', () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.signOut();
    expect(repo.currentUserId, isNull);
  });

  // Covers the happy path of deleteAccount's two-step body (Edge Function
  // call, then signOut): the local session must be gone afterward. It does
  // NOT cover the partial-failure branch this method now handles (delete
  // succeeds, signOut's network half throws) -- forcing that specific
  // ordering against the real stack would need either mocking SupabaseClient
  // or interrupting the network mid-call, and a contract suite that mocks
  // the thing it exists to avoid mocking proves nothing. That branch is
  // covered by code review and the gotrue_client source cited in
  // auth_repository_impl.dart instead.
  test('deleteAccount clears the local session', () async {
    await sendOtpRateLimited(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.deleteAccount();
    expect(repo.currentUserId, isNull);
  });
}
