import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/onboarding/phone_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
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

GoRouter buildRouter(SessionCubit session) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _CubitRefresh(session.stream),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneScreen()),
      // Deliberately no '/otp' route: OtpScreen is reached only via
      // Navigator.push from PhoneScreen, handed the live PhoneCubit through
      // BlocProvider.value. The screen has no meaning on its own -- it
      // renders the phone number held in that cubit's memory, and a
      // URL-addressable '/otp' would have nothing to verify against. A
      // signed-out user landing on '#/otp' being redirected back to '/phone'
      // by the guard below is correct, not a missing route.
      GoRoute(path: '/setup', builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: '/timeline', builder: (_, __) => const TimelineScreen()),
      GoRoute(
        path: '/import',
        builder: (_, __) => const ImportDisclosureScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
    redirect: (context, state) {
      final s = session.state;
      final at = state.matchedLocation;

      // Never route anywhere until the first load resolves.
      if (s is SessionUnknown) return at == '/splash' ? null : '/splash';

      final target = switch (s) {
        SessionSignedOut() => '/phone',
        SessionNeedsSetup() => '/setup',
        SessionReady() => '/timeline',
        SessionUnknown() => '/splash',
      };

      // Once ready, the user moves freely between the signed-in screens.
      const signedIn = {'/timeline', '/import', '/settings'};
      if (s is SessionReady && signedIn.contains(at)) return null;

      return at == target ? null : target;
    },
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

// Placeholders so this task compiles on its own. Each later screen task
// DELETES its placeholder here and adds the real import at the top of the
// file: Task 10 -> ImportDisclosureScreen, Task 12 -> TimelineScreen,
// Task 13 -> SettingsScreen. Leaving one behind shadows the real screen
// silently. (Task 7's PhoneScreen and Task 8's ProfileSetupScreen
// placeholders are gone -- the real ones are imported above.)
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ImportDisclosureScreen extends StatelessWidget {
  const ImportDisclosureScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}
