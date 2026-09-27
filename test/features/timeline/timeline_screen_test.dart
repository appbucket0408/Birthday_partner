import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/timeline/timeline_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real GraphRepository fake, not a mock -- the screen is exercised
/// through a real TimelineCubit, following the pattern in
/// test/features/contacts_import/import_pick_screen_test.dart.
class _FakeGraph implements GraphRepository {
  _FakeGraph(this.celebrationsList);

  final List<Celebration> celebrationsList;

  @override
  Future<List<Celebration>> celebrations() async => celebrationsList;

  @override
  Future<void> updateBirthday(int personId, Birthday birthday) async {}

  @override
  Future<void> updateNickname(int celebrationId, String? nickname) async {}

  @override
  Future<void> stopCelebrating(int celebrationId) async {}
}

Person _person(int id, {Birthday? birthday}) =>
    Person(id: id, displayName: 'Person $id', isClaimed: false,
        birthday: birthday);

Celebration _celeb(int id, Person person) => Celebration(id: id, person: person);

class _FakePush implements PushRepository {
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

Future<void> pump(WidgetTester tester, List<Celebration> celebrations) async {
  // TimelineScreen creates a PushCubit eagerly (lazy: false), so this
  // provider is required now -- arriving at the timeline is what asks for
  // notification permission.
  await tester.pumpWidget(
    MaterialApp(
      home: RepositoryProvider<PushRepository>.value(
        value: _FakePush(),
        child: TimelineScreen(
          repository: _FakeGraph(celebrations),
          now: _fixedNow,
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

    expect(find.text(AppStrings.timelineToday), findsOneWidget);
    expect(find.text(AppStrings.timelineLater), findsOneWidget);
    expect(find.text(AppStrings.timelineThisWeek), findsNothing);
    expect(find.text(AppStrings.timelineThisMonth), findsNothing);
    expect(find.text(AppStrings.timelineNoBirthdayYet), findsNothing);
  });

  // 2. A person with no birthday shows timelineNoBirthdayYet.
  testWidgets('a person with no birthday shows timelineNoBirthdayYet', (
    tester,
  ) async {
    await pump(tester, [_celeb(1, _person(1))]);

    expect(find.text(AppStrings.timelineNoBirthdayYet), findsOneWidget);
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
        matching: find.text(AppStrings.timelineImportCta),
      ),
      findsOneWidget,
    );
  });

  // B1: Settings is otherwise unreachable -- nothing in lib/ navigates to
  // '/settings' except this button. It must exist on every TimelineState,
  // not just the loaded one, so it is asserted here against the empty
  // state, which every fresh sign-in hits first.
  testWidgets('an AppBar settings button is always present', (tester) async {
    await pump(tester, []);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('settings_button')),
    );
    expect(button.onPressed, isNotNull);
    expect(button.tooltip, AppStrings.settingsTitle);
  });

  // 4. The overflow menu offers exactly the three actions.
  testWidgets('the overflow menu offers exactly the three actions', (
    tester,
  ) async {
    await pump(tester, [
      _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
    ]);

    await tester.tap(find.byKey(const Key('menu_1')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.timelineEditBirthday), findsOneWidget);
    expect(find.text(AppStrings.timelineEditNickname), findsOneWidget);
    expect(find.text(AppStrings.timelineStopCelebrating), findsOneWidget);
    expect(find.byType(PopupMenuItem<VoidCallback>), findsNWidgets(3));
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
      MaterialApp(
        home: RepositoryProvider<PushRepository>.value(
          value: push,
          child: TimelineScreen(repository: _FakeGraph([]), now: _fixedNow),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(push.permissionCalls, 1);
    expect(push.registerCalls, 1);
  });
}
