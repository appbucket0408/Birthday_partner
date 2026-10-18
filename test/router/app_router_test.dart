import 'dart:typed_data';

import 'package:birthday_app/features/calendar/calendar_screen.dart';
import 'package:birthday_app/features/gifting/cake_coming_soon_screen.dart';
import 'package:birthday_app/features/gifting/gift_list_screen.dart';
import 'package:birthday_app/features/person/person_screen.dart';
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/connections/connections_screen.dart';
import 'package:birthday_app/features/feed/feed_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/birthday_stat.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/models/feed_entry.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/avatar_repository.dart';
import 'package:birthday_app/repositories/gift_interest_repository.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
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

  // Whole-branch review §8 should-fix 5: the '/profile' route's own
  // ProfileScreen (via ProfileCubit) calls this during load(), which no
  // test in this file needed until the "My gifts" tile arrival test below
  // needed to actually reach a rendered ProfileScreen. Returning a real
  // profile rather than throwing costs nothing -- no existing test in this
  // file ever reached '/profile' before, so nothing depended on the throw.
  @override
  Future<Profile> loadProfile() async => _readyProfile();

  @override
  Future<void> signOut() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real fakes, not mocks -- same pattern as
/// test/features/person/person_cubit_test.dart's `_FakePerson`/`_FakeWish`.
class _FakeAvatarRepository implements AvatarRepository {
  @override
  Future<String> upload(Uint8List bytes, {required String extension}) async =>
      throw UnimplementedError('not exercised by these route tests');

  @override
  Future<void> remove() async {}

  @override
  Future<String> signedUrl(String path) async => 'https://example/$path';
}

class _FakeGiftInterestRepository implements GiftInterestRepository {
  @override
  Future<bool> isRegistered(int personId) async => false;

  @override
  Future<void> register(int personId) async {}
}

class _FakeGraphRepository implements GraphRepository {
  Set<int> celebratesMeSet = const {};
  final celebratedBack = <int>[];

  @override
  Future<Set<int>> celebratesMe() async => celebratesMeSet;

  @override
  Future<void> celebrateBack(int personId) async =>
      celebratedBack.add(personId);

  @override
  Future<List<Celebration>> celebrations() async => [];

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

class _FakeGiftRepository implements GiftRepository {
  @override
  Future<List<ServiceArea>> serviceAreas() async => [];

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async => [];

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async =>
      [];

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async =>
      throw UnimplementedError('not exercised by these route tests');

  @override
  Future<List<Gift>> myGifts() async => [];
}

// Whole-branch review §8 should-fix 5: person_screen.dart's "Send a cake"
// tile is gated on `_canComposeFor` (a non-null birthday AND
// viewerCelebrates), which _FakePersonRepository/_FakeGraphRepository above
// never satisfy (no birthday, no celebrations). These two exist only to
// satisfy that gate for the one arrival test that needs the tile to
// actually render.
class _ComposablePersonRepository extends _FakePersonRepository {
  @override
  Future<Person> person(int personId) async => Person(
        id: personId,
        displayName: 'Compose Target',
        isClaimed: true,
        birthday: const Birthday(month: 6, day: 1),
      );
}

class _CelebratingGraphRepository extends _FakeGraphRepository {
  _CelebratingGraphRepository(this._personId);
  final int _personId;

  @override
  Future<List<Celebration>> celebrations() async => [
        Celebration(
          id: 1,
          person: Person(
            id: _personId,
            displayName: 'Compose Target',
            isClaimed: true,
            birthday: const Birthday(month: 6, day: 1),
          ),
        ),
      ];
}

class _FakeWishRepository implements WishRepository {
  @override
  Future<List<Wish>> wishesFor(int personId) async => [];

