import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/calendar/calendar_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercised through a real CalendarCubit over a fake repository, the same
/// way timeline_screen_test.dart drives TimelineScreen.
class _FakeGraph implements GraphRepository {
  Set<int> celebratesMeSet = const {};
  final celebratedBack = <int>[];

  @override
  Future<Set<int>> celebratesMe() async => celebratesMeSet;

  @override
  Future<void> celebrateBack(int personId) async =>
      celebratedBack.add(personId);

  _FakeGraph(this.list);

  final List<Celebration> list;

  @override
  Future<List<Celebration>> celebrations() async => list;

  @override
  Future<void> stopCelebrating(int celebrationId) async {}
}

Celebration _celeb(int id, String name, Birthday birthday) => Celebration(
      id: id,
      person: Person(
        id: id,
        displayName: name,
        isClaimed: false,
        birthday: birthday,
      ),
    );

Future<void> _pump(WidgetTester tester, List<Celebration> list) async {
  // A phone-sized screen. The grid's cells are square, so the default
  // 800x600 test surface makes them tall enough to push the day list below
  // the fold, which no phone does.
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepositoryProvider<GraphRepository>.value(
      value: _FakeGraph(list),
      child: MaterialApp(
        home: CalendarScreen(now: () => DateTime(2026, 10, 17)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final people = [
    _celeb(1, 'Rahul', const Birthday(month: 10, day: 21, year: 1996)),
    _celeb(2, 'Meera', const Birthday(month: 10, day: 21)),
    _celeb(3, 'Karan', const Birthday(month: 11, day: 2)),
  ];

  testWidgets('opens on the current month with today selected',
      (tester) async {
    await _pump(tester, people);

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Saturday, 17 October'), findsOneWidget);
    expect(find.text(AppStrings.calendarNoBirthdays), findsOneWidget);
  });

  testWidgets('days with a birthday carry a dot, others do not',
      (tester) async {
    await _pump(tester, people);

    expect(find.byKey(const Key('calendar_dot_21')), findsOneWidget);
    expect(find.byKey(const Key('calendar_dot_17')), findsNothing);
    // Karan's November birthday is not dotted in October.
    expect(find.byKey(const Key('calendar_dot_2')), findsNothing);
  });

  testWidgets('tapping a day lists the people born on it', (tester) async {
    await _pump(tester, people);

    await tester.tap(find.byKey(const Key('calendar_day_21')));
    await tester.pumpAndSettle();

    expect(find.text('Wednesday, 21 October'), findsOneWidget);
    expect(find.byKey(const Key('calendar_person_1')), findsOneWidget);
    expect(find.byKey(const Key('calendar_person_2')), findsOneWidget);
    expect(find.text('turns 30'), findsOneWidget);
    expect(find.text(AppStrings.calendarYearUnknown), findsOneWidget);
  });

  testWidgets('the next-month arrow shows the next month\'s birthdays',
      (tester) async {
    await _pump(tester, people);

    await tester.tap(find.byKey(const Key('calendar_next_month')));
    await tester.pumpAndSettle();

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.byKey(const Key('calendar_dot_2')), findsOneWidget);
    expect(find.byKey(const Key('calendar_dot_21')), findsNothing);
  });
}
