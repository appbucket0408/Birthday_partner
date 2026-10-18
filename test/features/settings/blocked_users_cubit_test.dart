import 'dart:async';

import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/settings/blocked_users_cubit.dart';
import 'package:birthday_app/features/settings/blocked_users_state.dart';
import 'package:birthday_app/models/blocked_user.dart';
import 'package:birthday_app/models/report_reason.dart';
import 'package:birthday_app/repositories/moderation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeModeration implements ModerationRepository {
  List<BlockedUser> users = const [
    BlockedUser(profileId: 'a', displayName: 'Asha'),
    BlockedUser(profileId: 'b', displayName: 'Ravi'),
  ];
  Object? listError;
  Object? unblockError;
  final unblocked = <String>[];
  Completer<void>? gate;

  @override
  Future<List<BlockedUser>> blockedUsers() async {
    if (listError != null) throw listError!;
    return users;
  }

  @override
  Future<void> unblock(String profileId) async {
    await gate?.future;
    if (unblockError != null) throw unblockError!;
    unblocked.add(profileId);
  }

  @override
  Future<void> block(String profileId) => throw UnimplementedError();

  @override
  Future<void> reportUser(String profileId, ReportReason reason) =>
      throw UnimplementedError();

  @override
  Future<void> reportWish(int wishId, ReportReason reason) =>
      throw UnimplementedError();
}

void main() {
  test('load lists the blocked people', () async {
    final cubit = BlockedUsersCubit(_FakeModeration());
    await cubit.load();

    final state = cubit.state as BlockedUsersLoaded;
    expect(state.users.map((u) => u.displayName), ['Asha', 'Ravi']);
  });

  test('a failed load is an error with the failure\'s own message', () async {
    final repo = _FakeModeration()..listError = const ServerFailure('down');
    final cubit = BlockedUsersCubit(repo);
    await cubit.load();

    expect((cubit.state as BlockedUsersError).message, 'down');
  });

  test('unblock removes the row and reports success', () async {
    final repo = _FakeModeration();
    final cubit = BlockedUsersCubit(repo);
    await cubit.load();

    expect(await cubit.unblock('a'), isTrue);

    expect(repo.unblocked, ['a']);
    final state = cubit.state as BlockedUsersLoaded;
    expect(state.users.map((u) => u.profileId), ['b']);
    expect(state.unblocking, isEmpty);
  });

  test('a failed unblock keeps the row and carries the message', () async {
    final repo = _FakeModeration()..unblockError = const ServerFailure('nope');
    final cubit = BlockedUsersCubit(repo);
    await cubit.load();

    expect(await cubit.unblock('a'), isFalse);

    final state = cubit.state as BlockedUsersLoaded;
    expect(state.users.map((u) => u.profileId), ['a', 'b']);
    expect(state.error, 'nope');
    expect(state.unblocking, isEmpty);
  });

  test('a double tap on one row is one unblock', () async {
    final repo = _FakeModeration()..gate = Completer<void>();
    final cubit = BlockedUsersCubit(repo);
    await cubit.load();

    final first = cubit.unblock('a');
    final second = cubit.unblock('a');
    expect((cubit.state as BlockedUsersLoaded).unblocking, {'a'});
    repo.gate!.complete();
    await Future.wait([first, second]);

    expect(repo.unblocked, ['a']);
  });
}
