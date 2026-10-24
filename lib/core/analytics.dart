import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'logger.dart';

/// No-op until [enable]d in main.dart, so tests and the ops console skip it.
abstract final class Analytics {
  static bool _enabled = false;
  static bool get enabled => _enabled;

  static void enable() => _enabled = true;

  static FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  static Future<void> setUser(String? id) async {
    if (!_enabled) return;
    await _guard(() async {
      await _fa.setUserId(id: id);
      await FirebaseCrashlytics.instance.setUserIdentifier(id ?? '');
    });
  }

  static Future<void> signUp() =>
      _guard(() => _fa.logSignUp(signUpMethod: 'phone'));

  static Future<void> contactsImported(int added) => _log(
        'contacts_imported',
        {'added': added},
      );

  /// [source]: the screen the invite was shared from.
  static Future<void> inviteSent(String source) =>
      _log('invite_sent', {'source': source});

  static Future<void> wishPosted({required bool withPhoto}) =>
      _log('wish_posted', {'with_photo': withPhoto ? 1 : 0});

  static Future<void> _log(String name, Map<String, Object> params) =>
      _guard(() => _fa.logEvent(name: name, parameters: params));

  static Future<void> _guard(Future<void> Function() call) async {
    if (!_enabled) return;
    try {
      await call();
    } catch (e, s) {
      Log.error('analytics failed', e, s);
    }
  }
}
