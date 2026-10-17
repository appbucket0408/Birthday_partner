import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/profile/profile_cubit.dart';
import 'package:birthday_app/features/profile/profile_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/birthday_stat.dart';
import 'package:birthday_app/models/celebration.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/profile_repository.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fakes, not mocks -- same pattern as
/// test/features/person/person_cubit_test.dart's `_FakeGraph`.
class _FakeProfileRepo implements ProfileRepository {
  _FakeProfileRepo({
    this.statsList = const [],
    this.celebratesList = const [],
    this.statsError,
    this.celebratesError,
  });

  List<BirthdayStat> statsList;
  List<Person> celebratesList;
  Object? statsError;
  Object? celebratesError;

  int statsCalls = 0;
  int celebratesCalls = 0;

  @override
  Future<List<BirthdayStat>> stats() async {
    statsCalls++;
    if (statsError != null) throw statsError!;
    return statsList;
  }

  @override
  Future<List<Person>> celebrates() async {
    celebratesCalls++;
    if (celebratesError != null) throw celebratesError!;
    return celebratesList;
  }
}

class _FakeGraph implements GraphRepository {
  _FakeGraph({this.celebrationsList = const [], this.celebrationsError});

  List<Celebration> celebrationsList;
  Object? celebrationsError;

  int celebrationsCalls = 0;

  @override
  Future<List<Celebration>> celebrations() async {
    celebrationsCalls++;
    if (celebrationsError != null) throw celebrationsError!;
    return celebrationsList;
  }

  @override
  Future<void> updateBirthday(int personId, Birthday birthday) async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> updateNickname(int celebrationId, String? nickname) async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> stopCelebrating(int celebrationId) async =>
      throw UnimplementedError('not used by ProfileCubit');
}

class _FakeAuth implements AuthRepository {
  _FakeAuth({this.profileToReturn, this.loadProfileError});

  Profile? profileToReturn;
  Object? loadProfileError;

  int loadProfileCalls = 0;

  @override
  String? get currentUserId => 'user-1';

  @override
  Future<Profile> loadProfile() async {
    loadProfileCalls++;
    if (loadProfileError != null) throw loadProfileError!;
    return profileToReturn!;
  }

  @override
  Future<void> sendOtp(String phoneE164) async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<int> claimProfile() async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> signOut() async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> deleteAccount() async =>
      throw UnimplementedError('not used by ProfileCubit');
}

Person _person(int id) =>
    Person(id: id, displayName: 'Person $id', isClaimed: false);

Celebration _celeb(int personId) =>
    Celebration(id: personId, person: _person(personId));

Profile _profile() => const Profile(
      id: 'user-1',
      handle: 'u1',
      displayName: 'Me',
      remindersEnabled: true,
      birthday: Birthday(month: 6, day: 1),
    );

class _FakeWishes implements WishRepository {
  _FakeWishes({this.wall = const [], this.error});

  final List<Wish> wall;
  final Object? error;

  @override
  Future<List<Wish>> wishesToMe() async {
    if (error != null) throw error!;
    return wall;
  }

  @override
  Future<List<Wish>> wishesFor(int personId) async =>
      throw UnimplementedError('not used by ProfileCubit');

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  }) async =>
      throw UnimplementedError('not used by ProfileCubit');
}

Wish _wish(int id) => Wish(
      id: id,
      authorProfileId: 'friend-$id',
      subjectPersonId: 99,
      body: 'Happy birthday $id',
      occasionYear: 2026,
      createdAt: DateTime(2026, 6, 1),
      authorName: 'Friend $id',
    );

