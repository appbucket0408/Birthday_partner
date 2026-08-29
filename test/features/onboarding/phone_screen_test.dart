import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/otp_screen.dart';
import 'package:birthday_app/features/onboarding/phone_screen.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real [AuthRepository], not a mock: this test exercises the real
/// [PhoneScreen] -> [OtpScreen] handoff through a real [PhoneCubit], so the
/// bug (or its fix) in that navigation code is what the test is exposed to.
class _FakeAuth implements AuthRepository {
  Object? verifyError;

  @override
  Future<void> sendOtp(String phoneE164) async {}

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<int> claimProfile() async => 1;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  // A wrong code re-emits PhoneCodeSent (PhoneVerifying -> PhoneCodeSent with
  // an error). PhoneScreen's route stays mounted underneath the pushed
  // OtpScreen, so its listener sees that same transition. Without a guard on
  // route currency, it pushes a second OtpScreen on top of the first: a
  // fresh 30s cooldown and a doubled back stack, worse with every further
  // wrong attempt.
  testWidgets('a wrong code does not push a second OtpScreen', (tester) async {
    final auth = _FakeAuth()..verifyError = const AuthFailure('bad');
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<AuthRepository>.value(
          value: auth,
          child: const PhoneScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('phone_field')), '9999000001');
    await tester.tap(find.byKey(const Key('send_code_button')));
    await tester.pumpAndSettle();

    // skipOffstage: false matters here. A route fully covered by an
    // opaque route on top is marked offstage by Navigator (a paint/hit-test
    // optimisation), and the default finder hides offstage widgets -- so a
    // duplicate OtpScreen buried under the newest push would otherwise be
    // invisible to this assertion even though it is still in the tree.
    expect(find.byType(OtpScreen, skipOffstage: false), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp_field')), '000000');
    await tester.pumpAndSettle();

    expect(find.byType(OtpScreen, skipOffstage: false), findsOneWidget);
  });
}
