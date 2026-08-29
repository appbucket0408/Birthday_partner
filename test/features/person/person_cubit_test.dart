import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/person/person_cubit.dart';
import 'package:birthday_app/features/person/person_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/person_repository.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fakes, not mocks -- same pattern as
/// test/features/timeline/timeline_cubit_test.dart's `_FakeGraph`.
class _FakePerson implements PersonRepository {
  _FakePerson({this.personToReturn, this.countError});

  Person? personToReturn;
  Object? countError;
  int countToReturn = 0;

  int personCalls = 0;
  int celebratorCountCalls = 0;

  @override
  Future<Person> person(int personId) async {
    personCalls++;
    return personToReturn!;
  }

  @override
  Future<int> celebratorCount(int personId) async {
    celebratorCountCalls++;
    if (countError != null) throw countError!;
    return countToReturn;
  }
}

class _FakeWish implements WishRepository {
  _FakeWish({this.wishesToReturn = const [], this.postError});

  List<Wish> wishesToReturn;
  Object? postError;

  int postCalls = 0;
  int wishesForCalls = 0;
  int? lastOccasionYear;

  @override
  Future<List<Wish>> wishesFor(int personId) async {
    wishesForCalls++;
    return wishesToReturn;
  }

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  }) async {
    postCalls++;
    lastOccasionYear = occasionYear;
    if (postError != null) throw postError!;
  }
}

/// [celebrationsList] is the SIGNED-IN VIEWER'S OWN celebration edges --
/// `GraphRepository.celebrations()` filters server-side on
/// `celebrator_profile_id = auth.uid()` (see
/// `lib/repositories/graph_repository_impl.dart`) -- so membership of this
/// list, not the loaded [Person] itself, is what `PersonCubit.load` reads
/// to decide `PersonLoaded.viewerCelebrates`.
class _FakeGraph implements GraphRepository {
  _FakeGraph({this.celebrationsList = const []});

  List<Celebration> celebrationsList;

  int celebrationsCalls = 0;

  @override
  Future<List<Celebration>> celebrations() async {
    celebrationsCalls++;
    return celebrationsList;
  }

  @override
  Future<void> updateBirthday(int personId, Birthday birthday) async =>
      throw UnimplementedError('not used by PersonCubit');

  @override
  Future<void> updateNickname(int celebrationId, String? nickname) async =>
      throw UnimplementedError('not used by PersonCubit');

  @override
  Future<void> stopCelebrating(int celebrationId) async =>
      throw UnimplementedError('not used by PersonCubit');
}

Person _person(int id, {Birthday? birthday}) =>
    Person(id: id, displayName: 'Person $id', isClaimed: false,
        birthday: birthday);

Celebration _celeb(int personId) =>
    Celebration(id: personId, person: _person(personId));

Wish _wish(int id, {int occasionYear = 2025}) => Wish(
      id: id,
      authorProfileId: 'author-$id',
      subjectPersonId: 1,
      body: 'Happy birthday!',
      occasionYear: occasionYear,
      createdAt: DateTime(2026, 1, 1),
    );

/// Fixed at 5 Jan 2026 -- the exact scenario the brief and Birthday.occasionYear
/// were both written against: a December birthday, wished just after New
/// Year's, is a BELATED wish for last December, not an early one for next.
DateTime _fixedNow() => DateTime(2026, 1, 5);

