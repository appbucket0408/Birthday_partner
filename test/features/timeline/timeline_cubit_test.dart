import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/timeline/timeline_cubit.dart';
import 'package:birthday_app/features/timeline/timeline_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real GraphRepository fake, not a mock: the Cubit is exercised through
/// its real celebrations()/stopCelebrating() calls, following the pattern in
/// test/features/contacts_import/import_cubit_test.dart.
class _FakeGraph implements GraphRepository {
  Set<int> celebratesMeSet = const {};
  final celebratedBack = <int>[];

  @override
  Future<Set<int>> celebratesMe() async => celebratesMeSet;

  @override
  Future<void> celebrateBack(int personId) async =>
      celebratedBack.add(personId);

  _FakeGraph({
    this.celebrationsList = const [],
    this.celebrationsError,
    this.stopCelebratingError,
  });

  List<Celebration> celebrationsList;
  Object? celebrationsError;
  Object? stopCelebratingError;

  int celebrationsCalls = 0;
  int stopCelebratingCalls = 0;

  @override
  Future<List<Celebration>> celebrations() async {
    celebrationsCalls++;
    if (celebrationsError != null) throw celebrationsError!;
    return celebrationsList;
  }

  @override
  Future<void> stopCelebrating(int celebrationId) async {
    stopCelebratingCalls++;
    if (stopCelebratingError != null) throw stopCelebratingError!;
  }
}

Person _person(int id, {Birthday? birthday, bool isClaimed = false}) =>
    Person(id: id, displayName: 'Person $id', isClaimed: isClaimed,
        birthday: birthday);

Celebration _celeb(int id, Person person) =>
    Celebration(id: id, person: person);

/// Fixed at 15 Apr 2026 throughout, per the task-12 brief. Every test below
/// supplies this (or another fixed instant) explicitly -- never the real
/// clock, since a grouping test built against DateTime.now() would pass in
/// April and fail in October.
DateTime _fixedNow() => DateTime(2026, 4, 15);

/// Extracts just the ids in each group, in order, so assertions read as
/// plain data rather than a wall of Celebration/Person object literals.
Map<TimelineGroup?, List<int>> _idsByGroup(TimelineLoaded state) =>
    state.groups.map((k, v) => MapEntry(k, v.map((c) => c.id).toList()));

