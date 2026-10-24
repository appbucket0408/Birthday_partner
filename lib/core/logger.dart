import 'dart:developer' as developer;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// One logger. `print` is banned by analysis_options.
abstract final class Log {
  static bool _crashReporting = false;

  /// From main(), once Crashlytics is set up; errors then become non-fatals.
  static void enableCrashReporting() => _crashReporting = true;

  static void info(String message) =>
      developer.log(message, name: 'birthday');

  static void error(String message, [Object? error, StackTrace? stack]) {
    developer.log(message, name: 'birthday', error: error, stackTrace: stack);
    if (_crashReporting) {
      FirebaseCrashlytics.instance
          .recordError(error ?? message, stack, reason: message)
          .ignore();
    }
  }
}
