import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/phone_cubit.dart';
import 'package:birthday_app/features/onboarding/phone_state.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  Object? sendError;
  Object? verifyError;
  int sendCalls = 0;
  int verifyCalls = 0;
  String? lastPhone;

  @override
  Future<void> sendOtp(String phoneE164) async {
    sendCalls++;
    lastPhone = phoneE164;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async {
    verifyCalls++;
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<int> claimProfile() async => 1;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeAuth auth;
  setUp(() => auth = _FakeAuth());

  blocTest<PhoneCubit, PhoneState>(
    'a valid Indian number is normalised to E.164 before sending',
    build: () => PhoneCubit(auth),
    act: (c) => c.submitPhone('99990 00001'),
    expect: () => [isA<PhoneSending>(), isA<PhoneCodeSent>()],
    verify: (_) => expect(auth.lastPhone, '+919999000001'),
  );

  // Nothing reaches the network for a number that cannot be a number. The
  // whole graph is keyed on the hash of this string, so a malformed one is
  // three rows for one person later.
  blocTest<PhoneCubit, PhoneState>(
    'an unparseable number fails locally without calling the repository',
    build: () => PhoneCubit(auth),
    act: (c) => c.submitPhone('abc'),
    expect: () => [isA<PhoneError>()],
    verify: (_) => expect(auth.sendCalls, 0),
  );

  blocTest<PhoneCubit, PhoneState>(
    'a send failure is an error state, not a crash',
    build: () => PhoneCubit(auth..sendError = const ServerFailure('down')),
    act: (c) => c.submitPhone('9999000001'),
    expect: () => [isA<PhoneSending>(), isA<PhoneError>()],
  );

  blocTest<PhoneCubit, PhoneState>(
    'a correct code verifies',
    build: () => PhoneCubit(auth),
    act: (c) async {
      await c.submitPhone('9999000001');
      await c.submitCode('123456');
    },
    expect: () => [
      isA<PhoneSending>(),
      isA<PhoneCodeSent>(),
      isA<PhoneVerifying>(),
      isA<PhoneVerified>(),
    ],
  );

  // The user must land back on the code screen able to try again, not on a
  // dead error screen with the phone number lost. The number must be the
  // right one, not merely non-null -- a blanked or swapped number would
  // still satisfy an isNotNull check on the error alone.
  blocTest<PhoneCubit, PhoneState>(
    'a wrong code returns to PhoneCodeSent carrying the error',
    build: () => PhoneCubit(auth..verifyError = const AuthFailure('bad')),
    act: (c) async {
      await c.submitPhone('9999000001');
      await c.submitCode('000000');
    },
    expect: () => [
      isA<PhoneSending>(),
      isA<PhoneCodeSent>(),
      isA<PhoneVerifying>(),
      isA<PhoneCodeSent>()
          .having((s) => s.error, 'error', isNotNull)
          .having((s) => s.phoneE164, 'phoneE164', '+919999000001'),
    ],
  );

  // A concurrent second attempt -- an edit during the async gap, or a
  // delayed SMS autofill overwrite -- must not fire a second verifyOtp
  // while one is already in flight. The Cubit is the one place that knows
  // what is in flight, so the guard belongs here, not in the widget.
  blocTest<PhoneCubit, PhoneState>(
    'a second submitCode call while verifying is ignored',
    build: () => PhoneCubit(auth),
    act: (c) async {
      await c.submitPhone('9999000001');
      final first = c.submitCode('123456');
      final second = c.submitCode('123456');
      await Future.wait([first, second]);
    },
    verify: (_) => expect(auth.verifyCalls, 1),
  );

  blocTest<PhoneCubit, PhoneState>(
    'resend re-sends the same number',
    build: () => PhoneCubit(auth),
    act: (c) async {
      await c.submitPhone('9999000001');
      await c.resend();
    },
    verify: (_) {
      expect(auth.sendCalls, 2);
      expect(auth.lastPhone, '+919999000001');
    },
  );
}
