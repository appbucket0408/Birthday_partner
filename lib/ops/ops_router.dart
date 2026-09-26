import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_spacing.dart';
import '../core/app_strings.dart';
import 'signin/signin_cubit.dart';
import 'signin/signin_screen.dart';
import 'signin/signin_state.dart';

/// The ops console's own router. Deliberately not the consumer app's
/// `buildRouter`: that one redirects on a phone-OTP `SessionCubit` and knows
/// about onboarding, contacts and gifting routes that have no meaning here.
///
/// Every route but `/signin` requires [SignInReady] — signed in AND confirmed
/// staff. That redirect is for legibility, not security: RLS refuses a
/// non-staff caller every read and write regardless
/// (`products_staff_write`, `delivery_slots_staff_write`,
/// `service_areas_staff_write`, each `for all using (private.is_staff())`).
GoRouter buildOpsRouter(SignInCubit session) {
  return GoRouter(
    initialLocation: '/signin',
    refreshListenable: _CubitListenable(session),
    routes: [
      GoRoute(
        path: '/signin',
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: '/catalog',
        builder: (_, __) => const OpsCatalogPlaceholder(),
      ),
      GoRoute(
        path: '/slots',
        builder: (_, __) => const OpsSlotsPlaceholder(),
      ),
    ],
    redirect: (context, state) {
      final ready = session.state is SignInReady;
      final at = state.matchedLocation;

      if (!ready) return at == '/signin' ? null : '/signin';
      // Signed in and staff: keep them out of the sign-in screen.
      return at == '/signin' ? '/catalog' : null;
    },
    // The consumer router shipped without one of these until M3 Phase 1a's
    // review, and an unmatched location was a dead end with no way back.
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text(AppStrings.opsTitle)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.opsNotFound),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              key: const Key('ops_error_home'),
              onPressed: () => context.go('/catalog'),
              child: const Text(AppStrings.opsBackToCatalog),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bridges a Cubit to go_router's `refreshListenable`, so the redirect above
/// re-runs when sign-in state changes.
class _CubitListenable extends ChangeNotifier {
  _CubitListenable(SignInCubit cubit) {
    _sub = cubit.stream.listen((_) => notifyListeners());
  }

  late final dynamic _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Stands in for Task 4's `OpsCatalogScreen`. Exists so this router compiles
/// and its redirect is testable before that task lands — M1 Phase 2b shipped
/// a router naming five screens it never imported or stubbed, and this is
/// that defect avoided rather than rediscovered. Task 4 deletes this class
/// and points the route at the real screen.
class OpsCatalogPlaceholder extends StatelessWidget {
  const OpsCatalogPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(AppStrings.opsCatalogTab)),
        body: const Center(child: Text('Catalog — coming in Task 4.')),
      );
}

/// Stands in for Task 5's `OpsSlotsScreen`. Same reasoning as
/// [OpsCatalogPlaceholder]; Task 5 deletes it.
class OpsSlotsPlaceholder extends StatelessWidget {
  const OpsSlotsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(AppStrings.opsSlotsTab)),
        body: const Center(child: Text('Delivery slots — coming in Task 5.')),
      );
}
