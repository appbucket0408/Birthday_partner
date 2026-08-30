import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../features/contacts_import/import_disclosure_screen.dart';
import '../features/onboarding/phone_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
import '../features/person/person_screen.dart';
import '../features/profile/celebration_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/timeline/timeline_screen.dart';
import '../repositories/graph_repository.dart';
import '../repositories/profile_repository.dart';
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
      GoRoute(
        path: '/person/:personId',
        builder: (_, state) => PersonScreen(
          personId: int.parse(state.pathParameters['personId']!),
        ),
      ),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/profile/celebrating',
        builder: (context, __) => CelebrationListScreen(
          title: AppStrings.profileCelebrating,
          emptyMessage: AppStrings.profileCelebratingEmpty,
          navigable: true,
          fetchPeople: () async {
            final celebrations =
                await context.read<GraphRepository>().celebrations();
            return celebrations.map((c) => c.person).toList();
          },
        ),
      ),
      GoRoute(
        path: '/profile/celebrates',
        builder: (context, __) => CelebrationListScreen(
          title: AppStrings.profileCelebrates,
          emptyMessage: AppStrings.profileCelebratesEmpty,
          fetchPeople: () => context.read<ProfileRepository>().celebrates(),
        ),
      ),
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
      //
      // '/person/:personId' cannot go in the set as a literal string: unlike
      // every other entry here, it carries a path parameter, so `matchedLocation`
      // is the substituted location (e.g. '/person/42'), never the bare
      // '/person' the route is declared with. A literal-set membership check
      // would never match it and the guard would bounce every visit straight
      // back to '/timeline' -- checked separately, by prefix, for that reason.
      const signedIn = {
        '/timeline',
        '/import',
        '/settings',
        '/profile',
        '/profile/celebrating',
        '/profile/celebrates',
      };
      final onPersonPage = at.startsWith('/person/');
      if (s is SessionReady && (signedIn.contains(at) || onPersonPage)) {
        return null;
      }

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
