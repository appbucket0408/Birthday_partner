import 'dart:async';

import 'package:birthday_app/repositories/push_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake every later task reuses. Lives in the test tree, not lib/.
class FakePush implements PushRepository {
  FakePush({
    this.granted = true,
    this.status = PushPermission.notDetermined,
    this.onDelete,
  });
  bool granted;

  /// What the OS reports BEFORE any prompt. Separate from [granted],
  /// which is what a prompt would return, so a test can express
  /// "already denied" and assert no prompt was shown at all.
  PushPermission status;

  /// Lets a test record WHEN deletion happened relative to other calls, not
  /// merely that it did. The sign-out ordering test needs the order.
  final void Function()? onDelete;

  int permissionCalls = 0;
  int registerCalls = 0;
  int deleteCalls = 0;
  Object? registerError;
  Object? deleteError;
  final routes = StreamController<String>.broadcast();
  String? initial;

  @override
  Future<PushPermission> currentPermission() async => status;

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    status = granted ? PushPermission.granted : PushPermission.denied;
    return granted;
  }

  @override
  Future<void> registerThisDevice() async {
    registerCalls++;
    if (registerError != null) throw registerError!;
  }

  @override
  Future<void> deleteThisDeviceToken() async {
    deleteCalls++;
    onDelete?.call();
    if (deleteError != null) throw deleteError!;
  }

  @override
  Stream<String> get notificationRoutes => routes.stream;

  @override
  Future<String?> initialRoute() async => initial;
}

void main() {
  test('the fake satisfies the interface', () {
    expect(FakePush(), isA<PushRepository>());
  });
}
