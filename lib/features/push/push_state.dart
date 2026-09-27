sealed class PushState {
  const PushState();
}

final class PushIdle extends PushState {
  const PushIdle();
}

final class PushEnabled extends PushState {
  const PushEnabled();
}

/// The OS refused, or the user did. Not an error: the app works and
/// reminders simply do not arrive.
final class PushDenied extends PushState {
  const PushDenied();
}

final class PushFailed extends PushState {
  const PushFailed(this.message);
  final String message;
}
