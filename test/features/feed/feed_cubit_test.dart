import 'dart:typed_data';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/feed/feed_cubit.dart';
import 'package:birthday_app/features/feed/feed_state.dart';
import 'package:birthday_app/models/feed_entry.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWish implements WishRepository {
  _FakeWish(this.all);

  List<FeedEntry> all;
  Object? error;
  final befores = <DateTime?>[];

  @override
  Future<List<FeedEntry>> feed({DateTime? before, int limit = 20}) async {
    befores.add(before);
    if (error != null) throw error!;
    return all
        .where((e) => before == null || e.wish.createdAt.isBefore(before))
        .take(limit)
        .toList();
  }

  @override
  Future<List<Wish>> wishesFor(int personId) => throw UnimplementedError();

  @override
  Future<List<Wish>> wishesToMe() => throw UnimplementedError();

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
    String? photoPath,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadPhoto(Uint8List bytes, {required String extension}) =>
      throw UnimplementedError();

  @override
  Future<void> removePhoto(String path) => throw UnimplementedError();

  @override
  Future<String> photoUrl(String path) => throw UnimplementedError();
}

/// Entry [id], posted [id] minutes after a fixed instant -- so higher ids
/// are newer.
FeedEntry _entry(int id) => FeedEntry(
      wish: Wish(
        id: id,
        authorProfileId: 'author',
        subjectPersonId: 1,
        body: 'Happy birthday! 🎂',
        occasionYear: 2026,
        createdAt: DateTime.utc(2026, 10, 18).add(Duration(minutes: id)),
      ),
      subjectName: 'b_02',
    );

List<FeedEntry> _newestFirst(int count) =>
    [for (var id = count; id >= 1; id--) _entry(id)];

List<int> _ids(FeedState s) =>
    (s as FeedLoaded).entries.map((e) => e.wish.id).toList();

void main() {
  test('load() shows the first page, newest first', () async {
    final cubit = FeedCubit(_FakeWish(_newestFirst(5)), pageSize: 3);

    await cubit.load();

    expect(_ids(cubit.state), [5, 4, 3]);
    expect((cubit.state as FeedLoaded).hasMore, isTrue);
  });

  test('no wishes at all is FeedEmpty, not an empty list', () async {
    final cubit = FeedCubit(_FakeWish(const []));

    await cubit.load();

    expect(cubit.state, isA<FeedEmpty>());
  });

  test('a failed load is FeedError with a readable message', () async {
    final cubit = FeedCubit(
      _FakeWish(const [])..error = const ServerFailure('server down'),
    );

    await cubit.load();

    expect((cubit.state as FeedError).message, 'server down');
  });

  test('loadMore() appends older wishes and stops at the end', () async {
    final repo = _FakeWish(_newestFirst(5));
    final cubit = FeedCubit(repo, pageSize: 3);
    await cubit.load();

    await cubit.loadMore();

    expect(_ids(cubit.state), [5, 4, 3, 2, 1]);
    expect((cubit.state as FeedLoaded).hasMore, isFalse);
    expect(repo.befores.last, _entry(3).wish.createdAt);

    await cubit.loadMore(); // nothing older: no request
    expect(repo.befores, hasLength(2));
  });

  test('a failed loadMore() keeps the list and marks the footer', () async {
    final repo = _FakeWish(_newestFirst(5));
    final cubit = FeedCubit(repo, pageSize: 3);
    await cubit.load();

    repo.error = const ServerFailure('timeout');
    await cubit.loadMore();

    expect(_ids(cubit.state), [5, 4, 3]);
    expect((cubit.state as FeedLoaded).moreFailed, isTrue);

    repo.error = null;
    await cubit.loadMore();
    expect(_ids(cubit.state), [5, 4, 3, 2, 1]);
  });

  test('refresh() picks up a new wish without blanking the list', () async {
    final repo = _FakeWish(_newestFirst(2));
    final cubit = FeedCubit(repo);
    await cubit.load();

    repo.all = _newestFirst(3);
    final states = <FeedState>[];
    final sub = cubit.stream.listen(states.add);
    await cubit.refresh();
    await sub.cancel();

    expect(_ids(cubit.state), [3, 2, 1]);
    expect(states.whereType<FeedLoading>(), isEmpty);
  });

  test('a failed refresh() keeps the list and reports it once', () async {
    final repo = _FakeWish(_newestFirst(2));
    final cubit = FeedCubit(repo);
    await cubit.load();

    repo.error = const ServerFailure('offline');
    await cubit.refresh();

    expect(_ids(cubit.state), [2, 1]);
    expect((cubit.state as FeedLoaded).error, AppStrings.somethingWentWrong);
  });

  test('a second load while one is in flight is ignored', () async {
    final repo = _FakeWish(_newestFirst(2));
    final cubit = FeedCubit(repo);

    await Future.wait([cubit.load(), cubit.load()]);

    expect(repo.befores, hasLength(1));
  });
}
