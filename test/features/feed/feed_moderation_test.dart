import 'dart:typed_data';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/feed/feed_cubit.dart';
import 'package:birthday_app/features/feed/feed_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/blocked_user.dart';
import 'package:birthday_app/models/feed_entry.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/models/report_reason.dart';
import 'package:birthday_app/models/wish.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/moderation_repository.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:birthday_app/router/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWish implements WishRepository {
  _FakeWish(this.entries);
  List<FeedEntry> entries;

  @override
  Future<List<FeedEntry>> feed({DateTime? before, int limit = 20}) async =>
      before == null ? entries : const [];

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

/// Records calls, and drops the affected posts from the fake feed the way
/// feed_page does server-side, so the refresh after an action is visible.
class _FakeModeration implements ModerationRepository {
  _FakeModeration(this.wishes);
  final _FakeWish wishes;
  final reported = <(int, ReportReason)>[];
  final blocked = <String>[];
  Object? error;

  @override
  Future<void> reportWish(int wishId, ReportReason reason) async {
    if (error != null) throw error!;
    reported.add((wishId, reason));
    wishes.entries =
        wishes.entries.where((e) => e.wish.id != wishId).toList();
  }

  @override
  Future<void> block(String profileId) async {
    if (error != null) throw error!;
    blocked.add(profileId);
    wishes.entries = wishes.entries
        .where((e) => e.wish.authorProfileId != profileId)
        .toList();
  }

  @override
  Future<void> reportUser(String profileId, ReportReason reason) =>
      throw UnimplementedError();

  @override
  Future<void> unblock(String profileId) => throw UnimplementedError();

  @override
  Future<List<BlockedUser>> blockedUsers() => throw UnimplementedError();
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

FeedEntry _entry(int id, {required String author, String? authorId}) =>
    FeedEntry(
      wish: Wish(
        id: id,
        authorProfileId: authorId ?? 'author-$id',
        subjectPersonId: 2,
        body: 'wish $id',
        kind: 'message',
        occasionYear: 2026,
        createdAt: _now.subtract(const Duration(hours: 1)),
        authorName: author,
      ),
      subjectName: 'b_02',
    );

Future<_FakeModeration> _pump(
  WidgetTester tester,
  List<FeedEntry> entries,
) async {
  final wishes = _FakeWish(entries);
  final moderation = _FakeModeration(wishes);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<WishRepository>.value(value: wishes),
        RepositoryProvider<ModerationRepository>.value(value: moderation),
      ],
      child: BlocProvider<SessionCubit>(
        create: (_) => _StubSessionCubit(const SessionReady(_me)),
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => FeedCubit(wishes)..load(),
            child: FeedView(now: () => _now),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return moderation;
}

void main() {
  testWidgets('only other people\'s posts offer report and block',
      (tester) async {
    await _pump(tester, [
      _entry(1, author: 'Asha'),
      _entry(2, author: 'Sachin', authorId: 'me'),
    ]);

    expect(find.byKey(const Key('feed_more_1')), findsOneWidget);
    expect(find.byKey(const Key('feed_more_2')), findsNothing);
  });

  testWidgets('reporting a post sends the reason and drops it from the feed',
      (tester) async {
    final moderation = await _pump(tester, [
      _entry(1, author: 'Asha'),
      _entry(3, author: 'Ravi'),
    ]);

    await tester.tap(find.byKey(const Key('feed_more_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moderation_report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report_reason_spam')));
    await tester.pumpAndSettle();

    expect(moderation.reported, [(1, ReportReason.spam)]);
    expect(find.text(AppStrings.reportedPost), findsOneWidget);
    expect(find.text('wish 1'), findsNothing);
    expect(find.text('wish 3'), findsOneWidget);
  });

  testWidgets('blocking asks first, then blocks the author', (tester) async {
    final moderation = await _pump(tester, [_entry(1, author: 'Asha')]);

    await tester.tap(find.byKey(const Key('feed_more_1')));
    await tester.pumpAndSettle();
    expect(find.text('Block Asha'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moderation_block')));
    await tester.pumpAndSettle();

    expect(find.text('Block Asha?'), findsOneWidget);
    expect(moderation.blocked, isEmpty);

    await tester.tap(find.byKey(const Key('moderation_block_confirm')));
    await tester.pumpAndSettle();

    expect(moderation.blocked, ['author-1']);
    expect(find.text('Asha is blocked.'), findsOneWidget);
    expect(find.text('wish 1'), findsNothing);
  });

  testWidgets('backing out of the reason list reports nothing',
      (tester) async {
    final moderation = await _pump(tester, [_entry(1, author: 'Asha')]);

    await tester.tap(find.byKey(const Key('feed_more_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moderation_report')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(moderation.reported, isEmpty);
    expect(find.text('wish 1'), findsOneWidget);
  });

  testWidgets('a failed report says why and keeps the post', (tester) async {
    final moderation = await _pump(tester, [_entry(1, author: 'Asha')])
      ..error = const ServerFailure('server down');

    await tester.tap(find.byKey(const Key('feed_more_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moderation_report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report_reason_hate')));
    await tester.pumpAndSettle();

    expect(moderation.reported, isEmpty);
    expect(find.text('server down'), findsOneWidget);
    expect(find.text('wish 1'), findsOneWidget);
  });
}
