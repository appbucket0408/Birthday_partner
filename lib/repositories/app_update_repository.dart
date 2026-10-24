/// Where this build stands against Remote Config.
enum UpdateStatus {
  /// At or above `latest_build`, or a newer build was put off for now.
  upToDate,

  /// Below `latest_build`: offer the update, let the user carry on.
  optional,

  /// Below `min_supported_build`: the app cannot be used until updated.
  required,
}

abstract interface class AppUpdateRepository {
  /// Fetches Remote Config and rates this build. Never throws: a failed
  /// fetch falls back to the last values fetched, and with none, to
  /// [UpdateStatus.upToDate] -- a flaky network must not lock anyone out.
  Future<UpdateStatus> check();

  /// Emits whenever a config change is pushed while the app is open, so a
  /// raised minimum takes effect without a restart.
  Stream<UpdateStatus> get statusChanges;

  /// "Later" on the optional prompt: hides it for a few days, unless a
  /// newer `latest_build` is published in the meantime.
  Future<void> snoozeOptional();

  /// Opens this app's store page (Play Store app, else the web page).
  Future<void> openStore();
}
