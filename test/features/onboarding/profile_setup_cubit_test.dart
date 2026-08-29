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

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    completeProfileCalls++;
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
}
