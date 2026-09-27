import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/push/push_cubit.dart';
import 'package:birthday_app/features/push/push_state.dart';
import 'package:birthday_app/repositories/push_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repositories/push_repository_test.dart' show FakePush;

void main() {
  test('1. granted permission registers the device', () async {
    final push = FakePush(granted: true);
    final cubit = PushCubit(push);

    await cubit.enable();

    expect(push.permissionCalls, 1);
    expect(push.registerCalls, 1);
    expect(cubit.state, isA<PushEnabled>());
  });

  test('2. a denial does NOT register, and is not an error state', () async {
    final push = FakePush(granted: false);
    final cubit = PushCubit(push);

    await cubit.enable();

    // Registering a token the OS will never deliver to would create a row
    // that satisfies next_reminder_batch's `exists` check, so reminders
    // would be claimed and burned against a device that cannot receive.
    expect(push.registerCalls, 0);
    expect(cubit.state, isA<PushDenied>());
  });

  test('3. a denial followed by a later grant DOES register', () async {
    // Review Focus 4: the user denies, then turns notifications on in
    // Android settings and comes back. Nothing re-runs registration
    // unless enable() is safe to call again and actually re-asks.
    final push = FakePush(granted: false);
    final cubit = PushCubit(push);
    await cubit.enable();
    expect(cubit.state, isA<PushDenied>());

    // The user turns notifications on in Android settings and comes back.
    push.status = PushPermission.granted;
    await cubit.enable();

    expect(push.registerCalls, 1);
    expect(cubit.state, isA<PushEnabled>());
  });

  test('4. a registration failure surfaces without losing the grant',
      () async {
    final push = FakePush(granted: true)
      ..registerError = const OfflineFailure('no connection');
    final cubit = PushCubit(push);

    await cubit.enable();

    expect(cubit.state, isA<PushFailed>());
    expect((cubit.state as PushFailed).message, 'no connection');
  });

  test('5. a second enable() while the first is in flight is ignored',
      () async {
    final push = FakePush(granted: true);
    final cubit = PushCubit(push);

    // Both fired WITHOUT awaiting the first: the guard is claimed
    // synchronously, so awaiting would release it and prove nothing.
    final first = cubit.enable();
    final second = cubit.enable();
    await Future.wait([first, second]);

    expect(push.permissionCalls, 1);
  });

  test('6. an ALREADY-DENIED user is never prompted a second time', () async {
    // Review finding I10. Android 13 permanently auto-denies
    // POST_NOTIFICATIONS after the SECOND refusal, and PushCubit is
    // constructed fresh on every timeline arrival. Re-prompting
    // unconditionally therefore spends the user's last strike within
    // seconds of the first -- after which the only recovery is OS settings,
    // which is exactly the state test 3 exists to escape.
    final push = FakePush(granted: false, status: PushPermission.denied);
    final cubit = PushCubit(push);

    await cubit.enable();

    expect(push.permissionCalls, 0, reason: 'no prompt may be shown');
    expect(push.registerCalls, 0);
    expect(cubit.state, isA<PushDenied>());
  });

  test('7. an ALREADY-GRANTED user registers without a prompt', () async {
    final push = FakePush(status: PushPermission.granted);
    final cubit = PushCubit(push);

    await cubit.enable();

    expect(push.permissionCalls, 0);
    expect(push.registerCalls, 1);
    expect(cubit.state, isA<PushEnabled>());
  });
}
