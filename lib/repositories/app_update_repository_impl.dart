import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/logger.dart';
import 'app_update_repository.dart';

class AppUpdateRepositoryImpl implements AppUpdateRepository {
  AppUpdateRepositoryImpl(this._config);
  final FirebaseRemoteConfig _config;

  /// Build numbers (the `+N` in pubspec's version), set in the Firebase
  /// console. Below the minimum the app refuses to run; below the latest it
  /// offers the update.
  static const minSupportedBuildKey = 'min_supported_build';
  static const latestBuildKey = 'latest_build';

  static const _snoozedBuildPref = 'update_snoozed_build';
  static const _snoozedAtPref = 'update_snoozed_at_ms';
  static const snoozeFor = Duration(days: 3);

  Future<PackageInfo>? _info;
  Future<PackageInfo> get _package => _info ??= PackageInfo.fromPlatform();

  @override
  Future<UpdateStatus> check() async {
    try {
      await _config.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Debug builds fetch every launch so a console change can be tried
        // at once; release builds stay inside Firebase's fetch quota.
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(hours: 1),
      ));
      await _config.setDefaults(const {
        minSupportedBuildKey: 0,
        latestBuildKey: 0,
      });
      await _config.fetchAndActivate();
    } catch (e, s) {
      // Last activated values (or the 0 defaults) still apply below.
      Log.error('remote config fetch failed', e, s);
    }
    return _status();
  }

  @override
  Stream<UpdateStatus> get statusChanges => _config.onConfigUpdated
      .where((u) =>
          u.updatedKeys.contains(minSupportedBuildKey) ||
          u.updatedKeys.contains(latestBuildKey))
      .asyncMap((_) async {
    await _config.activate();
    return _status();
  });

  Future<UpdateStatus> _status() async {
    try {
      final build = int.tryParse((await _package).buildNumber) ?? 0;
      if (build < _config.getInt(minSupportedBuildKey)) {
        return UpdateStatus.required;
      }
      final latest = _config.getInt(latestBuildKey);
      if (build < latest && !await _isSnoozed(latest)) {
        return UpdateStatus.optional;
      }
    } catch (e, s) {
      Log.error('update check failed', e, s);
    }
    return UpdateStatus.upToDate;
  }

  /// Snoozed only for the build that was put off: publishing a newer
  /// `latest_build` brings the prompt straight back.
  Future<bool> _isSnoozed(int latest) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_snoozedBuildPref) != latest) return false;
    final at = prefs.getInt(_snoozedAtPref) ?? 0;
    final since = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(at));
    return since < snoozeFor;
  }

  @override
  Future<void> snoozeOptional() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozedBuildPref, _config.getInt(latestBuildKey));
    await prefs.setInt(
      _snoozedAtPref,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> openStore() async {
    final id = (await _package).packageName;
    final opened = await launchUrl(
      Uri.parse('market://details?id=$id'),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened) {
      await launchUrl(
        Uri.parse('https://play.google.com/store/apps/details?id=$id'),
        mode: LaunchMode.externalApplication,
      );
    }
  }
}
