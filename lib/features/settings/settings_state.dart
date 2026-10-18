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
final class SettingsLoaded extends SettingsState {
  const SettingsLoaded({
    required this.remindersEnabled,
    this.wishNotificationsEnabled = true,
    this.savingReminders = false,
    this.savingWishNotifications = false,
    this.error,
  });

  final bool remindersEnabled;
  final bool wishNotificationsEnabled;
  final bool savingReminders;
  final bool savingWishNotifications;
  final String? error;
  SettingsLoaded copyWith({
    bool? remindersEnabled,
    bool? wishNotificationsEnabled,
    bool? savingReminders,
    bool? savingWishNotifications,
    String? error,
  }) =>
      SettingsLoaded(
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        wishNotificationsEnabled:
            wishNotificationsEnabled ?? this.wishNotificationsEnabled,
        savingReminders: savingReminders ?? this.savingReminders,
        savingWishNotifications:
            savingWishNotifications ?? this.savingWishNotifications,
        error: error,
      );
}
final class SettingsSignedOut extends SettingsState {
  const SettingsSignedOut();
}
