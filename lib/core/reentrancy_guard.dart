import 'package:flutter/foundation.dart';

/// One place for the re-entrancy guard every cubit in this app needs.
///
/// Phase 2b grew five of these in three different shapes -- a state check in
/// PhoneCubit and ProfileSetupCubit, a bool in ImportCubit, a keyed Set in
/// TimelineCubit and SettingsCubit -- each rediscovered in review. This is the
/// keyed-Set form, which was the best of them: a double-tap on one row must not
/// fire two writes, but must not block a legitimate action on a different row
/// fired in the same instant.
///
/// A state check is NOT sufficient and must not be substituted. The state a
/// cubit emits to mark "in flight" is often emitted after the first await --
/// ImportCubit.commit does not emit ImportCommitting until the first progress
/// callback -- and that window is exactly where the double-tap lands.
///
/// Phase 2b's cubits are deliberately NOT converted to this mixin. It is
/// written so they could be, one at a time, later.
mixin ReentrancyGuard {
  final Set<String> _inFlight = {};

  /// Runs [body] unless [key] is already in flight.
  ///
  /// The key is claimed synchronously, before [body] is ever awaited, and
  /// released in a `finally` so a throwing body cannot strand it.
  @protected
  Future<void> guard(String key, Future<void> Function() body) async {
    if (!_inFlight.add(key)) return;
    try {
      await body();
    } finally {
      _inFlight.remove(key);
    }
  }

  @visibleForTesting
  bool isInFlight(String key) => _inFlight.contains(key);
}
