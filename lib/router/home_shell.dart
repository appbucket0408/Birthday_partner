import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';

/// The bottom navigation bar around the three signed-in tabs: Dashboard
/// ('/timeline'), Calendar ('/calendar') and Profile ('/profile').
///
/// Each tab is a branch of a `StatefulShellRoute.indexedStack`, so switching
/// tabs keeps every tab's scroll position and loaded state instead of
/// rebuilding it. Material 3's [NavigationBar] pads itself by the bottom
/// system inset, which keeps it clear of Android's gesture bar or
/// three-button bar without an extra SafeArea.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        key: const Key('home_nav_bar'),
        selectedIndex: shell.currentIndex,
        // Re-tapping the active tab returns it to its root, the way every
        // tab bar on the platform behaves.
        onDestinationSelected: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
        destinations: const [
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
    );
  }
}
