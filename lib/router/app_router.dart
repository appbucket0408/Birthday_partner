import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../features/contacts_import/import_disclosure_screen.dart';
import '../features/gifting/catalog_screen.dart';
import '../features/gifting/gift_list_screen.dart';
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
      // Carries a path parameter, so -- like '/person/:personId' -- it is
      // matched by prefix below, not added to the literal `signedIn` set.
      // The slot picker and the draft screen that follow it are
      // parameterless but cannot carry the selection (person, birthday,
      // product, slot) accumulating across the three screens, so both are
      // pushed rather than routed (see task-5-brief.md and CatalogScreen's
      // doc). '/gifts' (below) is the one screen after this point that IS a
      // real route: it carries nothing forward, so it can be.
      GoRoute(
        path: '/gift/new/:personId',
        builder: (_, state) => CatalogScreen(
          personId: int.parse(state.pathParameters['personId']!),
        ),
      ),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      // Parameterless and genuinely addressable -- unlike the slot picker and
      // draft screens that precede it, it only loads the signed-in user's
      // own gifts, so it needs nothing carried forward from another screen.
      // Literal `signedIn` membership is therefore correct here, unlike
      // '/person/:personId' and '/gift/new/:personId' below, which carry a
      // path parameter and so need prefix matching instead (see those
      // routes' own comments).
      GoRoute(path: '/gifts', builder: (_, __) => const GiftListScreen()),
      GoRoute(
        path: '/profile/celebrating',
        builder: (context, __) => CelebrationListScreen(
          title: AppStrings.profileCelebrating,
          emptyMessage: AppStrings.profileCelebratingEmpty,
          navigable: true,
          fetchPeople: () async {
            final celebrations =
                await context.read<GraphRepository>().celebrations();
            return CelebrationListScreen.peopleFromCelebrations(celebrations);
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
        '/gifts',
      };
      final onPersonPage = at.startsWith('/person/');
      // '/gift/new/:personId' carries a path parameter for the same reason
      // '/person/:personId' does, so it needs the same prefix treatment --
      // a literal `signedIn` membership test never matches the substituted
      // location and the screen becomes unreachable while still compiling
      // and analyzing clean, exactly as '/person/:personId' once did.
      final onGiftCatalogPage = at.startsWith('/gift/new/');
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
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
