import 'dart:typed_data';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/feed/feed_cubit.dart';
import 'package:birthday_app/features/feed/feed_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/feed_entry.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:birthday_app/router/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWish implements WishRepository {
  _FakeWish(this.entries);

  List<FeedEntry> entries;
  Object? error;

  @override
  Future<List<FeedEntry>> feed({DateTime? before, int limit = 20}) async {
    if (error != null) throw error!;
    return before == null ? entries : const [];
  }

  // No signed URL in a widget test: the photo falls back to its
  // broken-image placeholder, which is itself under test.
  @override
  Future<String> photoUrl(String path) async =>
      throw const ServerFailure('no storage in tests');

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
}

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
  id: 'me',
  handle: 'sachin',
  displayName: 'Sachin',
  remindersEnabled: true,
  birthday: Birthday(month: 3, day: 12),
);

final _now = DateTime(2026, 10, 18, 15);

FeedEntry _entry(
  int id, {
  required String body,
  String kind = 'message',
  String? photoPath,
  String? author = 'b_03',
  Duration age = const Duration(hours: 3),
}) =>
    FeedEntry(
      wish: Wish(
        id: id,
        authorProfileId: 'author-$id',
        subjectPersonId: 2,
        body: body,
        kind: kind,
        occasionYear: 2026,
        createdAt: _now.subtract(age),
        photoPath: photoPath,
        authorName: author,
      ),
      subjectName: 'b_02',
    );

Future<_FakeWish> _pump(WidgetTester tester, List<FeedEntry> entries) async {
  final repo = _FakeWish(entries);
  await tester.pumpWidget(
    RepositoryProvider<WishRepository>.value(
      value: repo,
      child: BlocProvider<SessionCubit>(
        create: (_) => _StubSessionCubit(const SessionReady(_me)),
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => FeedCubit(repo)..load(),
            child: FeedView(now: () => _now),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('a text wish, a photo wish and a cake each render as a post',
      (tester) async {
    await _pump(tester, [
      _entry(1, body: 'Happy birthday! 🎂'),
      _entry(2, body: 'Another year 🎈', photoPath: 'author-2/p.jpg'),
      _entry(3, body: 'sent a cake', kind: 'cake', author: null),
    ]);

    expect(find.byKey(const Key('feed_post_1')), findsOneWidget);
    expect(find.text('Happy birthday! 🎂'), findsOneWidget);
    expect(find.text('Another year 🎈'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('feed_post_3')),
      200,
    );
    expect(find.text(AppStrings.feedCakeBody), findsOneWidget);
    expect(
      find.textContaining(
        '${AppStrings.feedAuthorUnknown} ${AppStrings.feedSentCakeTo} b_02',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the header names both people and says how long ago',
      (tester) async {
    await _pump(tester, [_entry(1, body: 'HBD!')]);

    expect(
      find.textContaining('b_03 ${AppStrings.feedWished} b_02',
          findRichText: true),
      findsOneWidget,
    );
    expect(find.text('3h'), findsOneWidget);
  });

  testWidgets('no wishes shows the empty state, with a way to add people',
      (tester) async {
    await _pump(tester, const []);

    expect(find.byKey(const Key('feed_empty')), findsOneWidget);
    expect(find.byKey(const Key('feed_add_people')), findsOneWidget);
  });

  testWidgets('an error offers Retry, which loads the feed', (tester) async {
    final repo = _FakeWish([_entry(1, body: 'Back again')])
      ..error = const ServerFailure('server down');
    await tester.pumpWidget(
      RepositoryProvider<WishRepository>.value(
        value: repo,
        child: BlocProvider<SessionCubit>(
          create: (_) => _StubSessionCubit(const SessionReady(_me)),
          child: MaterialApp(
            home: BlocProvider(
              create: (_) => FeedCubit(repo)..load(),
              child: FeedView(now: () => _now),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('server down'), findsOneWidget);

    repo.error = null;
    await tester.tap(find.byKey(const Key('feed_retry')));
    await tester.pumpAndSettle();

    expect(find.text('Back again'), findsOneWidget);
  });
}
