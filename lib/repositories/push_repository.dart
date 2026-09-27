/// The device-token lifecycle. Extracted from [SettingsRepository], which
/// carried `deleteThisDeviceToken` together with a hardcoded
/// `String? get _currentDeviceToken => null` -- settings triggers one end of
/// this lifecycle but does not own it.
/// What the OS currently reports, BEFORE any prompt is shown.
enum PushPermission {
  /// Never asked. The only state in which a prompt may be shown.
  notDetermined,
  granted,

  /// Refused, either by the user or permanently by the OS. Asking again is
  /// actively harmful on Android 13+: the SECOND refusal of
  /// POST_NOTIFICATIONS makes the permission permanently auto-denied, and
  /// the only recovery is OS settings.
  denied,
}

abstract interface class PushRepository {
  /// What the OS reports now, without prompting. Callers use this to decide
  /// whether asking is even allowed.
  Future<PushPermission> currentPermission();

  /// Asks the OS for notification permission. Android 13+ treats
  /// POST_NOTIFICATIONS as a runtime permission; below 13 this resolves true
  /// without a prompt. A false result is not an error: the app works, and
  /// reminders simply do not arrive.
  Future<bool> requestPermission();

  /// Reads the FCM token and calls `register_device_token(p_token,
  /// p_platform)`. Safe to call repeatedly: the function deletes any prior
  /// row holding that token before inserting, so a reinstall or a
  /// handed-down phone reassigns cleanly.
  Future<void> registerThisDevice();

  /// Deletes this device's row. MUST be called BEFORE the session is
  /// cleared: once it is gone, `device_tokens_all_own` scopes the row to an
  /// `auth.uid()` this client no longer has, and the delete silently
  /// affects nothing while the device keeps receiving the previous user's
  /// reminders.
  Future<void> deleteThisDeviceToken();

  /// Routes from notifications tapped while the app was running.
  Stream<String> get notificationRoutes;

  /// The route from a notification that launched the app from terminated,
  /// or null. Separate from [notificationRoutes] because the tap happened
  /// before anything could subscribe.
  Future<String?> initialRoute();
}
