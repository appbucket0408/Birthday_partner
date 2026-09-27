@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/settings_repository.dart';
import 'package:birthday_app/repositories/settings_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/settings_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late SettingsRepository settings;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    settings = SettingsRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number, per the task-11 phone pool assignment
  // ([auth.sms.test_otp] in supabase/config.toml).
  const phone = '+919999000005';

  final otpThrottle = OtpSendThrottle();

  setUp(() async {
    await otpThrottle.run(() => auth.sendOtp(phone));
    await auth.verifyOtp(phoneE164: phone, token: '123456');
    await auth.claimProfile();
  });

  tearDown(() => auth.deleteAccount().catchError((_) {}));

  test(
    'setRemindersEnabled(false) persists and loadProfile reflects it',
    () async {
      await settings.setRemindersEnabled(false);

      final profile = await auth.loadProfile();
      expect(profile.remindersEnabled, isFalse);
    },
  );

  test('setRemindersEnabled(true) restores it', () async {
    await settings.setRemindersEnabled(false);

    await settings.setRemindersEnabled(true);

    final profile = await auth.loadProfile();
    expect(profile.remindersEnabled, isTrue);
  });
}
