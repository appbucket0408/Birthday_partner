import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/push_repository.dart';
import '../../repositories/settings_repository.dart';
import 'settings_state.dart';

/// Settings (spec §6.4): the reminders toggle, sign-out and account
/// deletion. Sign-out and deletion both stay on [AuthRepository] -- this
/// cubit composes [SettingsRepository] (the reminders write and the device
/// token cleanup) with it rather than either repository growing the other's
/// concern.
///
/// Deliberately built without a [SessionCubit] reference. This cubit only
/// reports what happened ([SettingsSignedOut]); the screen is what notifies
/// SessionCubit, the same shape as PhoneCubit/ProfileSetupCubit finishing
/// and the screen telling SessionCubit to re-derive routing state.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settings, this._auth, this._push)
      : super(const SettingsLoading());

  final SettingsRepository _settings;
  final AuthRepository _auth;
  final PushRepository _push;

  // Guards re-entrancy per action, not with one flag for the whole cubit --
  // same shape as TimelineCubit._inFlight: a double-tap on "Sign out" must
  // not fire deleteThisDeviceToken() twice, but that must not also block a
  // legitimate, unrelated toggle fired in the same instant.
  final Set<String> _inFlight = {};

  Future<void> load() async {
    if (!_inFlight.add('load')) return;
    emit(const SettingsLoading());
    try {
      final profile = await _auth.loadProfile();
      emit(SettingsLoaded(remindersEnabled: profile.remindersEnabled));
    } on AppFailure catch (f) {
      emit(SettingsLoadError(f.message));
    } catch (_) {
      emit(const SettingsLoadError(AppStrings.somethingWentWrong));
    } finally {
      _inFlight.remove('load');
    }
  }

  /// Sets `profiles.reminders_enabled`, optimistically -- the switch moves
  /// immediately with [SettingsLoaded.savingReminders] true, then either
  /// settles on [enabled] or reverts to the last-known-good value if the
  /// write is rejected. A stale value left on screen after a rejected write
  /// would tell the user reminders are set the way the server actually
  /// refused them.
  Future<void> toggleReminders(bool enabled) async {
    final current = state;
    if (current is! SettingsLoaded) return;
    if (!_inFlight.add('toggle')) return;
    final previous = current.remindersEnabled;
    emit(SettingsLoaded(remindersEnabled: enabled, savingReminders: true));
    try {
      await _settings.setRemindersEnabled(enabled);
      emit(SettingsLoaded(remindersEnabled: enabled));
    } catch (_) {
      emit(
        SettingsLoaded(
          remindersEnabled: previous,
          error: AppStrings.somethingWentWrong,
        ),
      );
    } finally {
      _inFlight.remove('toggle');
    }
  }

  /// Deletes this device's token BEFORE clearing the session -- not after,
  /// and not concurrently. Once the session is gone, `device_tokens_all_own`
  /// makes the row unreachable by this client (RLS scopes it to
  /// `auth.uid()`), and a signed-out device that keeps its token keeps
  /// receiving someone else's birthday reminders. The order is the whole of
  /// what makes this method correct.
  Future<void> signOut() async {
    if (!_inFlight.add('signOut')) return;
    final current = state;
    try {
      await _push.deleteThisDeviceToken();
      await _auth.signOut();
      emit(const SettingsSignedOut());
    } catch (_) {
      if (current is SettingsLoaded) {
        emit(
          SettingsLoaded(
            remindersEnabled: current.remindersEnabled,
            error: AppStrings.somethingWentWrong,
          ),
        );
      }
    } finally {
      _inFlight.remove('signOut');
    }
  }

  /// Deletes the account. [AuthRepository.deleteAccount] is itself the
  /// two-step body (invoke the Edge Function, then sign out locally) --
  /// this cubit does not repeat that ordering, only reports the outcome.
  Future<void> deleteAccount() async {
    if (!_inFlight.add('deleteAccount')) return;
    final current = state;
    try {
      await _auth.deleteAccount();
      emit(const SettingsSignedOut());
    } catch (_) {
      if (current is SettingsLoaded) {
        emit(
          SettingsLoaded(
            remindersEnabled: current.remindersEnabled,
            error: AppStrings.somethingWentWrong,
          ),
        );
      }
    } finally {
      _inFlight.remove('deleteAccount');
    }
  }
}
