import 'package:birthday_app/features/push/notification_permission_cubit.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repositories/push_repository_test.dart' show FakePush;

void main() {
  test('check reports what the OS allows, without prompting', () async {
    final push = FakePush(status: PushPermission.denied);
    final cubit = NotificationPermissionCubit(push);

    await cubit.check();

    expect(cubit.state, PushPermission.denied);
    expect(push.permissionCalls, 0);
  });

  test('turning it on in settings registers the device on the way back',
      () async {
    final push = FakePush(status: PushPermission.blocked);
    final cubit = NotificationPermissionCubit(push);
    await cubit.check();

    // The user flips it on in the OS settings page and comes back.
    push.status = PushPermission.granted;
    await cubit.check();

    expect(cubit.state, PushPermission.granted);
    expect(push.registerCalls, 1);
  });

  test('a first check that finds it granted registers nothing extra',
      () async {
    final push = FakePush(status: PushPermission.granted);
    await NotificationPermissionCubit(push).check();
    expect(push.registerCalls, 0, reason: 'PushCubit already did on arrival');
  });

  test('Turn on, while the OS can still prompt, prompts and registers',
      () async {
    final push = FakePush(granted: true, status: PushPermission.denied);
    final cubit = NotificationPermissionCubit(push);
    await cubit.check();

    await cubit.turnOn();

    expect(push.permissionCalls, 1);
    expect(push.registerCalls, 1);
    expect(push.openSettingsCalls, 0);
    expect(cubit.state, PushPermission.granted);
  });

  test('Turn on, once the OS will never prompt, opens settings instead',
      () async {
    final push = FakePush(status: PushPermission.blocked);
    final cubit = NotificationPermissionCubit(push);
    await cubit.check();

    await cubit.turnOn();

    expect(push.openSettingsCalls, 1);
    expect(push.permissionCalls, 0);
  });
}
