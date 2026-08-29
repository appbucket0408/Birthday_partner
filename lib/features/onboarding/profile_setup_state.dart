sealed class ProfileSetupState {
  const ProfileSetupState();
}

final class ProfileSetupIdle extends ProfileSetupState {
  const ProfileSetupIdle();
}

final class ProfileSetupSaving extends ProfileSetupState {
  const ProfileSetupSaving();
}

final class ProfileSetupDone extends ProfileSetupState {
  const ProfileSetupDone();
}

/// [handleTaken] decides whether the message is attached to the handle field
/// or shown as a general failure. Attributing an unrelated outage to the
/// username sends the user off renaming themselves for no reason.
final class ProfileSetupError extends ProfileSetupState {
  const ProfileSetupError(this.message, {this.handleTaken = false});
  final String message;
  final bool handleTaken;
}
