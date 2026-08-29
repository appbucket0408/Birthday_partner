sealed class SettingsState {
  const SettingsState();
}

final class SettingsLoading extends SettingsState {
  const SettingsLoading();
}

final class SettingsLoadError extends SettingsState {
  const SettingsLoadError(this.message);
  final String message;
}

/// [remindersEnabled] is the last-known-good value -- the switch reflects
/// it, never an in-flight guess. [savingReminders] is true only while a
/// toggle write is in flight, so the switch can show a spinner without
/// changing what value it displays. [error] is a transient message from the
/// last action (toggle/signOut/deleteAccount) that failed; it does not blank
/// the screen, since [remindersEnabled] is still the last-known-good value
/// -- mirrors TimelineLoaded.error.
final class SettingsLoaded extends SettingsState {
  const SettingsLoaded({
    required this.remindersEnabled,
    this.savingReminders = false,
    this.error,
  });

  final bool remindersEnabled;
  final bool savingReminders;
  final String? error;
}

/// Sign-out or account deletion succeeded and the local session is gone.
/// Terminal for this cubit: the screen's listener reacts to this exactly
/// once by notifying SessionCubit, mirroring PhoneVerified/
/// ProfileSetupDone -- SessionCubit is the single source of truth for
/// routing, and this cubit has no reference to it.
final class SettingsSignedOut extends SettingsState {
  const SettingsSignedOut();
}
