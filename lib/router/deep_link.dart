import 'session_cubit.dart';
import 'session_state.dart';

/// Navigates to a route that arrived from outside the app, but not before
/// the session has resolved.
///
/// The timing matters and is not obvious. `getInitialMessage()` is a
/// platform-channel round trip that resolves in milliseconds;
/// `SessionCubit.load()` is a network call that does not. So on a cold start
/// from a tapped notification, the route is in hand while the session is
/// still [SessionUnknown] -- and `buildRouter`'s redirect sends every
/// location but '/splash' to '/splash' in that state, after which '/splash'
/// redirects on to '/timeline'. Navigating immediately therefore does not
/// deep-link at all: it silently lands the user on the timeline and throws
/// the link away.
///
/// Waiting costs nothing, because the destination screens are all behind
/// [SessionReady] anyway. If the session resolves to signed-out, the
/// router's own redirect handles it from there -- this function does not
/// second-guess where the user is allowed to go, only when it is safe to ask.
Future<void> navigateWhenSessionResolves({
  required String route,
  required SessionCubit session,
  required void Function(String route) go,
}) async {
  if (session.state is! SessionUnknown) {
    go(route);
    return;
  }
  await session.stream.firstWhere((s) => s is! SessionUnknown);
  go(route);
}
