import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/profile_setup_cubit.dart';
import 'package:birthday_app/features/onboarding/profile_setup_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  Object? error;
  Map<String, dynamic>? saved;
  int completeProfileCalls = 0;
  int claimCalls = 0;
  final calls = <String>[];

  bool verifiedPhone = false;

  @override
  bool get hasVerifiedPhone => verifiedPhone;

  @override
  Future<int> claimProfile() async {
    claimCalls++;
    calls.add('claim');
    return 1;
  }

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    completeProfileCalls++;
    calls.add('complete');
    if (error != null) throw error!;
    saved = {
      'handle': handle,
      'displayName': displayName,
      'city': city,
      'birthday': birthday,
    };
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _birthday = Birthday(month: 4, day: 15, year: 1991);

void main() {
  late _FakeAuth auth;
  setUp(() => auth = _FakeAuth());

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a complete form saves and finishes',
    build: () => ProfileSetupCubit(auth),
    act: (c) => c.submit(
      handle: 'sachin',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [isA<ProfileSetupSaving>(), isA<ProfileSetupDone>()],
    verify: (_) => expect(auth.saved!['handle'], 'sachin'),
  );

  // 23505 is reachable on the first screen a user sees, because every account
  // starts with a valid placeholder handle -- this is renaming, not naming.
  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a taken handle is its own error, not a generic failure',
    build: () => ProfileSetupCubit(
      auth..error = const ServerFailure('duplicate key', code: '23505'),
    ),
    act: (c) => c.submit(
      handle: 'taken',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [
      isA<ProfileSetupSaving>(),
      isA<ProfileSetupError>()
          .having((s) => s.handleTaken, 'handleTaken', isTrue)
          .having((s) => s.message, 'message', AppStrings.setupHandleTaken),
    ],
  );

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'any other server error is generic and not attributed to the handle',
    build: () => ProfileSetupCubit(
      auth..error = const ServerFailure('down', code: '08006'),
    ),
    act: (c) => c.submit(
      handle: 'sachin',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [
      isA<ProfileSetupSaving>(),
      isA<ProfileSetupError>().having((s) => s.handleTaken, 'handleTaken', isFalse),
    ],
  );

  // The button disables on ProfileSetupSaving, but that only takes effect a
  // microtask after this state propagates -- the cubit is the source of
  // truth for what is in flight, mirroring PhoneCubit.submitCode (Task 7).
  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a second submit call while saving is ignored',
    build: () => ProfileSetupCubit(auth),
    act: (c) async {
      final first = c.submit(
        handle: 'sachin',
        displayName: 'Sachin',
        city: 'Jaipur',
        birthday: _birthday,
      );
      final second = c.submit(
        handle: 'sachin',
        displayName: 'Sachin',
        city: 'Jaipur',
        birthday: _birthday,
      );
      await Future.wait([first, second]);
    },
    verify: (_) => expect(auth.completeProfileCalls, 1),
  );

  // Safety net for an email sign-up whose phone got verified but whose
  // claim never ran: finishing without it would leave no person behind the
  // account. It must run BEFORE the profile is completed.
  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'with a verified phone, submit claims before completing the profile',
    build: () => ProfileSetupCubit(auth..verifiedPhone = true),
    act: (c) => c.submit(
      handle: 'h',
      displayName: 'n',
      city: 'c',
      birthday: _birthday,
    ),
    verify: (_) => expect(auth.calls, ['claim', 'complete']),
  );

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'without a verified phone, submit does not try to claim',
    build: () => ProfileSetupCubit(auth..verifiedPhone = false),
    act: (c) => c.submit(
      handle: 'h',
      displayName: 'n',
      city: 'c',
      birthday: _birthday,
    ),
    verify: (_) => expect(auth.claimCalls, 0),
  );
}
