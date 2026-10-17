import 'package:birthday_app/core/app_links.dart';
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/timeline/timeline_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:birthday_app/router/session_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A real GraphRepository fake, not a mock -- the screen is exercised
/// through a real TimelineCubit, following the pattern in
/// test/features/contacts_import/import_pick_screen_test.dart.
class _FakeGraph implements GraphRepository {
  Set<int> celebratesMeSet = const {};
  final celebratedBack = <int>[];

  @override
  Future<Set<int>> celebratesMe() async => celebratesMeSet;

  @override
  Future<void> celebrateBack(int personId) async =>
      celebratedBack.add(personId);

  _FakeGraph(this.celebrationsList);

  final List<Celebration> celebrationsList;

  @override
  Future<List<Celebration>> celebrations() async => celebrationsList;

  @override
  Future<void> stopCelebrating(int celebrationId) async {}
}

Person _person(int id, {Birthday? birthday, bool isClaimed = false}) =>
    Person(id: id, displayName: 'Person $id', isClaimed: isClaimed,
        birthday: birthday);

Celebration _celeb(int id, Person person) => Celebration(id: id, person: person);

class _FakePush implements PushRepository {
  /// notDetermined, not granted: this fake exists to prove the screen
  /// actually ASKS, and a pre-granted fake would skip the prompt and make
  /// the reachability assertion below vacuous.
  PushPermission status = PushPermission.notDetermined;

  @override
  Future<PushPermission> currentPermission() async => status;

  int permissionCalls = 0;
  int registerCalls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return true;
  }

  @override
  Future<void> registerThisDevice() async => registerCalls++;

  @override
  Future<void> deleteThisDeviceToken() async {}

  @override
  Stream<String> get notificationRoutes => const Stream.empty();

  @override
  Future<String?> initialRoute() async => null;
}

DateTime _fixedNow() => DateTime(2026, 4, 15);

/// The Dashboard header reads the signed-in profile off [SessionCubit].
/// Same stub shape as test/router/app_router_test.dart's: emit a state
/// directly, never call load().
class _StubSessionCubit extends SessionCubit {
  _StubSessionCubit(SessionState initial) : super(_UnusedAuth()) {
    emit(initial);
  }
}

class _UnusedAuth implements AuthRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _me = Profile(
  id: 'user-1',
  handle: 'sachin',
  displayName: 'Sachin',
  remindersEnabled: true,
  city: 'Jaipur',
  birthday: Birthday(month: 3, day: 12),
);

/// Wraps [child] the way app.dart does: the session above everything else.
Widget _withSession(Widget child) => BlocProvider<SessionCubit>(
      create: (_) => _StubSessionCubit(const SessionReady(_me)),
      child: child,
    );

Future<void> pump(WidgetTester tester, List<Celebration> celebrations) async {
  // TimelineScreen creates a PushCubit eagerly (lazy: false), so this
  // provider is required now -- arriving at the timeline is what asks for
  // notification permission.
  await tester.pumpWidget(
    _withSession(
      MaterialApp(
        home: RepositoryProvider<PushRepository>.value(
          value: _FakePush(),
          child: TimelineScreen(
            repository: _FakeGraph(celebrations),
            now: _fixedNow,
          ),
        ),
      ),
    ),
  );
  // load() is fired from TimelineScreen.build() but not awaited there --
  // let its future resolve and the screen rebuild off the loaded state.
  await tester.pumpAndSettle();
}

