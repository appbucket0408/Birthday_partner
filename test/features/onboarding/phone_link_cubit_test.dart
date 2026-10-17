import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/phone_link_cubit.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  Object? sendError;
  Object? verifyError;
  Object? claimError;
  String? lastPhone;
  int sendCalls = 0;
  int verifyCalls = 0;
  int claimCalls = 0;

  @override
  Future<void> sendPhoneLink(String phoneE164) async {
    sendCalls++;
    lastPhone = phoneE164;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> verifyPhoneLink({
    required String phoneE164,
    required String token,
  }) async {
    verifyCalls++;
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<int> claimProfile() async {
    claimCalls++;
    final e = claimError;
    if (e != null) {
      claimError = null; // fails once, then succeeds
      throw e;
    }
    return 1;
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeAuth auth;
  setUp(() => auth = _FakeAuth());

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'a valid number is normalised to E.164 and texted a code',
    build: () => PhoneLinkCubit(auth),
    act: (c) => c.send('98765 43210'),
    expect: () => [
      isA<PhoneLinkSending>(),
      isA<PhoneLinkCodeSent>()
          .having((s) => s.phoneE164, 'phoneE164', '+919876543210'),
    ],
    verify: (_) => expect(auth.lastPhone, '+919876543210'),
  );

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'an invalid number fails locally without calling the repository',
    build: () => PhoneLinkCubit(auth),
    act: (c) => c.send('abc'),
    expect: () => [
      isA<PhoneLinkIdle>()
          .having((s) => s.error, 'error', AppStrings.phoneInvalid),
    ],
    verify: (_) => expect(auth.sendCalls, 0),
  );

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'a number already on another account goes back to the number field '
    'with that message',
    build: () => PhoneLinkCubit(
      auth..sendError = const AuthFailure(AppStrings.phoneAlreadyRegistered),
    ),
    act: (c) => c.send('9876543210'),
    expect: () => [
      isA<PhoneLinkSending>(),
      isA<PhoneLinkIdle>()
          .having((s) => s.error, 'error', AppStrings.phoneAlreadyRegistered),
    ],
  );

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'a correct code verifies, then claims',
    build: () => PhoneLinkCubit(auth),
    act: (c) async {
      await c.send('9876543210');
      await c.verify('123456');
    },
    skip: 2,
    expect: () => [isA<PhoneLinkVerifying>(), isA<PhoneLinkDone>()],
    verify: (_) {
      expect(auth.verifyCalls, 1);
      expect(auth.claimCalls, 1);
    },
  );

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'a wrong code stays on the code step with the error and does not claim',
    build: () => PhoneLinkCubit(auth..verifyError = const AuthFailure('bad')),
    act: (c) async {
      await c.send('9876543210');
      await c.verify('000000');
    },
    skip: 2,
    expect: () => [
      isA<PhoneLinkVerifying>(),
      isA<PhoneLinkCodeSent>().having((s) => s.error, 'error', 'bad'),
    ],
    verify: (_) => expect(auth.claimCalls, 0),
  );

  // A code is single-use. If the claim after an accepted code fails, the
  // retry must claim again without re-verifying the spent code.
  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'after a failed claim, a retry claims without re-verifying',
    build: () =>
        PhoneLinkCubit(auth..claimError = const ServerFailure('blip')),
    act: (c) async {
      await c.send('9876543210');
      await c.verify('123456');
      await c.verify('123456');
    },
    skip: 4,
    expect: () => [isA<PhoneLinkVerifying>(), isA<PhoneLinkDone>()],
    verify: (_) {
      expect(auth.verifyCalls, 1);
      expect(auth.claimCalls, 2);
    },
  );

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'a 409 from the claim shows the conflict message',
    build: () => PhoneLinkCubit(
      auth..claimError = const ServerFailure('x', code: '409'),
    ),
    act: (c) async {
      await c.send('9876543210');
      await c.verify('123456');
    },
    skip: 3,
    expect: () => [
      isA<PhoneLinkCodeSent>()
          .having((s) => s.error, 'error', AppStrings.claimConflict),
    ],
  );

  blocTest<PhoneLinkCubit, PhoneLinkState>(
    'a second verify while one is in flight is ignored',
    build: () => PhoneLinkCubit(auth),
    act: (c) async {
      await c.send('9876543210');
      await Future.wait([c.verify('123456'), c.verify('123456')]);
    },
    verify: (_) => expect(auth.verifyCalls, 1),
  );
}
