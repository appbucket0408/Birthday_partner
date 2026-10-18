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
      emit(
        SettingsLoaded(
          remindersEnabled: profile.remindersEnabled,
          wishNotificationsEnabled: profile.wishNotificationsEnabled,
        ),
      );
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
    emit(current.copyWith(remindersEnabled: enabled, savingReminders: true));
    try {
      await _settings.setRemindersEnabled(enabled);
      emit(_loaded.copyWith(remindersEnabled: enabled, savingReminders: false));
    } catch (_) {
      emit(
        _loaded.copyWith(
          remindersEnabled: previous,
          savingReminders: false,
          error: AppStrings.somethingWentWrong,
        ),
      );
    } finally {
      _inFlight.remove('toggle');
    }
  }

  Future<void> toggleWishNotifications(bool enabled) async {
    final current = state;
    if (current is! SettingsLoaded) return;
    if (!_inFlight.add('toggleWish')) return;
    final previous = current.wishNotificationsEnabled;
    emit(
      current.copyWith(
        wishNotificationsEnabled: enabled,
        savingWishNotifications: true,
      ),
    );
    try {
      await _settings.setWishNotificationsEnabled(enabled);
      emit(
        _loaded.copyWith(
          wishNotificationsEnabled: enabled,
          savingWishNotifications: false,
        ),
      );
    } catch (_) {
      emit(
        _loaded.copyWith(
          wishNotificationsEnabled: previous,
          savingWishNotifications: false,
          error: AppStrings.somethingWentWrong,
        ),
      );
    } finally {
      _inFlight.remove('toggleWish');
    }
  }

  SettingsLoaded get _loaded => state as SettingsLoaded;

  Future<void> signOut() async {
    if (!_inFlight.add('signOut')) return;
    final current = state;
    try {
      await _push.deleteThisDeviceToken();
      await _auth.signOut();
      emit(const SettingsSignedOut());
    } catch (_) {
      if (current is SettingsLoaded) {
        emit(current.copyWith(error: AppStrings.somethingWentWrong));
      }
    } finally {
      _inFlight.remove('signOut');
    }
  }

  Future<void> deleteAccount() async {
    if (!_inFlight.add('deleteAccount')) return;
    final current = state;
    try {
      await _auth.deleteAccount();
      emit(const SettingsSignedOut());
    } catch (_) {
      if (current is SettingsLoaded) {
        emit(current.copyWith(error: AppStrings.somethingWentWrong));
      }
    } finally {
      _inFlight.remove('deleteAccount');
    }
  }
}