void main() {
  // 1. Group headers render only for non-empty groups. Two celebrations
  //    land in today and later; thisWeek, thisMonth and the no-birthday
  //    bucket have nothing in them and must not print a header for nothing.
  testWidgets('group headers render only for non-empty groups', (
    tester,
  ) async {
    await pump(tester, [
      _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
      _celeb(2, _person(2, birthday: const Birthday(month: 9, day: 1))),
    ]);

    // Each heading carries its count.
    expect(find.text('${AppStrings.timelineToday} · 1'), findsOneWidget);
    expect(find.text('${AppStrings.timelineLater} · 1'), findsOneWidget);
    expect(find.textContaining(AppStrings.timelineThisWeek), findsNothing);
    expect(find.textContaining(AppStrings.timelineThisMonth), findsNothing);
    expect(find.textContaining(AppStrings.timelineWaitingToJoin), findsNothing);
  });

  // 2. A person with no birthday -- someone not on the app yet -- is listed
  //    under "Waiting to join", with the line explaining why.
  testWidgets('a person with no birthday is under Waiting to join', (
    tester,
  ) async {
    await pump(tester, [_celeb(1, _person(1))]);

    expect(
      find.text('${AppStrings.timelineWaitingToJoin} · 1'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('timeline_waiting_hint')), findsOneWidget);
    expect(find.text('Person 1'), findsOneWidget);
  });

  // 3. The empty state shows the import CTA.
  testWidgets('the empty state shows the import CTA', (tester) async {
    await pump(tester, []);

    expect(find.text(AppStrings.timelineEmptyTitle), findsOneWidget);
    expect(find.text(AppStrings.timelineEmptyBody), findsOneWidget);
    final cta = tester.widget<FilledButton>(
      find.byKey(const Key('timeline_import_cta')),
    );
    expect(cta.onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('timeline_import_cta')),
        matching: find.text(AppStrings.timelineAddPeople),
      ),
      findsOneWidget,
    );
  });

  // The Dashboard header shows the signed-in user on both the empty and
  // the loaded timeline -- a fresh sign-in sees the empty one first.
  for (final (name, rows) in [
    ('empty', <Celebration>[]),
    ('loaded', [_celeb(1, _person(1))]),
  ]) {
    testWidgets('the header shows the signed-in user on the $name timeline',
        (tester) async {
      await pump(tester, rows);

      final header = find.byKey(const Key('dashboard_me_header'));
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('Sachin')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.text('@sachin · 🎂 12 March · Jaipur'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('each row shows the person\'s birthday under their name',
      (tester) async {
    await pump(tester, [
      _celeb(1, _person(1, birthday: const Birthday(month: 9, day: 1))),
    ]);

    expect(find.text('1 September'), findsOneWidget);
  });

  // 4. No ⋮ menu: stopping is a long-press that asks first, because it
  //    removes the person.
  testWidgets('long-press asks before stopping, then stops', (tester) async {
    final graph = _FakeGraph([
      _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
    ]);
    await tester.pumpWidget(
      _withSession(
        MaterialApp(
          home: RepositoryProvider<PushRepository>.value(
            value: _FakePush(),
            child: TimelineScreen(repository: graph, now: _fixedNow),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_1')), findsNothing);

    await tester.longPress(find.byKey(const Key('celebration_1')));
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.connectionsStopTitleTemplate
          .replaceFirst('%s', 'Person 1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('connections_stop_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('celebration_1')), findsNothing);
  });

  testWidgets('each row shows how soon the birthday is', (tester) async {
    await pump(tester, [
      _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
      _celeb(2, _person(2, birthday: const Birthday(month: 4, day: 18))),
    ]);

    expect(
      find.descendant(
        of: find.byKey(const Key('countdown_1')),
        matching: find.text(AppStrings.personToday),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('countdown_2')),
        matching: find.text('in 3 days'),
      ),
      findsOneWidget,
    );
  });

  // The assertion M4 Phase 1 taught this project to write: unit tests on
  // PushCubit prove enable() works, and prove NOTHING about whether anything
  // ever calls it. BlocProvider is lazy by default and nothing in
  // _TimelineView reads PushCubit, so without `lazy: false` the cubit is
  // never constructed, enable() never runs, no device ever registers, and
  // every other test in this file still passes. This is the test that fails
  // when that happens.
  testWidgets('arriving at the timeline asks for permission and registers',
      (tester) async {
    final push = _FakePush();
    await tester.pumpWidget(
      _withSession(
        MaterialApp(
          home: RepositoryProvider<PushRepository>.value(
            value: push,
            child: TimelineScreen(repository: _FakeGraph([]), now: _fixedNow),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(push.permissionCalls, 1);
    expect(push.registerCalls, 1);
  });

  group('Add people button', () {
    // Exactly one "Add people" button is always on screen: the floating one
    // on a list, the big centred one on the empty Dashboard -- never both.
    // The header icon is always there, list or empty, in the app bar.
    for (final (name, rows) in [
      ('loaded', [_celeb(1, _person(1))]),
      ('empty', <Celebration>[]),
    ]) {
      testWidgets('the header Add people icon is on the $name Dashboard',
          (tester) async {
        await pump(tester, rows);
        final icon = find.byKey(const Key('dashboard_add_people'));
        expect(icon, findsOneWidget);
        expect(
          find.ancestor(of: icon, matching: find.byType(AppBar)),
          findsOneWidget,
        );
      });
    }

    // The labelled entry: a row at the top of a list. The empty Dashboard
    // has no list, and keeps its big centred button instead.
    testWidgets('a list has the labelled Add people row at the top',
        (tester) async {
      await pump(tester, [_celeb(1, _person(1))]);
      final row = find.byKey(const Key('dashboard_add_people_row'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(AppStrings.timelineAddPeopleHint)),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(row).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('celebration_1'))).dy),
      );
      expect(find.byKey(const Key('timeline_import_cta')), findsNothing);
    });

    testWidgets('the empty Dashboard has the centred button, not the row',
        (tester) async {
      await pump(tester, []);
      expect(find.byKey(const Key('timeline_import_cta')), findsOneWidget);
      expect(find.byKey(const Key('dashboard_add_people_row')), findsNothing);
    });

    testWidgets('the row opens the contacts import too', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => RepositoryProvider<PushRepository>.value(
              value: _FakePush(),
              child: TimelineScreen(
                repository: _FakeGraph([_celeb(1, _person(1))]),
                now: _fixedNow,
              ),
            ),
          ),
          GoRoute(
            path: '/import',
            builder: (_, __) => const Text('import screen'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _withSession(MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dashboard_add_people_row')));
      await tester.pumpAndSettle();

      expect(find.text('import screen'), findsOneWidget);
    });

    testWidgets('opens the contacts import', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => RepositoryProvider<PushRepository>.value(
              value: _FakePush(),
              child: TimelineScreen(
                repository: _FakeGraph([_celeb(1, _person(1))]),
                now: _fixedNow,
              ),
            ),
          ),
          GoRoute(
            path: '/import',
            builder: (_, __) => const Text('import screen'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _withSession(MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dashboard_add_people')));
      await tester.pumpAndSettle();

      expect(find.text('import screen'), findsOneWidget);
    });
  });

  group('Invite', () {
    Future<List<String>> pumpWithShare(
      WidgetTester tester,
      List<Celebration> rows,
    ) async {
      final shared = <String>[];
      await tester.pumpWidget(
        _withSession(
          MaterialApp(
            home: RepositoryProvider<PushRepository>.value(
              value: _FakePush(),
              child: TimelineScreen(
                repository: _FakeGraph(rows),
                now: _fixedNow,
                share: (text) async => shared.add(text),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return shared;
    }

    testWidgets('is offered for someone not on the app, not for a member',
        (tester) async {
      await pumpWithShare(tester, [
        _celeb(1, _person(1)),
        _celeb(2, _person(2,
            isClaimed: true, birthday: const Birthday(month: 9, day: 1))),
      ]);

      expect(find.byKey(const Key('invite_1')), findsOneWidget);
      expect(find.byKey(const Key('invite_2')), findsNothing);
    });

    testWidgets('shares a message addressed to them, with the download link',
        (tester) async {
      final shared = await pumpWithShare(tester, [
        _celeb(1, Person(
          id: 1,
          displayName: 'Asha Sharma',
          isClaimed: false,
        )),
      ]);

      await tester.tap(find.byKey(const Key('invite_1')));
      await tester.pump();

      expect(shared, hasLength(1));
      expect(shared.single, startsWith('Hi Asha!'));
      expect(shared.single, contains(AppLinks.download));
    });
  });

  testWidgets('a person who celebrates you back is labelled so',
      (tester) async {
    final graph = _FakeGraph([
      _celeb(1, _person(1, birthday: const Birthday(month: 9, day: 1))),
      _celeb(2, _person(2, birthday: const Birthday(month: 9, day: 2))),
    ])..celebratesMeSet = {1};
    await tester.pumpWidget(
      _withSession(
        MaterialApp(
          home: RepositoryProvider<PushRepository>.value(
            value: _FakePush(),
            child: TimelineScreen(repository: graph, now: _fixedNow),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 September'), findsOneWidget);
    expect(find.text('2 September'), findsOneWidget);
    // On its own line under the date, only for the one who celebrates back.
    expect(find.byKey(const Key('celebrates_you_1')), findsOneWidget);
    expect(find.byKey(const Key('celebrates_you_2')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('celebrates_you_1'))).dy,
      greaterThan(tester.getTopLeft(find.text('1 September')).dy),
    );
  });
}
