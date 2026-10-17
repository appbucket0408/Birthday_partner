@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Email sign-in, and the phone link an email sign-up needs before it can
/// claim a person. Requires the local stack (`supabase start`) with
/// `[auth.email] enable_signup = true` and the email_otp.html templates.
///
/// The email code is read back from Mailpit, the local inbox `supabase start`
/// runs on port 54324 -- the only place a local email code goes.
///
/// Run with:
///   fvm flutter test test/repositories/auth_email_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository repo;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    repo = AuthRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number in [auth.sms.test_otp]. The "taken number" case
  // below makes it taken itself (a first email account links it), so this
  // suite never touches a number another suite signs in with.
  const linkPhone = '+919999000015';

  final otpThrottle = OtpSendThrottle();

  tearDown(() async {
    if (ApiClient.instance.auth.currentSession != null) {
      await repo.deleteAccount().catchError((_) {});
    }
  });

  String freshEmail() =>
      'authemail${DateTime.now().microsecondsSinceEpoch}@example.com';

  Future<void> signInByEmail(String email) async {
    await repo.sendEmailOtp(email);
    await repo.verifyEmailOtp(email: email, token: await mailedCode(email));
  }

  test('an email code round trip signs in, with no verified phone', () async {
    await signInByEmail(freshEmail());

    expect(repo.currentUserId, isNotNull);
    expect(repo.hasVerifiedPhone, isFalse);
  });

  test('a wrong email code is an AuthFailure, not a crash', () async {
    final email = freshEmail();
    await repo.sendEmailOtp(email);
    await expectLater(
      repo.verifyEmailOtp(email: email, token: '000000'),
      throwsA(isA<AuthFailure>()),
    );

    // Sending the code created the account. Sign in with the real code so
    // tearDown has a session to delete it with.
    await repo.verifyEmailOtp(email: email, token: await mailedCode(email));
  });

  test('claimProfile is refused until a phone is linked, then succeeds',
      () async {
    await signInByEmail(freshEmail());

    await expectLater(repo.claimProfile(), throwsA(isA<ServerFailure>()));

    await otpThrottle.run(() => repo.sendPhoneLink(linkPhone));
    // Pending until the code is confirmed.
    expect(repo.hasVerifiedPhone, isFalse);
    await repo.verifyPhoneLink(phoneE164: linkPhone, token: '123456');
    expect(repo.hasVerifiedPhone, isTrue);

    expect(await repo.claimProfile(), isA<int>());
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('linking a number another account owns is refused with a clear '
      'message', () async {
    // First account: email, then links the number.
    await signInByEmail(freshEmail());
    await otpThrottle.run(() => repo.sendPhoneLink(linkPhone));
    await repo.verifyPhoneLink(phoneE164: linkPhone, token: '123456');
    await repo.signOut(); // keep it: it is what makes the number taken

    // Second account tries the same number.
    await signInByEmail(freshEmail());
    await expectLater(
      otpThrottle.run(() => repo.sendPhoneLink(linkPhone)),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.message,
          'message',
          AppStrings.phoneAlreadyRegistered,
        ),
      ),
    );
    await repo.deleteAccount();

    // Remove the first account too, so the number is free for the next run.
    // It now has that phone, so it signs straight back in by phone.
    await otpThrottle.run(() => repo.sendOtp(linkPhone));
    await repo.verifyOtp(phoneE164: linkPhone, token: '123456');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
