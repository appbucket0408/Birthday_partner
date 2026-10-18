import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../features/notifications/notification_badge_cubit.dart';
import 'active_tab.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  // Branch order in app_router.dart's StatefulShellRoute.
  static const feedTab = 0;
  static const dashboardTab = 1;
  static const calendarTab = 2;
  static const profileTab = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Tells each tab which one is showing, so Calendar and Profile can
      // refresh when the user comes back to them.
      body: ActiveTab(index: shell.currentIndex, child: shell),
      // A hairline instead of a shadow separates the bar from the content.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
          key: const Key('home_nav_bar'),
          selectedIndex: shell.currentIndex,
          // Re-tapping the active tab returns it to its root, the way every
          // tab bar on the platform behaves.
          onDestinationSelected: (index) {
            shell.goBranch(index, initialLocation: index == shell.currentIndex);
            // Something may have arrived while the app was open; the bell is
            // in every tab, so a tab switch is a natural moment to recount.
            try {
              context.read<NotificationBadgeCubit>().refresh();
            } on ProviderNotFoundException {
              // Router tests build the shell without it.
            }
          },
          destinations: const [
            NavigationDestination(
              key: Key('nav_feed'),
              icon: Icon(Icons.dynamic_feed_outlined),
              selectedIcon: Icon(Icons.dynamic_feed),
              label: AppStrings.navFeed,
            ),
            NavigationDestination(
              key: Key('nav_dashboard'),
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: AppStrings.navDashboard,
            ),
            NavigationDestination(
              key: Key('nav_calendar'),
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: AppStrings.navCalendar,
            ),
            NavigationDestination(
              key: Key('nav_profile'),
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: AppStrings.navProfile,
            ),
          ],
        ),
      ),
    );
  }
}
