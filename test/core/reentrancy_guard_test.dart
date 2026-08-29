import 'dart:async';

import 'package:birthday_app/core/reentrancy_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class _Subject with ReentrancyGuard {
  int calls = 0;
  final _completers = <String, Completer<void>>{};

  Future<void> run(String key) => guard(key, () async {
        calls++;
        _completers[key] = Completer<void>();
        await _completers[key]!.future;
      });

  /// `guard` is @protected, so a test must not call it directly — the analyzer
  /// raises invalid_use_of_protected_member and `flutter analyze` must stay
  /// clean. Drive the mixin through this class's own methods instead.
  Future<void> runThrowing(String key) =>
      guard(key, () async => throw StateError('boom'));

  void finish(String key) => _completers[key]?.complete();
}

void main() {
  test('a second call with the same key while in flight is ignored', () async {
    final s = _Subject();
    final first = s.run('a');
    final second = s.run('a');
    s.finish('a');
    await Future.wait([first, second]);
    expect(s.calls, 1);
  });

  // The whole reason this mixin uses a keyed Set rather than one flag: a
  // double-tap on one row must not fire twice, but must not block a
  // legitimate action on a different row fired in the same instant.
  test('different keys run concurrently', () async {
    final s = _Subject();
    final a = s.run('a');
    final b = s.run('b');
    expect(s.calls, 2);
    s.finish('a');
    s.finish('b');
    await Future.wait([a, b]);
  });

  test('the key is released when the body throws', () async {
    final s = _Subject();
    await expectLater(s.runThrowing('a'), throwsStateError);
    expect(s.isInFlight('a'), isFalse);
  });

  // The gap this exists to close: the flag must be set BEFORE the first
  // await, or two synchronous taps both pass the check.
  test('the key is claimed synchronously, before the first await', () {
    final s = _Subject();
    s.run('a');
    expect(s.isInFlight('a'), isTrue);
  });
}
