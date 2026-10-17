import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/calendar/calendar_cubit.dart';
import 'package:birthday_app/features/calendar/calendar_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real fake, not a mock -- same pattern as the timeline and profile
/// cubit tests.
class _FakeGraph implements GraphRepository {
  _FakeGraph([this.list = const [], this.error]);

  final List<Celebration> list;
  final Object? error;
  int calls = 0;

  @override
  Future<List<Celebration>> celebrations() async {
    calls++;
    if (error != null) throw error!;
    return list;
  }

  @override
  Future<void> stopCelebrating(int celebrationId) async =>
      throw UnimplementedError('not used by CalendarCubit');
}

Celebration _celeb(int id, String name, {Birthday? birthday}) => Celebration(
      id: id,
      person: Person(
        id: id,
        displayName: name,
        isClaimed: false,
        birthday: birthday,
      ),
    );

/// 15 Dec 2026, mid-afternoon: the time of day must not leak into the
/// selected date.
DateTime _now() => DateTime(2026, 12, 15, 15, 30);

Future<CalendarLoaded> _loaded(List<Celebration> list) async {
  final cubit = CalendarCubit(_FakeGraph(list), now: _now);
  await cubit.load();
  return cubit.state as CalendarLoaded;
}

void main() {
  blocTest<CalendarCubit, CalendarState>(
    'load() opens on the current month with today selected',
    build: () => CalendarCubit(_FakeGraph(), now: _now),
    act: (c) => c.load(),
    expect: () => [
      isA<CalendarLoading>(),
      isA<CalendarLoaded>()
          .having((s) => s.month, 'month', DateTime(2026, 12))
          .having((s) => s.selected, 'selected', DateTime(2026, 12, 15)),
    ],
  );

  test('a failed load surfaces the failure message', () async {
    final cubit = CalendarCubit(
      _FakeGraph(const [], const ServerFailure('boom')),
      now: _now,
    );
    await cubit.load();
    expect((cubit.state as CalendarError).message, 'boom');
  });

  test('an unexpected error falls back to somethingWentWrong', () async {
    final cubit = CalendarCubit(_FakeGraph(const [], StateError('x')), now: _now);
    await cubit.load();
    expect(
      (cubit.state as CalendarError).message,
      AppStrings.somethingWentWrong,
    );
  });

  test('changeMonth crosses year boundaries in both directions', () async {
    final cubit = CalendarCubit(_FakeGraph(), now: _now);
    await cubit.load();

    cubit.changeMonth(1);
    expect((cubit.state as CalendarLoaded).month, DateTime(2027, 1));

    cubit
      ..changeMonth(-1)
      ..changeMonth(-1);
    expect((cubit.state as CalendarLoaded).month, DateTime(2026, 11));
  });

  test('paging months leaves the selected day where it was', () async {
    final cubit = CalendarCubit(_FakeGraph(), now: _now);
    await cubit.load();

    cubit.changeMonth(2);
    expect((cubit.state as CalendarLoaded).selected, DateTime(2026, 12, 15));
  });

  test('birthdayDays marks only the days in the month on screen', () async {
    final state = await _loaded([
      _celeb(1, 'A', birthday: const Birthday(month: 12, day: 3)),
      _celeb(2, 'B', birthday: const Birthday(month: 12, day: 25, year: 1990)),
      _celeb(3, 'C', birthday: const Birthday(month: 1, day: 3)),
      _celeb(4, 'No birthday'),
    ]);

    expect(state.birthdayDays, {3, 25});
  });

  test('onSelected lists everyone born on that day, sorted by name', () async {
    final cubit = CalendarCubit(
      _FakeGraph([
        _celeb(1, 'Rahul', birthday: const Birthday(month: 12, day: 21)),
        _celeb(2, 'Meera', birthday: const Birthday(month: 12, day: 21)),
        _celeb(3, 'Karan', birthday: const Birthday(month: 12, day: 22)),
      ]),
      now: _now,
    );
    await cubit.load();
    cubit.select(DateTime(2026, 12, 21));

    final names =
        (cubit.state as CalendarLoaded).onSelected.map((c) => c.person.displayName);
    expect(names, ['Meera', 'Rahul']);
  });

  // The same Feb 29 rule as the timeline and the reminder fan-out: in a
  // non-leap year the birthday is on Feb 28, never dropped.
  test('a Feb 29 birthday lands on Feb 28 in a non-leap year', () async {
    final cubit = CalendarCubit(
      _FakeGraph([
        _celeb(1, 'Leap', birthday: const Birthday(month: 2, day: 29)),
      ]),
      now: _now,
    );
    await cubit.load();
    cubit
      ..changeMonth(2) // February 2027, not a leap year
      ..select(DateTime(2027, 2, 28));

    final state = cubit.state as CalendarLoaded;
    expect(state.birthdayDays, {28});
    expect(state.onSelected.map((c) => c.person.displayName), ['Leap']);
  });

  test('a Feb 29 birthday stays on Feb 29 in a leap year', () async {
    final cubit = CalendarCubit(
      _FakeGraph([
        _celeb(1, 'Leap', birthday: const Birthday(month: 2, day: 29)),
      ]),
      now: () => DateTime(2028, 2, 1),
    );
    await cubit.load();

    expect((cubit.state as CalendarLoaded).birthdayDays, {29});
  });
}
