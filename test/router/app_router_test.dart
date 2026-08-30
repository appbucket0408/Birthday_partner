import 'package:birthday_app/features/person/person_screen.dart';
import 'package:birthday_app/features/profile/celebration_list_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/birthday_stat.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/person_repository.dart';
import 'package:birthday_app/repositories/profile_repository.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:birthday_app/router/app_router.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:birthday_app/router/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// [buildRouter] takes a live [SessionCubit], never a plain [SessionState] --
/// so a test that wants a specific state without going through
/// [SessionCubit.load] (and the [AuthRepository] round trip that implies)
/// has to subclass it and [emit] directly. This is a fake session, not a
/// fake AuthRepository plus a real load(): [_FakeAuthRepository] below only
/// exists to satisfy the constructor and is never called.
class _StubSessionCubit extends SessionCubit {
  _StubSessionCubit(SessionState initial) : super(_FakeAuthRepository()) {
    emit(initial);
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  String? get currentUserId => null;

  @override
  Future<Profile> loadProfile() async => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real fakes, not mocks -- same pattern as
/// test/features/person/person_cubit_test.dart's `_FakePerson`/`_FakeWish`.
class _FakeGraphRepository implements GraphRepository {
  @override
  Future<List<Celebration>> celebrations() async => [];

  @override
  Future<void> updateBirthday(int personId, Birthday birthday) async {}

  @override
  Future<void> updateNickname(int celebrationId, String? nickname) async {}

  @override
  Future<void> stopCelebrating(int celebrationId) async {}
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<List<BirthdayStat>> stats() async => [];

  @override
  Future<List<Person>> celebrates() async => [];
}

class _FakePersonRepository implements PersonRepository {
  @override
  Future<Person> person(int personId) async =>
      Person(id: personId, displayName: 'Person $personId', isClaimed: false);

  @override
  Future<int> celebratorCount(int personId) async => 0;
}

class _FakeWishRepository implements WishRepository {
  @override
  Future<List<Wish>> wishesFor(int personId) async => [];

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  }) async {}
}

Profile _readyProfile() => const Profile(
      id: 'uuid',
      handle: 'u1',
      displayName: 'Test User',
      remindersEnabled: true,
      birthday: Birthday(month: 1, day: 1),
    );

/// Every repository a route builder in app_router.dart reads off context:
/// GraphRepository ('/profile/celebrating'), ProfileRepository
/// ('/profile/celebrates'), and PersonRepository/WishRepository/
/// GraphRepository again (PersonScreen, via PersonCubit). Registered here
/// exactly as app.dart registers them in production, via
/// MultiRepositoryProvider above MaterialApp.router -- never read by the
/// router itself, only by the screens the router builds.
Widget _appWith(GoRouter router) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider<GraphRepository>.value(value: _FakeGraphRepository()),
        RepositoryProvider<ProfileRepository>.value(
          value: _FakeProfileRepository(),
        ),
        RepositoryProvider<PersonRepository>.value(
          value: _FakePersonRepository(),
        ),
        RepositoryProvider<WishRepository>.value(value: _FakeWishRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );

/// Builds a router already sitting on [location], for a signed-in session.
///
/// The `.go(location)` call happens BEFORE the widget is ever pumped, and
/// that ordering is load-bearing, not incidental: `buildRouter`'s
/// `initialLocation` is hard-coded to '/splash', and if this test pumped the
/// router at that default location first, the SessionReady redirect would
/// send it to '/timeline' -- which builds the real `TimelineScreen`, which
/// falls back to `GraphRepositoryImpl(ApiClient.instance)` when no
/// repository is injected (see its class doc), which reaches for a Supabase
/// client this test never initializes and crashes.
///
/// Calling `.go` first means the FIRST redirect this router ever resolves is
/// against [location], not '/splash' -- '/timeline' is never touched unless
/// the redirect guard itself sends this router there, which is exactly the
/// thing under test.
GoRouter _routerAt(String location) {
  final session = _StubSessionCubit(SessionReady(_readyProfile()));
  final router = buildRouter(session);
  router.go(location);
  return router;
}

/// The current resolved location, read off the router directly rather than
/// by inspecting rendered widgets -- this stays valid even on the one path
/// (broken person-page guard) where the resolved screen fails to build.
String _locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('redirect guard', () {
    // The redirect guard's onPersonPage check (app_router.dart) is a prefix
    // match, `at.startsWith('/person/')`, because '/person/:personId' is the
    // one signed-in route with a path parameter and so can never appear in
    // the literal `signedIn` set. This exact route needed a mid-task fix
    // during Task 8 when the original template-matching approach made the
    // screen unreachable -- so this guard has already broken once for a
    // reason that looked plausible at the time. It had no test either time.
    testWidgets(
      '/person/1 is reachable and is not bounced back to /timeline',
      (tester) async {
        final router = _routerAt('/person/1');

        await tester.pumpWidget(_appWith(router));
        // Consumed, not asserted on: a broken guard sends this router to
        // '/timeline', which builds the real TimelineScreen and throws
        // (see _routerAt's doc) before this test's own assertion runs. That
        // crash is itself proof of the same bug the location check below
        // catches -- swallowing it here keeps the failure signal on the one
        // assertion this test is actually about, instead of a stack trace.
        tester.takeException();

        expect(
          _locationOf(router),
          '/person/1',
          reason: 'the redirect guard sent /person/1 elsewhere',
        );

        // With the guard intact, the rest of the frame is free to keep
        // settling: PersonScreen's own cubit resolves against the fakes
        // above and the page actually renders.
        await tester.pumpAndSettle();
        expect(find.byType(PersonView), findsOneWidget);
      },
    );
  });

  group('CelebrationListScreen navigability per route', () {
    // test/features/profile/celebration_list_screen_test.dart pins the
    // widget's own default (false) and that passing `true` works, but never
    // exercises the route that is supposed to leave `navigable` at that
    // default. Adding `navigable: true` to '/profile/celebrates' in
    // app_router.dart today leaves every existing test green -- this is the
    // one test that would not be.
    testWidgets(
      "'/profile/celebrates' yields navigable: false",
      (tester) async {
        final router = _routerAt('/profile/celebrates');
        await tester.pumpWidget(_appWith(router));
        await tester.pumpAndSettle();

        final screen = tester.widget<CelebrationListScreen>(
          find.byType(CelebrationListScreen),
        );
        expect(screen.navigable, isFalse);
      },
    );

    testWidgets(
      "'/profile/celebrating' yields navigable: true",
      (tester) async {
        final router = _routerAt('/profile/celebrating');
        await tester.pumpWidget(_appWith(router));
        await tester.pumpAndSettle();

        final screen = tester.widget<CelebrationListScreen>(
          find.byType(CelebrationListScreen),
        );
        expect(screen.navigable, isTrue);
      },
    );
  });
}
