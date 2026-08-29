import '../models/profile.dart';

sealed class SessionState {
  const SessionState();
}

/// Before the first load resolves. The router shows a splash, never a screen.
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// Signed in, but profiles.birth_month is still null.
final class SessionNeedsSetup extends SessionState {
  const SessionNeedsSetup();
}

final class SessionReady extends SessionState {
  const SessionReady(this.profile);
  final Profile profile;
}
