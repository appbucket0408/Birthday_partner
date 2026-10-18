abstract interface class SettingsRepository {
  /// Writes `profiles.reminders_enabled` for the signed-in user.
  Future<void> setRemindersEnabled(bool enabled);

  /// Writes `profiles.wish_notifications_enabled` for the signed-in user.
  Future<void> setWishNotificationsEnabled(bool enabled);
}
