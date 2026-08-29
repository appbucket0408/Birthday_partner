import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:birthday_app/router/session_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake is right here and wrong for repositories. This tests state
/// transitions, which are the Cubit's own logic; the repository's behaviour is
/// covered against real Supabase in Task 5.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.userId, this.profile, this.throwOnLoad = false});

  String? userId;
  Profile? profile;
  bool throwOnLoad;

  @override
  String? get currentUserId => userId;

  @override
  Future<Profile> loadProfile() async {
    if (throwOnLoad) throw const ServerFailure('boom');
    return profile!;
  }

  @override
  Future<void> signOut() async {
    userId = null;
    profile = null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile({Birthday? birthday}) => Profile(
      id: 'uuid',
      handle: 'u123',
      displayName: 'New user',
      remindersEnabled: true,
      birthday: birthday,
    );

void main() {
  blocTest<SessionCubit, SessionState>(
    'no session resolves to signed out',
    build: () => SessionCubit(_FakeAuthRepository()),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionSignedOut>()],
  );

  blocTest<SessionCubit, SessionState>(
    'a session with no birthday needs setup',
    build: () => SessionCubit(
      _FakeAuthRepository(userId: 'uuid', profile: _profile()),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionNeedsSetup>()],
  );

  blocTest<SessionCubit, SessionState>(
    'a session with a birthday is ready',
    build: () => SessionCubit(
      _FakeAuthRepository(
        userId: 'uuid',
        profile: _profile(birthday: const Birthday(month: 4, day: 15)),
      ),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionReady>()],
  );

  // A profile that cannot be read must not strand the user on a blank screen.
  // Signing them out is recoverable; an unknown state is not.
  blocTest<SessionCubit, SessionState>(
    'a failed profile load falls back to signed out',
    build: () => SessionCubit(
      _FakeAuthRepository(userId: 'uuid', throwOnLoad: true),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionSignedOut>()],
  );

  blocTest<SessionCubit, SessionState>(
    'signOut returns to signed out',
    build: () => SessionCubit(
      _FakeAuthRepository(
        userId: 'uuid',
        profile: _profile(birthday: const Birthday(month: 4, day: 15)),
      ),
    ),
    act: (cubit) async {
      await cubit.load();
      await cubit.signOut();
    },
    expect: () => [isA<SessionReady>(), isA<SessionSignedOut>()],
  );
}