void main() {
  // 1. load() emits ProfileLoading then ProfileLoaded with all three header
  //    counts and the stats list.
  blocTest<ProfileCubit, ProfileState>(
    'load() emits ProfileLoading then ProfileLoaded with all three header '
    'counts and the stats list',
    build: () => ProfileCubit(
      _FakeProfileRepo(
        statsList: [
          const BirthdayStat(
            year: 2026,
            wishesSent: 2,
            wishesReceived: 5,
            birthdaysCelebrated: 2,
          ),
        ],
        celebratesList: [_person(10), _person(11)],
      ),
      _FakeGraph(celebrationsList: [_celeb(1), _celeb(2), _celeb(3)]),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(),
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<ProfileLoading>(),
      isA<ProfileLoaded>()
          .having((s) => s.celebratingCount, 'celebratingCount', 3)
          .having((s) => s.celebratesCount, 'celebratesCount', 2)
          .having((s) => s.wishesReceived, 'wishesReceived', 5)
          .having((s) => s.wishesSent, 'wishesSent', 2)
          .having((s) => s.stats.map((s) => s.year).toList(), 'stat years',
              [2026]),
    ],
  );

  // 2. Both header wish counts are all-time totals, summed across every
  //    year's stat row -- not just the current or newest year.
  blocTest<ProfileCubit, ProfileState>(
    'wishesReceived and wishesSent are summed across every year',
    build: () => ProfileCubit(
      _FakeProfileRepo(
        statsList: [
          const BirthdayStat(
            year: 2026,
            wishesSent: 2,
            wishesReceived: 5,
            birthdaysCelebrated: 2,
          ),
          const BirthdayStat(
            year: 2025,
            wishesSent: 9,
            wishesReceived: 40,
            birthdaysCelebrated: 9,
          ),
        ],
      ),
      _FakeGraph(),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(),
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<ProfileLoading>(),
      isA<ProfileLoaded>()
          .having((s) => s.wishesReceived, 'wishesReceived', 45)
          .having((s) => s.wishesSent, 'wishesSent', 11),
    ],
  );

  // The wall carries the wishes sent to the user, in repository order.
  blocTest<ProfileCubit, ProfileState>(
    'load() carries the wishes sent to the user as the wall',
    build: () => ProfileCubit(
      _FakeProfileRepo(),
      _FakeGraph(),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(wall: [_wish(2), _wish(1)]),
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<ProfileLoading>(),
      isA<ProfileLoaded>()
          .having((s) => s.wall.map((w) => w.id).toList(), 'wall ids', [2, 1]),
    ],
  );

  // The wall is secondary: if it fails to load, the profile still loads
  // with an empty wall instead of turning into an error screen.
  blocTest<ProfileCubit, ProfileState>(
    'a failing wall still loads the profile, with an empty wall',
    build: () => ProfileCubit(
      _FakeProfileRepo(),
      _FakeGraph(celebrationsList: [_celeb(1)]),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(error: const ServerFailure('wall broke')),
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<ProfileLoading>(),
      isA<ProfileLoaded>()
          .having((s) => s.celebratingCount, 'celebratingCount', 1)
          .having((s) => s.wall, 'wall', isEmpty),
    ],
  );

  // 3. An empty stats list still loads, with all counts zero and an empty
  //    wall. A brand-new account must not see an error screen.
  blocTest<ProfileCubit, ProfileState>(
    'an empty stats list still loads, with all counts zero and an empty '
    'wall',
    build: () => ProfileCubit(
      _FakeProfileRepo(),
      _FakeGraph(),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(),
    ),
    act: (c) => c.load(),
    expect: () => [
      isA<ProfileLoading>(),
      isA<ProfileLoaded>()
          .having((s) => s.celebratingCount, 'celebratingCount', 0)
          .having((s) => s.celebratesCount, 'celebratesCount', 0)
          .having((s) => s.wishesReceived, 'wishesReceived', 0)
          .having((s) => s.wishesSent, 'wishesSent', 0)
          .having((s) => s.stats, 'stats', isEmpty),
    ],
  );

  // 4. A failure in any one of the three repositories surfaces as
  //    ProfileError with a human message. The discriminating assertion is
  //    that a non-AppFailure ALSO falls back to AppStrings.somethingWentWrong
  //    -- an AppFailure.toString() alone would satisfy a weaker version of
  //    this test.
  test(
      'a failure in stats() surfaces as ProfileError with the '
      "ServerFailure's own message, never 'Instance of'", () async {
    final cubit = ProfileCubit(
      _FakeProfileRepo(
        statsError: const ServerFailure('boom from the server'),
      ),
      _FakeGraph(),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<ProfileError>());
    final message = (state as ProfileError).message;
    expect(message, 'boom from the server');
    expect(message, isNot(contains('Instance of')));
  });

  test(
      'a non-AppFailure error from celebrates() falls back to '
      'AppStrings.somethingWentWrong', () async {
    final cubit = ProfileCubit(
      _FakeProfileRepo(celebratesError: StateError('unexpected')),
      _FakeGraph(),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<ProfileError>());
    expect((state as ProfileError).message, AppStrings.somethingWentWrong);
  });

  test(
      'a non-AppFailure error from celebrations() falls back to '
      'AppStrings.somethingWentWrong', () async {
    final cubit = ProfileCubit(
      _FakeProfileRepo(),
      _FakeGraph(celebrationsError: StateError('unexpected')),
      _FakeAuth(profileToReturn: _profile()),
      _FakeWishes(),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<ProfileError>());
    expect((state as ProfileError).message, AppStrings.somethingWentWrong);
  });

  test(
      'a non-AppFailure error from loadProfile() falls back to '
      'AppStrings.somethingWentWrong', () async {
    final cubit = ProfileCubit(
      _FakeProfileRepo(),
      _FakeGraph(),
      _FakeAuth(loadProfileError: StateError('unexpected')),
      _FakeWishes(),
    );

    await cubit.load();

    final state = cubit.state;
    expect(state, isA<ProfileError>());
    expect((state as ProfileError).message, AppStrings.somethingWentWrong);
  });

  // 5. A second load() while the first is in flight is ignored
  //    (ReentrancyGuard).
  test('a second load() while the first is in flight is ignored', () async {
    final auth = _FakeAuth(profileToReturn: _profile());
    final cubit = ProfileCubit(
      _FakeProfileRepo(),
      _FakeGraph(),
      auth,
      _FakeWishes(),
    );

    final first = cubit.load();
    final second = cubit.load();
    await Future.wait([first, second]);

    expect(auth.loadProfileCalls, 1);
  });
}