void main() {
  // 1. load() emits PersonLoading then PersonLoaded with the person, the
  //    count and the wishes.
  blocTest<PersonCubit, PersonState>(
    'load() emits PersonLoading then PersonLoaded with person, count, wishes',
    build: () => PersonCubit(
      _FakePerson(
        personToReturn:
            _person(1, birthday: const Birthday(month: 12, day: 20)),
      )..countToReturn = 3,
      _FakeWish(wishesToReturn: [_wish(1)]),
      _FakeGraph(celebrationsList: [_celeb(1)]),
      now: _fixedNow,
    ),
    act: (c) => c.load(1),
    expect: () => [
      isA<PersonLoading>(),
      isA<PersonLoaded>()
          .having((s) => s.person.id, 'person.id', 1)
          .having((s) => s.celebratorCount, 'celebratorCount', 3)
          .having((s) => s.wishes.map((w) => w.id).toList(), 'wish ids', [1]),
    ],
  );

  // 2. A person with no birthday still loads -- the page must render,
  //    because the timeline's inline edit is how a missing birthday gets
  //    fixed.
  blocTest<PersonCubit, PersonState>(
    'a person with no birthday still loads',
    build: () => PersonCubit(
      _FakePerson(personToReturn: _person(1))..countToReturn = 0,
      _FakeWish(),
      _FakeGraph(),
      now: _fixedNow,
    ),
    act: (c) => c.load(1),
    expect: () => [
      isA<PersonLoading>(),
      isA<PersonLoaded>().having(
        (s) => s.person.birthday,
        'birthday',
        isNull,
      ),
    ],
  );

  // 3. A failing celebratorCount surfaces as PersonError with a human
  //    message, never a Dart type dump. The second half is the assertion
  //    that actually discriminates: AppFailure.toString() would satisfy the
  //    first half on its own, so a non-AppFailure must ALSO fall back to
  //    AppStrings.somethingWentWrong.
  test(
      'a failing celebratorCount surfaces as PersonError with the '
      "ServerFailure's own message, never 'Instance of'", () async {
    final fake = _FakePerson(
      personToReturn: _person(1),
      countError: const ServerFailure('boom from the server'),
    );
    final cubit = PersonCubit(fake, _FakeWish(), _FakeGraph(), now: _fixedNow);

    await cubit.load(1);

    final state = cubit.state;
    expect(state, isA<PersonError>());
    final message = (state as PersonError).message;
    expect(message, 'boom from the server');
    expect(message, isNot(contains('Instance of')));
  });

  test(
      'a non-AppFailure error from celebratorCount falls back to the '
      'generic message', () async {
    final fake = _FakePerson(
      personToReturn: _person(1),
      countError: StateError('unexpected'),
    );
    final cubit = PersonCubit(fake, _FakeWish(), _FakeGraph(), now: _fixedNow);

    await cubit.load(1);

    final state = cubit.state;
    expect(state, isA<PersonError>());
    expect((state as PersonError).message, AppStrings.somethingWentWrong);
  });

  // 3b (fix round 1): viewerCelebrates is true when the viewer's OWN
  // celebration list (GraphRepository.celebrations()) contains this person.
  test(
      'viewerCelebrates is true when the celebration list contains this '
      'person', () async {
    final cubit = PersonCubit(
      _FakePerson(personToReturn: _person(1)),
      _FakeWish(),
      _FakeGraph(celebrationsList: [_celeb(1)]),
      now: _fixedNow,
    );

    await cubit.load(1);

    final state = cubit.state as PersonLoaded;
    expect(state.viewerCelebrates, isTrue);
  });

  // 3c (fix round 1): the flip side -- a person visible only via one of
  // can_see_person's OTHER two branches (own profile, or they celebrate the
  // viewer) does not appear in the viewer's own celebrations() list, so
  // viewerCelebrates must be false.
  test(
      'viewerCelebrates is false when the celebration list does NOT contain '
      'this person', () async {
    final cubit = PersonCubit(
      _FakePerson(personToReturn: _person(1)),
      _FakeWish(),
      _FakeGraph(celebrationsList: [_celeb(99)]), // some other person entirely
      now: _fixedNow,
    );

    await cubit.load(1);

    final state = cubit.state as PersonLoaded;
    expect(state.viewerCelebrates, isFalse);
  });

  // 4. postWish() derives occasionYear from the person's birthday rather
  //    than taking it as an argument. This is the whole point of the
  //    design: the user is never asked which year. A Dec 20 birthday
  //    wished on 5 Jan 2026 is a BELATED wish for Dec 2025, not an early
  //    one for Dec 2026.
  test(
      'postWish() derives occasionYear from Birthday.occasionYear, never '
      'the current year', () async {
    final wish = _FakeWish();
    final person = _FakePerson(
      personToReturn:
          _person(1, birthday: const Birthday(month: 12, day: 20)),
    );
    final cubit = PersonCubit(
      person,
      wish,
      _FakeGraph(celebrationsList: [_celeb(1)]),
      now: _fixedNow,
    );
    await cubit.load(1);

    await cubit.postWish('Happy belated birthday!');

    const expectedYear = 2025;
    expect(
      const Birthday(month: 12, day: 20).occasionYear(_fixedNow()),
      expectedYear,
      reason: 'sanity check on the fixture itself',
    );
    expect(wish.lastOccasionYear, expectedYear);
  });

  // 5. postWish() reloads the wall on success, so the new wish appears.
  test('postWish() reloads the wall on success', () async {
    final wish = _FakeWish(wishesToReturn: [_wish(1)]);
    final person = _FakePerson(
      personToReturn:
          _person(1, birthday: const Birthday(month: 12, day: 20)),
    );
    final cubit = PersonCubit(
      person,
      wish,
      _FakeGraph(celebrationsList: [_celeb(1)]),
      now: _fixedNow,
    );
    await cubit.load(1);

    // The second load (post-write) returns a longer wall -- the freshly
    // posted wish plus the one already there.
    wish.wishesToReturn = [_wish(2), _wish(1)];
    await cubit.postWish('Happy belated birthday!');

    final state = cubit.state as PersonLoaded;
    expect(state.wishes.map((w) => w.id).toList(), [2, 1]);
    expect(wish.wishesForCalls, 2); // once from load(), once from postWish()
  });

  // 6. A second postWish() while the first is in flight is ignored --
  //    the ReentrancyGuard mixin doing its job, not a hand-rolled flag.
  test('a second postWish() while the first is in flight is ignored',
      () async {
    final wish = _FakeWish();
    final person = _FakePerson(
      personToReturn:
          _person(1, birthday: const Birthday(month: 12, day: 20)),
    );
    final cubit = PersonCubit(
      person,
      wish,
      _FakeGraph(celebrationsList: [_celeb(1)]),
      now: _fixedNow,
    );
    await cubit.load(1);

    final first = cubit.postWish('First');
    final second = cubit.postWish('Second');
    await Future.wait([first, second]);

    expect(wish.postCalls, 1);
  });

  // 7 (fix round 1, ruling item 2). A failing postWish must NOT discard the
  // already-rendered wall by replacing the state with PersonError -- it
  // stays PersonLoaded, with the wishes still present and a transient
  // postError set, the same shape TimelineLoaded.error uses for row-action
  // failures. The message must be human-readable, never a Dart type dump.
  test(
      'a failing postWish() leaves PersonLoaded with the wishes still '
      "present and postError set to the failure's own message", () async {
    final existingWish = _wish(1);
    final wish = _FakeWish(
      wishesToReturn: [existingWish],
      postError: const ServerFailure('no celebration edge to this person'),
    );
    final person = _FakePerson(
      personToReturn:
          _person(1, birthday: const Birthday(month: 12, day: 20)),
    );
    final cubit = PersonCubit(
      person,
      wish,
      _FakeGraph(celebrationsList: [_celeb(1)]),
      now: _fixedNow,
    );
    await cubit.load(1);

    await cubit.postWish('Uninvited, mid-compose race');

    final state = cubit.state;
    expect(state, isA<PersonLoaded>());
    final loaded = state as PersonLoaded;
    expect(loaded.wishes.map((w) => w.id).toList(), [1]);
    expect(loaded.postError, 'no celebration edge to this person');
    expect(loaded.postError, isNot(contains('Instance of')));
  });
}