  @override
  Future<List<Wish>> wishesToMe() async => [];

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
    String? photoPath,
  }) async {}

  @override
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String extension,
  }) async =>
      throw UnimplementedError('not used by the router');

  @override
  Future<void> removePhoto(String path) async =>
      throw UnimplementedError('not used by the router');

  @override
  Future<String> photoUrl(String path) async =>
      throw UnimplementedError('not used by the router');

  @override
  Future<List<FeedEntry>> feed({DateTime? before, int limit = 20}) async =>
      const [];
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
/// ('/profile/celebrates'), PersonRepository/WishRepository/GraphRepository
/// again (PersonScreen, via PersonCubit), and now GiftRepository/
/// PersonRepository again (CatalogScreen, via CatalogCubit). Registered here
/// exactly as app.dart registers them in production, via
/// MultiRepositoryProvider above MaterialApp.router -- never read by the
/// router itself, only by the screens the router builds.
Widget _appWith(
  GoRouter router, {
  PersonRepository? personRepository,
  GraphRepository? graphRepository,
}) =>
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<GraphRepository>.value(
          value: graphRepository ?? _FakeGraphRepository(),
        ),
        RepositoryProvider<ProfileRepository>.value(
          value: _FakeProfileRepository(),
        ),
        RepositoryProvider<PersonRepository>.value(
          value: personRepository ?? _FakePersonRepository(),
        ),
        RepositoryProvider<WishRepository>.value(value: _FakeWishRepository()),
        RepositoryProvider<GiftRepository>.value(value: _FakeGiftRepository()),
        RepositoryProvider<GiftInterestRepository>.value(
          value: _FakeGiftInterestRepository(),
        ),
        // Needed by '/profile' (ProfileScreen -> ProfileCubit._auth), added
        // alongside the should-fix 5 arrival tests below -- no earlier test
        // in this file ever reached '/profile'.
        RepositoryProvider<AuthRepository>.value(value: _FakeAuthRepository()),
        RepositoryProvider<AvatarRepository>.value(
          value: _FakeAvatarRepository(),
        ),
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
///
/// Returns both the router AND the session that backs it: `buildRouter`'s
/// `refreshListenable` subscribes to `session.stream` internally, so a
/// caller that only kept the router has no way to end that subscription --
/// closing the session (which ends its stream) is what lets it wind down.
({SessionCubit session, GoRouter router}) _routerAt(String location) {
  final session = _StubSessionCubit(SessionReady(_readyProfile()));
  final router = buildRouter(session);
  router.go(location);
  return (session: session, router: router);
}

