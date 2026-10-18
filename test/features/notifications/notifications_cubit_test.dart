import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/notifications/notification_badge_cubit.dart';
import 'package:birthday_app/features/notifications/notifications_cubit.dart';
import 'package:birthday_app/features/notifications/notifications_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notifications.dart';

void main() {
  group('NotificationsCubit', () {
    test('loads, THEN marks everything seen, keeping what was new marked new',
        () async {
      final repo = FakeNotifications(items: [wishN(1), reminderN(2, seen: true)]);
      final cubit = NotificationsCubit(repo);

      await cubit.load();

      // Order matters: marking first would load every row as already seen
      // and the screen could not highlight what is new.
      expect(repo.calls, ['list', 'markAllSeen']);
      final state = cubit.state as NotificationsLoaded;
      expect(state.items.map((n) => n.seen), [false, true]);
    });

    test('nothing queued yet is the empty state', () async {
      final cubit = NotificationsCubit(FakeNotifications());
      await cubit.load();
      expect(cubit.state, isA<NotificationsEmpty>());
    });

    test("a failed load shows the failure's own message", () async {
      final repo = FakeNotifications()
        ..listError = const ServerFailure('server says no');
      final cubit = NotificationsCubit(repo);
      await cubit.load();
      expect((cubit.state as NotificationsError).message, 'server says no');
      expect(repo.calls, ['list'], reason: 'nothing to mark seen');
    });

    test('a failed mark-seen still leaves the list on screen', () async {
      final repo = FakeNotifications(items: [wishN(1)])
        ..markError = const ServerFailure('boom');
      final cubit = NotificationsCubit(repo);
      await cubit.load();
      expect(cubit.state, isA<NotificationsLoaded>());
    });

    test('loadMore pages back from the oldest one shown', () async {
      final repo = FakeNotifications(
        items: [for (var i = 1; i <= 5; i++) reminderN(i)],
      );
      final cubit = NotificationsCubit(repo, pageSize: 3);
      await cubit.load();
      expect((cubit.state as NotificationsLoaded).hasMore, isTrue);

      await cubit.loadMore();

      final state = cubit.state as NotificationsLoaded;
      expect(state.items.map((n) => n.id), [1, 2, 3, 4, 5]);
      expect(state.hasMore, isFalse);
    });
  });

  group('NotificationBadgeCubit', () {
    test('refresh reads the unseen count; clear zeroes it', () async {
      final cubit = NotificationBadgeCubit(FakeNotifications(unseen: 4));
      await cubit.refresh();
      expect(cubit.state, 4);
      cubit.clear();
      expect(cubit.state, 0);
    });
  });
}
