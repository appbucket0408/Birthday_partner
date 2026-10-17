import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/phone_cubit.dart';
import 'package:birthday_app/features/onboarding/phone_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  Object? sendError;
  Object? verifyError;
  int sendCalls = 0;
  int verifyCalls = 0;
  String? lastPhone;

  int emailSendCalls = 0;
  int emailVerifyCalls = 0;
  String? lastEmail;
  int claimCalls = 0;

  /// A phone sign-in always ends with a verified phone; an email one does
  /// not until sign-up links one.
  bool verifiedPhone = true;

  /// What loadProfile returns after sign-in; null throws, as a failed load.
  Profile? profile = _newUser;

  @override
  bool get hasVerifiedPhone => verifiedPhone;

  @override
  Future<void> sendEmailOtp(String email) async {
    emailSendCalls++;
    lastEmail = email;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    emailVerifyCalls++;
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<Profile> loadProfile() async =>
      profile ?? (throw const ServerFailure('profile load failed'));

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
  Future<int> claimProfile() async {
    claimCalls++;
    return 1;
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// Fresh from the signup trigger: no birthday, so not onboarded yet.
const _newUser = Profile(
  id: 'u',
  handle: 'ux',
  displayName: 'New user',
  remindersEnabled: true,
);

const _returningUser = Profile(
  id: 'u',
  handle: 'sachin',
  displayName: 'Sachin',
  remindersEnabled: true,
  birthday: Birthday(month: 3, day: 12),
);

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
          .having((s) => s.destination, 'destination', '+919999000001'),
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

  // B5: PhoneNumber.parse itself throws PhoneNumberException on some inputs
  // rather than returning an invalid-but-parsed number -- '+09876543210' in
  // particular is an ordinary typo (an Indian number typed with the trunk
  // '0' after the '+'), not a garbage string. Without a try/catch around
  // the parse call, submitPhone throws uncaught, no state is emitted, and
  // "Send code" does nothing forever. Every input below must land on
  // PhoneError(AppStrings.phoneInvalid) and never reach the repository --
  // mirrors the wrapping already done at contacts_repository_impl.dart:54-62
  // and import_cubit.dart:142-147.
  group('inputs that throw out of PhoneNumber.parse itself', () {
    for (final raw in ['+09876543210', '+', '+0', '00', '+999999999']) {
      blocTest<PhoneCubit, PhoneState>(
        '"$raw" emits PhoneError without calling the repository',
        build: () => PhoneCubit(auth),
        act: (c) => c.submitPhone(raw),
        expect: () => [
          isA<PhoneError>().having(
            (s) => s.message,
            'message',
            AppStrings.phoneInvalid,
          ),
        ],
        verify: (_) => expect(auth.sendCalls, 0),
      );
    }
  });

  group('email', () {
    blocTest<PhoneCubit, PhoneState>(
      'a valid email is trimmed, lower-cased and sent',
      build: () => PhoneCubit(auth),
      act: (c) => c.submitEmail('  Sachin@Example.COM '),
      expect: () => [
        isA<PhoneSending>(),
        isA<PhoneCodeSent>()
            .having((s) => s.destination, 'destination', 'sachin@example.com'),
      ],
      verify: (_) {
        expect(auth.lastEmail, 'sachin@example.com');
        expect(auth.sendCalls, 0, reason: 'must not send an SMS');
      },
    );

    for (final raw in ['', 'sachin', 'sachin@', '@example.com', 'a b@c.d']) {
      blocTest<PhoneCubit, PhoneState>(
        '"$raw" fails locally without calling the repository',
        build: () => PhoneCubit(auth),
        act: (c) => c.submitEmail(raw),
        expect: () => [
          isA<PhoneError>()
              .having((s) => s.message, 'message', AppStrings.emailInvalid),
        ],
        verify: (_) => expect(auth.emailSendCalls, 0),
      );
    }

    // claim_profile refuses a session with no verified phone, so a new
    // email account must not call it here; sign-up does, after linking one.
    blocTest<PhoneCubit, PhoneState>(
      'an email code verifies by email and skips the claim without a phone',
      build: () => PhoneCubit(auth..verifiedPhone = false),
      act: (c) async {
        await c.submitEmail('a@b.co');
        await c.submitCode('123456');
      },
      expect: () => [
        isA<PhoneSending>(),
        isA<PhoneCodeSent>(),
        isA<PhoneVerifying>(),
        isA<PhoneVerified>(),
      ],
      verify: (_) {
        expect(auth.emailVerifyCalls, 1);
        expect(auth.verifyCalls, 0);
        expect(auth.claimCalls, 0);
      },
    );

    blocTest<PhoneCubit, PhoneState>(
      'a returning email user who already linked a phone claims as usual',
      build: () => PhoneCubit(auth..verifiedPhone = true),
      act: (c) async {
        await c.submitEmail('a@b.co');
        await c.submitCode('123456');
      },
      verify: (_) => expect(auth.claimCalls, 1),
    );

    blocTest<PhoneCubit, PhoneState>(
      'resend after an email sends the email again, never an SMS',
      build: () => PhoneCubit(auth),
      act: (c) async {
        await c.submitEmail('a@b.co');
        await c.resend();
      },
      verify: (_) {
        expect(auth.emailSendCalls, 2);
        expect(auth.sendCalls, 0);
      },
    );
  });

  group('welcome back', () {
    blocTest<PhoneCubit, PhoneState>(
      'a returning, onboarded user is greeted by name',
      build: () => PhoneCubit(auth..profile = _returningUser),
      act: (c) async {
        await c.submitPhone('9999000001');
        await c.submitCode('123456');
      },
      skip: 3,
      expect: () => [
        isA<PhoneVerified>()
            .having((s) => s.welcomeName, 'welcomeName', 'Sachin'),
      ],
    );

    blocTest<PhoneCubit, PhoneState>(
      'a new user gets no greeting (they go to sign-up)',
      build: () => PhoneCubit(auth..profile = _newUser),
      act: (c) async {
        await c.submitPhone('9999000001');
        await c.submitCode('123456');
      },
      skip: 3,
      expect: () => [
        isA<PhoneVerified>().having((s) => s.welcomeName, 'welcomeName', null),
      ],
    );

    // The greeting is cosmetic: failing to load the profile for it must not
    // turn a successful sign-in into an error.
    blocTest<PhoneCubit, PhoneState>(
      'a failed profile load still signs in, without a greeting',
      build: () => PhoneCubit(auth..profile = null),
      act: (c) async {
        await c.submitPhone('9999000001');
        await c.submitCode('123456');
      },
      skip: 3,
      expect: () => [
        isA<PhoneVerified>().having((s) => s.welcomeName, 'welcomeName', null),
      ],
    );
  });
}
