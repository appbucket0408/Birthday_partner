import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../repositories/push_repository.dart';
import 'push_state.dart';

class PushCubit extends Cubit<PushState> {
  PushCubit(this._push) : super(const PushIdle());
  final PushRepository _push;

  // Claimed synchronously, before the first await -- a double arrival at the
  // timeline must not fire two permission prompts.
  bool _inFlight = false;

  /// Safe to call on every arrival at the timeline. Re-asking is what lets
  /// a user who denied, then enabled notifications in Android settings,
  /// actually start receiving reminders -- on Android 13+ a second
  /// requestPermission() after the OS-level grant resolves true without a
  /// prompt, so this costs nothing in the common case.
  Future<void> enable() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      // Ask the OS what it already thinks BEFORE prompting. This cubit is
      // constructed fresh on every arrival at the timeline, so prompting
      // unconditionally would spend the user's second and final
      // POST_NOTIFICATIONS refusal within seconds of the first, and Android
      // 13+ then auto-denies permanently. Re-running enable() must be free.
      final status = await _push.currentPermission();
      // blocked as much as denied: neither may be prompted for unasked.
      if (status == PushPermission.denied ||
          status == PushPermission.blocked) {
        emit(const PushDenied());
        return;
      }
      // Already granted -- typically the user turned it on in OS settings
      // after refusing here. Register without showing anything.
      if (status == PushPermission.notDetermined) {
        final granted = await _push.requestPermission();
        if (!granted) {
          emit(const PushDenied());
          return;
        }
      }
      await _push.registerThisDevice();
      emit(const PushEnabled());
    } on AppFailure catch (f) {
      emit(PushFailed(f.message));
    } catch (_) {
      emit(const PushFailed(AppStrings.somethingWentWrong));
    } finally {
      _inFlight = false;
    }
  }
}
