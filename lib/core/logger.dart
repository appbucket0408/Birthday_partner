import 'dart:developer' as developer;

/// One logger. `print` is banned by analysis_options.
abstract final class Log {
  static void info(String message) =>
      developer.log(message, name: 'birthday');

  static void error(String message, [Object? error, StackTrace? stack]) =>
      developer.log(message, name: 'birthday', error: error, stackTrace: stack);
}
