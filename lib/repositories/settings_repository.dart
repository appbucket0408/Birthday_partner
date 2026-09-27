/// Everything the Settings screen (spec §6.4) needs beyond identity, which
/// AuthRepository already owns end to end (signOut/deleteAccount stay
/// there -- SettingsCubit composes both repositories rather than this one
/// growing identity concerns).
///
/// The device-token lifecycle used to live here too, behind a hardcoded
/// `_currentDeviceToken => null`. It moved to PushRepository in M1 Phase 2c:
/// settings triggers one end of that lifecycle but does not own it.
abstract interface class SettingsRepository {
  /// Writes `profiles.reminders_enabled` for the signed-in user.
  Future<void> setRemindersEnabled(bool enabled);
}
