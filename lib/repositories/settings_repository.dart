/// Everything the Settings screen (spec §6.4) needs beyond identity, which
/// AuthRepository already owns end to end (signOut/deleteAccount stay
/// there -- SettingsCubit composes both repositories rather than this one
/// growing identity concerns).
abstract interface class SettingsRepository {
  /// Writes `profiles.reminders_enabled` for the signed-in user.
  Future<void> setRemindersEnabled(bool enabled);

  /// Deletes this device's row from `device_tokens`, if one exists.
  ///
  /// Push registration is stubbed until Phase 2c, so no client ever has a
  /// registered token today -- this is the ONLY path through this method
  /// that exists in Phase 2b. It MUST be a guarded no-op rather than a stub
  /// that throws: [SettingsCubit.signOut] depends on this succeeding on
  /// every sign-out, and a signed-out device that keeps its token keeps
  /// receiving someone else's birthday reminders.
  Future<void> deleteThisDeviceToken();
}
