import 'dart:async';

import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/router/deep_link.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile() => const Profile(
      id: 'u1',
      handle: 'h',
      displayName: 'D',
      city: 'C',
      birthday: Birthday(month: 1, day: 1),
      remindersEnabled: true,
    );

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.gate);

  /// Holds loadProfile open so the session genuinely sits in
  /// SessionUnknown, the way it does on a real cold start while the
  /// platform channel for getInitialMessage has already resolved.
  final Completer<void> gate;

  @override
  String? get currentUserId => 'u1';

  @override
  Future<Profile> loadProfile() async {
    await gate.future;
    return _profile();
  }

  @override
  Future<void> signOut() async {}

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test(
      'a cold-start deep link waits for the session instead of being '
      'discarded at /splash', () async {
    // THE regression this file exists for. app.dart used to call
    // _router.go(route) the moment getInitialMessage() resolved. At that
    // instant SessionCubit is still SessionUnknown, and buildRouter's
    // redirect sends every location but '/splash' to '/splash'; when the
    // session then resolves, '/splash' redirects on to '/timeline'. Net
    // effect: tapping a birthday notification with the app killed landed on
    // the timeline and the deep link was silently thrown away.
    final gate = Completer<void>();
    final session = SessionCubit(_FakeAuth(gate));
    final went = <String>[];

    final pending = navigateWhenSessionResolves(
      route: '/person/42',
      session: session,
      go: went.add,
    );

    session.load();
    await Future<void>.delayed(Duration.zero);

    // Nothing yet: navigating now is what loses the link.
    expect(went, isEmpty, reason: 'must not navigate while SessionUnknown');

    gate.complete();
    await pending;

    expect(went, ['/person/42']);
  });

  test('an already-resolved session navigates immediately', () async {
    final gate = Completer<void>()..complete();
    final session = SessionCubit(_FakeAuth(gate));
    await session.load();
    final went = <String>[];

    await navigateWhenSessionResolves(
      route: '/person/7',
      session: session,
      go: went.add,
    );

    expect(went, ['/person/7']);
  });
}
