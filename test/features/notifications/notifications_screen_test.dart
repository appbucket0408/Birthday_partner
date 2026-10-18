import 'package:birthday_app/features/notifications/notification_badge_cubit.dart';
import 'package:birthday_app/features/notifications/notification_bell.dart';
import 'package:birthday_app/features/notifications/notifications_screen.dart';
import 'package:birthday_app/repositories/notification_repository.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../repositories/push_repository_test.dart' show FakePush;
import 'fake_notifications.dart';

/// A tab with the bell, the Notifications screen, and a stand-in person page
/// that shows the location it was opened with -- enough to follow a tap all
/// the way through, the way the real router does.
Future<NotificationBadgeCubit> _pumpApp(
  WidgetTester tester,
  FakeNotifications repo, {
  PushPermission permission = PushPermission.granted,
}) async {
  final badge = NotificationBadgeCubit(repo);
  final router = GoRouter(
    initialLocation: '/tab',
    routes: [
      GoRoute(
        path: '/tab',
        builder: (_, __) => Scaffold(
          appBar: AppBar(actions: const [NotificationBell()]),
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/person/:id',
        builder: (_, state) => Scaffold(body: Text('opened ${state.uri}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<NotificationRepository>.value(value: repo),
        RepositoryProvider<PushRepository>.value(
          value: FakePush(status: permission),
        ),
      ],
      child: BlocProvider.value(
        value: badge,
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return badge;
}

void main() {
  testWidgets('the bell shows the unseen count, and opening the list clears it',
      (tester) async {
    final repo = FakeNotifications(items: [wishN(1)], unseen: 3);
    final badge = await _pumpApp(tester, repo);

    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notification_bell')));
    await tester.pumpAndSettle();

    expect(find.text('Ravi left you a birthday wish.'), findsOneWidget);
    expect(badge.state, 0);
    expect(repo.calls, containsAllInOrder(['list', 'markAllSeen']));
  });

  testWidgets('what was new is marked; what was seen is not', (tester) async {
    final repo = FakeNotifications(
      items: [wishN(1), reminderN(2, seen: true)],
      unseen: 1,
    );
    await _pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('notification_bell')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification_unseen_1')), findsOneWidget);
    expect(find.byKey(const Key('notification_unseen_2')), findsNothing);
    expect(find.text("Asha's birthday is tomorrow."), findsOneWidget);
  });

  testWidgets('tapping a wish opens my wall with the wish, like the push',
      (tester) async {
    final repo = FakeNotifications(items: [wishN(1)]);
    await _pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('notification_bell')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification_1')));
    await tester.pumpAndSettle();

    expect(find.text('opened /person/7?wish=901'), findsOneWidget);
  });

  testWidgets('with nothing queued it says so', (tester) async {
    await _pumpApp(tester, FakeNotifications());
    await tester.tap(find.byKey(const Key('notification_bell')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
  });

  group('the notifications-off banner', () {
    testWidgets('is absent while the phone allows notifications',
        (tester) async {
      await _pumpApp(tester, FakeNotifications(items: [wishN(1)]));
      await tester.tap(find.byKey(const Key('notification_bell')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications_off_banner')), findsNothing);
    });

    testWidgets('shows when they are off, above the list', (tester) async {
      await _pumpApp(
        tester,
        FakeNotifications(items: [wishN(1)]),
        permission: PushPermission.blocked,
      );
      await tester.tap(find.byKey(const Key('notification_bell')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications_off_banner')), findsOneWidget);
      expect(find.byKey(const Key('notification_1')), findsOneWidget);
    });
  });

  testWidgets('without a badge provider the bell renders nothing',
      (tester) async {
    // Every single-tab widget test pumps a tab screen like this.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NotificationBell())),
    );
    expect(find.byKey(const Key('notification_bell')), findsNothing);
  });
}
