import 'dart:typed_data';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/photo_picker.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/profile_setup_cubit.dart';
import 'package:birthday_app/features/onboarding/profile_setup_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/avatar_repository.dart';
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

/// Records what the cubit asked of it; [error] makes the next call fail.
class _FakeAvatars implements AvatarRepository {
  Object? error;
  final uploads = <String>[];
  int removes = 0;

  @override
  Future<String> upload(Uint8List bytes, {required String extension}) async {
    if (error != null) throw error!;
    uploads.add(extension);
    return 'user-1/photo.$extension';
  }

  @override
  Future<void> remove() async {
    if (error != null) throw error!;
    removes++;
  }

  @override
  Future<String> signedUrl(String path) async => 'https://example/$path';
}

const _birthday = Birthday(month: 4, day: 15, year: 1991);

void main() {
  late _FakeAuth auth;
  late _FakeAvatars avatars;
  setUp(() {
    auth = _FakeAuth();
    avatars = _FakeAvatars();
  });

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a complete form saves and finishes',
    build: () => ProfileSetupCubit(auth, avatars),
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
      avatars,
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
      avatars,
    ),
    act: (c) => c.submit(
      handle: 'sachin',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [
      isA<ProfileSetupSaving>(),
      isA<ProfileSetupError>().having(
        (s) => s.handleTaken,
        'handleTaken',
        isFalse,
      ),
    ],
  );

  // The button disables on ProfileSetupSaving, but that only takes effect a
  // microtask after this state propagates -- the cubit is the source of
  // truth for what is in flight, mirroring PhoneCubit.submitCode (Task 7).
  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a second submit call while saving is ignored',
    build: () => ProfileSetupCubit(auth, avatars),
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
    build: () => ProfileSetupCubit(auth..verifiedPhone = true, avatars),
    act: (c) =>
        c.submit(handle: 'h', displayName: 'n', city: 'c', birthday: _birthday),
    verify: (_) => expect(auth.calls, ['claim', 'complete']),
  );

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'without a verified phone, submit does not try to claim',
    build: () => ProfileSetupCubit(auth..verifiedPhone = false, avatars),
    act: (c) =>
        c.submit(handle: 'h', displayName: 'n', city: 'c', birthday: _birthday),
    verify: (_) => expect(auth.claimCalls, 0),
  );

  group('photo', () {
    final photo = PhotoPicked(Uint8List.fromList([1, 2, 3]), 'png');

    blocTest<ProfileSetupCubit, ProfileSetupState>(
      'a picked photo is uploaded after the profile is completed',
      build: () => ProfileSetupCubit(auth, avatars),
      act: (c) => c.submit(
        handle: 'h',
        displayName: 'n',
        city: 'c',
        birthday: _birthday,
        photo: photo,
      ),
      expect: () => [isA<ProfileSetupSaving>(), isA<ProfileSetupDone>()],
      verify: (_) {
        expect(auth.completeProfileCalls, 1);
        expect(avatars.uploads, ['png']);
      },
    );

    blocTest<ProfileSetupCubit, ProfileSetupState>(
      'no photo means no upload',
      build: () => ProfileSetupCubit(auth, avatars),
      act: (c) => c.submit(
        handle: 'h',
        displayName: 'n',
        city: 'c',
        birthday: _birthday,
      ),
      verify: (_) => expect(avatars.uploads, isEmpty),
    );

    // A taken handle must not upload: the user renames and resubmits, and
    // each attempt would otherwise store another photo.
    blocTest<ProfileSetupCubit, ProfileSetupState>(
      'a rejected profile does not upload the photo',
      build: () => ProfileSetupCubit(
        auth..error = const ServerFailure('dup', code: '23505'),
        avatars,
      ),
      act: (c) => c.submit(
        handle: 'h',
        displayName: 'n',
        city: 'c',
        birthday: _birthday,
        photo: photo,
      ),
      verify: (_) => expect(avatars.uploads, isEmpty),
    );

    blocTest<ProfileSetupCubit, ProfileSetupState>(
      'a failed upload is its own error, and sign-up does not finish',
      build: () => ProfileSetupCubit(
        auth,
        avatars..error = const ServerFailure('storage down'),
      ),
      act: (c) => c.submit(
        handle: 'h',
        displayName: 'n',
        city: 'c',
        birthday: _birthday,
        photo: photo,
      ),
      expect: () => [
        isA<ProfileSetupSaving>(),
        isA<ProfileSetupError>()
            .having((s) => s.message, 'message', AppStrings.photoUploadFailed)
            .having((s) => s.handleTaken, 'handleTaken', false),
      ],
    );
  });
}
