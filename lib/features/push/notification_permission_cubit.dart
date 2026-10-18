import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logger.dart';
import '../../repositories/push_repository.dart';

/// What the OS currently allows, for the Notifications-off banner. `null`
/// until the first check, so the banner never flashes on screen while it is
/// still unknown.
///
/// PushCubit asks once, on arrival at the Dashboard, and then deliberately
/// never again (a second refusal is permanent on Android 13+). Without this,
/// a user who refused -- or whose permission a reinstall reset -- had no way
/// to find out reminders had stopped, and no way back from inside the app.
class NotificationPermissionCubit extends Cubit<PushPermission?> {
  NotificationPermissionCubit(this._push) : super(null);

  final PushRepository _push;
  bool _inFlight = false;

  /// Re-read the OS state: on open, and whenever the app resumes (the user
  /// may be back from the settings page). Turning it on registers the device
  /// at once, rather than waiting for the next visit to the Dashboard.
  Future<void> check() async {
    try {
      final before = state;
      final now = await _push.currentPermission();
      if (isClosed) return;
      emit(now);
      if (now == PushPermission.granted &&
          before != null &&
          before != PushPermission.granted) {
        await _register();
      }
    } catch (e, s) {
      Log.error('reading notification permission failed', e, s);
    }
  }

  /// The banner's button: the only place a prompt is shown on a user's tap
  /// rather than unasked, which is what makes a second ask acceptable here.
  /// Once the OS will not prompt any more ([PushPermission.blocked]), the
  /// settings page is the only way, and [check] notices on the way back.
  Future<void> turnOn() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      if (state == PushPermission.blocked) {
        await _push.openNotificationSettings();
        return;
      }
      final granted = await _push.requestPermission();
      if (granted) await _register();
      final now = await _push.currentPermission();
      if (!isClosed) emit(now);
    } catch (e, s) {
      Log.error('turning notifications on failed', e, s);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _register() async {
    try {
      await _push.registerThisDevice();
    } catch (e, s) {
      Log.error('registering after permission grant failed', e, s);
    }
  }
}