void main() {
  // 1. Four celebrations with birthdays on Apr 15, Apr 18, May 1 and Sep 1
  //    group into today / thisWeek / thisMonth / later respectively.
  blocTest<TimelineCubit, TimelineState>(
    'four birthdays land in today, thisWeek, thisMonth and later',
    build: () => TimelineCubit(
      _FakeGraph(celebrationsList: [
        _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
        _celeb(2, _person(2, birthday: const Birthday(month: 4, day: 18))),
        _celeb(3, _person(3, birthday: const Birthday(month: 5, day: 1))),
        _celeb(4, _person(4, birthday: const Birthday(month: 9, day: 1))),
      ]),
      now: _fixedNow,
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<TimelineLoading>(),
      isA<TimelineLoaded>().having(_idsByGroup, 'groups by id', {
        TimelineGroup.today: [1],
        TimelineGroup.thisWeek: [2],
        TimelineGroup.thisMonth: [3],
        TimelineGroup.later: [4],
      }),
    ],
  );

  // 2. A celebration whose person has NO birthday is still returned, in its
  //    own bucket -- the parent spec skips these for reminders, but hiding
  //    them here would make them unfixable, and fixing them is what the
  //    edit action is for.
  blocTest<TimelineCubit, TimelineState>(
    'a person with no birthday is still returned, in its own bucket',
    build: () => TimelineCubit(
      _FakeGraph(celebrationsList: [
        _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
        _celeb(2, _person(2)), // no birthday at all
      ]),
      now: _fixedNow,
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<TimelineLoading>(),
      isA<TimelineLoaded>().having(_idsByGroup, 'groups by id', {
        TimelineGroup.today: [1],
        null: [2],
      }),
    ],
  );

  // 3. An empty edge list emits TimelineEmpty, not an empty TimelineLoaded.
  blocTest<TimelineCubit, TimelineState>(
    'an empty edge list emits TimelineEmpty, not an empty TimelineLoaded',
    build: () => TimelineCubit(_FakeGraph(), now: _fixedNow),
    act: (c) => c.load(),
    expect: () => [isA<TimelineLoading>(), isA<TimelineEmpty>()],
  );

  // 4. Within a group, rows are ordered by next occurrence ascending. Three
  //    people all land in thisMonth (8-31 days out from 15 Apr): Apr 30 (15
  //    days), Apr 23 (8 days) and May 10 (25 days) -- built out of order,
  //    expected back sorted.
  blocTest<TimelineCubit, TimelineState>(
    'rows within a group are ordered by next occurrence ascending',
    build: () => TimelineCubit(
      _FakeGraph(celebrationsList: [
        _celeb(30, _person(30, birthday: const Birthday(month: 5, day: 10))),
        _celeb(10, _person(10, birthday: const Birthday(month: 4, day: 23))),
        _celeb(20, _person(20, birthday: const Birthday(month: 4, day: 30))),
      ]),
      now: _fixedNow,
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<TimelineLoading>(),
      isA<TimelineLoaded>().having(
        (s) => s.groups[TimelineGroup.thisMonth]?.map((c) => c.id).toList(),
        'thisMonth ids in order',
        [10, 20, 30],
      ),
    ],
  );

  // Not one of the brief's seven: a failed stopCelebrating must
  // surface the generic message rather than silently dropping the row or
  // throwing out of the Cubit.
  test('a failed stopCelebrating surfaces the generic message and keeps '
      'the row', () async {
    final fake = _FakeGraph(
      celebrationsList: [
        _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
      ],
      stopCelebratingError: const ServerFailure('boom'),
    );
    final cubit = TimelineCubit(fake, now: _fixedNow);
    await cubit.load();

    await cubit.stopCelebrating(1);

    final state = cubit.state as TimelineLoaded;
    expect(state.error, AppStrings.somethingWentWrong);
    expect(state.groups[TimelineGroup.today]!.single.id, 1);
  });

  // 7. stopCelebrating removes the row from state without a full reload.
  test('stopCelebrating removes the row from state without a full reload',
      () async {
    final fake = _FakeGraph(celebrationsList: [
      _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
      _celeb(2, _person(2, birthday: const Birthday(month: 4, day: 18))),
    ]);
    final cubit = TimelineCubit(fake, now: _fixedNow);
    await cubit.load();

    await cubit.stopCelebrating(1);

    final state = cubit.state as TimelineLoaded;
    expect(_idsByGroup(state), {
      TimelineGroup.thisWeek: [2],
    });
    // celebrations() was called exactly once -- by load(). Removing a row
    // is a local list edit, not a re-fetch.
    expect(fake.celebrationsCalls, 1);
  });

  // B4: a failure of celebrations() must never reach the screen as
  // Object.toString()'s default "Instance of 'ServerFailure'" -- this is the
  // home screen, so any failure here puts that Dart type dump in front of
  // every user, not just one who tripped a row action. AppFailure carries a
  // human [message]; the cubit must read it rather than stringify the
  // exception with '$e'.
  test('load surfaces a ServerFailure\'s own message, never "Instance of"',
      () async {
    final fake = _FakeGraph(
      celebrationsError: const ServerFailure('boom from the server'),
    );
    final cubit = TimelineCubit(fake, now: _fixedNow);

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<TimelineError>());
    final message = (state as TimelineError).message;
    expect(message, 'boom from the server');
    expect(message, isNot(contains('Instance of')));
  });

  // The flip side: something that is NOT a modelled AppFailure (a plugin
  // exception, a null-check, whatever) must fall back to the generic
  // message, not leak an arbitrary exception's toString to the user.
  test('load falls back to the generic message for a non-AppFailure error',
      () async {
    final fake = _FakeGraph(celebrationsError: StateError('unexpected'));
    final cubit = TimelineCubit(fake, now: _fixedNow);

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<TimelineError>());
    expect((state as TimelineError).message, AppStrings.somethingWentWrong);
  });

  // Re-entrancy: the cubit, not the widget, is the source of truth for what
  // is in flight -- mirrors PhoneCubit.submitCode, ProfileSetupCubit.submit
  // and ImportCubit.commit. A fast double-tap on one row's "Stop
  // celebrating" must not fire two DELETEs.
  test('a second stopCelebrating call for the same row while one is in '
      'flight is ignored', () async {
    final fake = _FakeGraph(celebrationsList: [
      _celeb(1, _person(1, birthday: const Birthday(month: 4, day: 15))),
    ]);
    final cubit = TimelineCubit(fake, now: _fixedNow);
    await cubit.load();

    final first = cubit.stopCelebrating(1);
    final second = cubit.stopCelebrating(1);
    await Future.wait([first, second]);

    expect(fake.stopCelebratingCalls, 1);
  });

  // Who celebrates the viewer rides along on the loaded state, for the
  // "Celebrates you" label -- and a failure to learn it must not fail the
  // timeline, it is only a label.
  test('load carries who celebrates the viewer', () async {
    final graph = _FakeGraph(celebrationsList: [_celeb(1, _person(1))])
      ..celebratesMeSet = {1};
    final cubit = TimelineCubit(graph, now: _fixedNow);
    await cubit.load();
    expect((cubit.state as TimelineLoaded).celebratesMe, {1});
  });
}