/// Disposes a fixture from [_routerAt] in the order that matters: the
/// router first, so it unhooks its listener from the session's stream
/// before that stream ends, then the session itself, which closes its
/// stream and lets the internal `_CubitRefresh` subscription (private to
/// app_router.dart, unreachable from this file) wind down rather than
/// leak for the rest of the test run.
Future<void> _disposeFixture(({SessionCubit session, GoRouter router}) fixture) async {
  fixture.router.dispose();
  await fixture.session.close();
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
        final fixture = _routerAt('/person/1');
        addTearDown(() => _disposeFixture(fixture));
        final router = fixture.router;

        await tester.pumpWidget(_appWith(router));
        // A broken guard sends this router to '/timeline', which builds the
        // real TimelineScreen and throws (see _routerAt's doc) before this
        // test's own assertion runs. That crash is itself proof of the same
        // bug the location check below catches, so it is consumed here
        // rather than asserted on -- but only that ONE exception: anything
        // else escaping this pump is a real, unrelated failure and must
        // fail this test, not be swallowed alongside it.
        final err = tester.takeException();
        if (err != null) {
          expect(
            err.toString(),
            contains('You must initialize the supabase instance'),
            reason: 'unexpected exception during pump (not the '
                'expected TimelineScreen/Supabase crash): $err',
          );
        }

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

    // A tapped "new wish" notification routes to /person/<id>?wish=<id>.
    // The guard matches on the path, so the query must not bounce it, and
    // the router hands the page only a positive id -- a deep link can carry
    // any query string at all.
    for (final (query, expected) in [
      ('?wish=9', 9),
      ('?wish=0', null),
      ('?wish=abc', null),
      ('?wish=-3', null),
      ('', null),
    ]) {
      testWidgets(
        '/person/1$query reaches the page with openWishId $expected',
        (tester) async {
          final fixture = _routerAt('/person/1$query');
          addTearDown(() => _disposeFixture(fixture));

          await tester.pumpWidget(_appWith(fixture.router));
          await tester.pumpAndSettle();

          expect(
            tester.widget<PersonView>(find.byType(PersonView)).openWishId,
            expected,
          );
        },
      );
    }

    // Task 5's own version of the exact same bug: '/gift/new/:personId' is
    // the one other signed-in route with a path parameter, so it needs the
    // identical prefix check (`onGiftCatalogPage` in app_router.dart) rather
    // than a literal `signedIn` entry. This route had no test until now,
    // same as '/person/:personId' before Task 8 caught it.
    testWidgets(
      '/gift/new/1 is reachable and is not bounced back to /timeline',
      (tester) async {
        final fixture = _routerAt('/gift/new/1');
        addTearDown(() => _disposeFixture(fixture));
        final router = fixture.router;

        await tester.pumpWidget(_appWith(router));
        // See the '/person/1' test above for why only this one exception is
        // swallowed rather than asserted on.
        final err = tester.takeException();
        if (err != null) {
          expect(
            err.toString(),
            contains('You must initialize the supabase instance'),
            reason: 'unexpected exception during pump (not the '
                'expected CatalogScreen/Supabase crash): $err',
          );
        }

        expect(
          _locationOf(router),
          '/gift/new/1',
          reason: 'the redirect guard sent /gift/new/1 elsewhere',
        );

        await tester.pumpAndSettle();
        expect(find.byType(CakeComingSoonView), findsOneWidget);
      },
    );

    // Task 8: '/gifts' had NO GoRoute at all until this task -- a signed-in
    // user who completed a draft and tapped "See my gifts" landed on
    // go_router's default unmatched-route error page (draft_screen.dart's
    // `context.go('/gifts')` was a live dead end). The test that would have
    // caught it needs the REAL buildRouter, not an inline test router --
    // draft_screen_test.dart's "See my gifts" test builds its own
    // GoRouter with a '/gifts' GoRoute declared inline, so it proved the
    // button's onPressed callback, never that the production router could
    // resolve the destination. This is that missing test: it proves BOTH
    // that '/gifts' resolves through buildRouter, and that the redirect
    // guard ADMITS a signed-in user there rather than bouncing them to
    // '/timeline' -- the same shape of test as '/person/1' and
    // '/gift/new/1' above, for the one other real, parameterless route
    // this phase adds.
    testWidgets(
      '/gifts is reachable and is not bounced back to /timeline',
      (tester) async {
        final fixture = _routerAt('/gifts');
        addTearDown(() => _disposeFixture(fixture));
        final router = fixture.router;

        await tester.pumpWidget(_appWith(router));
        // See the '/person/1' test above for why only this one exception is
        // swallowed rather than asserted on.
        final err = tester.takeException();
        if (err != null) {
          expect(
            err.toString(),
            contains('You must initialize the supabase instance'),
            reason: 'unexpected exception during pump (not the '
                'expected GiftListScreen/Supabase crash): $err',
          );
        }

        expect(
          _locationOf(router),
          '/gifts',
          reason: 'the redirect guard sent /gifts elsewhere',
        );

        await tester.pumpAndSettle();
        expect(find.byType(GiftListView), findsOneWidget);
      },
    );
  });

  // Both Profile counts open the same screen; each route must land on its
  // own tab, or tapping "Celebrate me" would show "I celebrate".
  group('connections routes open the right tab', () {
    for (final (route, tab, emptyText) in [
      (
        '/profile/celebrating',
        ConnectionsTab.iCelebrate,
        AppStrings.profileCelebratingEmpty,
      ),
      (
        '/profile/celebrates',
        ConnectionsTab.celebrateMe,
        AppStrings.profileCelebratesEmpty,
      ),
    ]) {
      testWidgets('$route opens on ${tab.name}', (tester) async {
        final fixture = _routerAt(route);
        addTearDown(() => _disposeFixture(fixture));
        await tester.pumpWidget(_appWith(fixture.router));
        await tester.pumpAndSettle();

        final screen = tester.widget<ConnectionsScreen>(
          find.byType(ConnectionsScreen),
        );
        expect(screen.initialTab, tab);
        // Only the visible tab is built; its empty state proves which.
        expect(find.text(emptyText), findsOneWidget);
      });
    }
  });

  // Whole-branch review §8 should-fix 5: two navigation edges the same shape
  // as the '/gifts' dead end Task 8 fixed -- reachable only by tapping a
  // button whose destination path string no test exercised. Both go through
  // the REAL buildRouter, not an inline test router (the exact gap that let
  // '/gifts' hide): profile_screen_test.dart and person_screen_test.dart
  // each prove the tile renders and is visible, never that tapping it
  // actually arrives anywhere.
  group('navigation edges with no arrival test (whole-branch review §8)', () {
    testWidgets(
      'tapping "My gifts" on the profile page arrives at /gifts through '
      'the real router', (tester) async {
        final fixture = _routerAt('/profile');
        addTearDown(() => _disposeFixture(fixture));
        final router = fixture.router;

        await tester.pumpWidget(_appWith(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile_my_gifts_tile')));
        await tester.pumpAndSettle();

        expect(
          _locationOf(router),
          '/gifts',
          reason: 'tapping the "My gifts" tile did not arrive at /gifts',
        );
        expect(find.byType(GiftListView), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "Send a cake" on the person page arrives at '
      '/gift/new/:personId through the real router', (tester) async {
        const personId = 42;
        final fixture = _routerAt('/person/$personId');
        addTearDown(() => _disposeFixture(fixture));
        final router = fixture.router;

        await tester.pumpWidget(
          _appWith(
            router,
            personRepository: _ComposablePersonRepository(),
            graphRepository: _CelebratingGraphRepository(personId),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('gift_send_cake_button')));
        await tester.pumpAndSettle();

        expect(
          _locationOf(router),
          '/gift/new/$personId',
          reason: 'tapping "Send a cake" did not arrive at /gift/new/:personId',
        );
        expect(find.byType(CakeComingSoonView), findsOneWidget);
      },
    );
  });

  // The bottom bar wraps exactly the four tabs. '/timeline' is never
  // pumped here for the reason _routerAt's doc gives (it reaches for a real
  // Supabase client), so the tab tests start from Feed, Profile and Calendar.
  group('bottom navigation', () {
    testWidgets('a signed-in session lands on the Feed', (tester) async {
      final fixture = _routerAt('/splash');
      addTearDown(() => _disposeFixture(fixture));

      await tester.pumpWidget(_appWith(fixture.router));
      await tester.pumpAndSettle();

      expect(_locationOf(fixture.router), '/feed');
      expect(find.byType(FeedView), findsOneWidget);
      final bar = tester.widget<NavigationBar>(
        find.byKey(const Key('home_nav_bar')),
      );
      expect(bar.selectedIndex, 0);
    });

    testWidgets('the tabs are Feed, Dashboard, Calendar, Profile in order',
        (tester) async {
      final fixture = _routerAt('/feed');
      addTearDown(() => _disposeFixture(fixture));

      await tester.pumpWidget(_appWith(fixture.router));
      await tester.pumpAndSettle();

      final keys = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => (d.key! as ValueKey<String>).value)
          .toList();
      expect(keys, ['nav_feed', 'nav_dashboard', 'nav_calendar', 'nav_profile']);
    });

    testWidgets('tapping the Feed tab on Profile arrives at /feed',
        (tester) async {
      final fixture = _routerAt('/profile');
      addTearDown(() => _disposeFixture(fixture));

      await tester.pumpWidget(_appWith(fixture.router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_feed')));
      await tester.pumpAndSettle();

      expect(_locationOf(fixture.router), '/feed');
      expect(find.byType(FeedView), findsOneWidget);
    });

    testWidgets('/calendar is reachable and shows the bottom bar',
        (tester) async {
      final fixture = _routerAt('/calendar');
      addTearDown(() => _disposeFixture(fixture));

      await tester.pumpWidget(_appWith(fixture.router));
      await tester.pumpAndSettle();

      expect(_locationOf(fixture.router), '/calendar');
      expect(find.byType(CalendarView), findsOneWidget);
      expect(find.byKey(const Key('home_nav_bar')), findsOneWidget);
    });

    testWidgets('tapping the Calendar tab on Profile arrives at /calendar',
        (tester) async {
      final fixture = _routerAt('/profile');
      addTearDown(() => _disposeFixture(fixture));

      await tester.pumpWidget(_appWith(fixture.router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_nav_bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav_calendar')));
      await tester.pumpAndSettle();

      expect(_locationOf(fixture.router), '/calendar');
      expect(find.byType(CalendarView), findsOneWidget);
    });

    testWidgets('full-screen pages like /gifts do not show the bottom bar',
        (tester) async {
      final fixture = _routerAt('/gifts');
      addTearDown(() => _disposeFixture(fixture));

      await tester.pumpWidget(_appWith(fixture.router));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_nav_bar')), findsNothing);
    });
  });

  // Whole-branch review §8 should-fix 4: app.dart configured NO errorBuilder
  // at all -- Task 8 closed the one known instance ('/gifts'), not the
  // class. Any unmatched location landed on go_router's own default error
  // page, with no way back into the app.
  group('errorBuilder', () {
    testWidgets(
      'an unknown location renders the error page, which can navigate home',
      (tester) async {
        final fixture = _routerAt('/this-route-does-not-exist');
        addTearDown(() => _disposeFixture(fixture));
        final router = fixture.router;

        await tester.pumpWidget(_appWith(router));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('router_error_go_home')), findsOneWidget);

        await tester.tap(find.byKey(const Key('router_error_go_home')));
        await tester.pumpAndSettle();

        expect(
          _locationOf(router),
          '/feed',
          reason: 'the error page\'s home button did not navigate to /feed',
        );
        expect(find.byType(FeedView), findsOneWidget);
      },
    );
  });
}
