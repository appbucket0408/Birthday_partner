import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/connections/connections_screen.dart';
import '../features/contacts_import/import_disclosure_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/gifting/cake_coming_soon_screen.dart';
import '../features/gifting/gift_list_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/phone_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
import '../features/person/person_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/timeline/timeline_screen.dart';
import 'home_shell.dart';
import 'session_cubit.dart';
import 'session_state.dart';

/// Bridges a Cubit to go_router's Listenable-based refresh.
class _CubitRefresh extends ChangeNotifier {
  _CubitRefresh(Stream<SessionState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<SessionState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter buildRouter(
  SessionCubit session, {
  List<NavigatorObserver> observers = const [],
}) {
  return GoRouter(
    observers: observers,
    initialLocation: '/splash',
    refreshListenable: _CubitRefresh(session.stream),
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text(AppStrings.routeNotFoundTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.routeNotFoundBody, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('router_error_go_home'),
                onPressed: () => context.go('/feed'),
                child: const Text(AppStrings.routeNotFoundAction),
              ),
            ],
          ),
        ),
      ),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const ProfileSetupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                builder: (_, __) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/timeline',
                builder: (_, __) => const TimelineScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, __) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/import',
        builder: (_, __) => const ImportDisclosureScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/person/:personId',
        builder: (_, state) => PersonScreen(
          personId: int.parse(state.pathParameters['personId']!),
          openWishId: switch (int.tryParse(
            state.uri.queryParameters['wish'] ?? '',
          )) {
            final id? when id > 0 => id,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: '/gift/new/:personId',
        // Coming soon until payments exist; the catalog flow is kept for
        // then (see CakeComingSoonScreen).
        builder: (_, state) => CakeComingSoonScreen(
          personId: int.parse(state.pathParameters['personId']!),
        ),
      ),
      GoRoute(path: '/gifts', builder: (_, __) => const GiftListScreen()),
      // Full screen, above the tabs, opened from any tab's bell and popped
      // back to it.
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      // Both counts on the Profile tab open the same screen, each on its own
      // tab -- Instagram's Following / Followers.
      GoRoute(
        path: '/profile/celebrating',
        builder: (_, __) =>
            const ConnectionsScreen(initialTab: ConnectionsTab.iCelebrate),
      ),
      GoRoute(
        path: '/profile/celebrates',
        builder: (_, __) =>
            const ConnectionsScreen(initialTab: ConnectionsTab.celebrateMe),
      ),
    ],
    redirect: (context, state) {
      final s = session.state;
      final at = state.matchedLocation;
      const signedIn = {
        '/feed',
        '/timeline',
        '/calendar',
        '/import',
        '/settings',
        '/profile',
        '/profile/celebrating',
        '/profile/celebrates',
        '/gifts',
        '/notifications',
      };
      final onPersonPage = at.startsWith('/person/');
      final onGiftCatalogPage = at.startsWith('/gift/new/');
      const recognizedElsewhere = {'/splash', '/phone', '/setup', ...signedIn};
      if (!recognizedElsewhere.contains(at) &&
          !onPersonPage &&
          !onGiftCatalogPage) {
        return null;
      }

      // Never route anywhere until the first load resolves.
      if (s is SessionUnknown) return at == '/splash' ? null : '/splash';

      final target = switch (s) {
        SessionSignedOut() => '/phone',
        SessionNeedsSetup() => '/setup',
        SessionReady() => '/feed',
        SessionUnknown() => '/splash',
      };

      if (s is SessionReady &&
          (signedIn.contains(at) || onPersonPage || onGiftCatalogPage)) {
        return null;
      }

      return at == target ? null : target;
    },
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.appName,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
