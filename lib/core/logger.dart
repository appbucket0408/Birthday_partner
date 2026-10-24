import 'dart:developer' as developer;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'analytics.dart';

/// One logger. `print` is banned by analysis_options.
abstract final class Log {
  static void info(String message) =>
      developer.log(message, name: 'birthday');

  static void error(String message, [Object? error, StackTrace? stack]) {
    developer.log(message, name: 'birthday', error: error, stackTrace: stack);
    if (Analytics.enabled) {
      FirebaseCrashlytics.instance
          .recordError(error ?? message, stack, reason: message)
          .ignore();
    }
  }
}
