import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/moderation_repository.dart';
import 'blocked_users_state.dart';

class BlockedUsersCubit extends Cubit<BlockedUsersState> with ReentrancyGuard {
  BlockedUsersCubit(this._moderation) : super(const BlockedUsersLoading());
  final ModerationRepository _moderation;

  Future<void> load() => guard('load', () async {
        emit(const BlockedUsersLoading());
        try {
          emit(BlockedUsersLoaded(await _moderation.blockedUsers()));
        } on AppFailure catch (f) {
          emit(BlockedUsersError(f.message));
        } catch (_) {
          emit(const BlockedUsersError(AppStrings.somethingWentWrong));
        }
      });

  /// Returns whether it worked, for the screen's snackbar. Keyed per
  /// profile: a double tap on one row is one write, but two rows can be
  /// unblocked at once.
  Future<bool> unblock(String profileId) async {
    var ok = false;
    await guard('unblock:$profileId', () async {
      final current = state;
      if (current is! BlockedUsersLoaded) return;
      emit(BlockedUsersLoaded(
        current.users,
        unblocking: {...current.unblocking, profileId},
      ));
      try {
        await _moderation.unblock(profileId);
        ok = true;
      } on AppFailure catch (f) {
        _settle(profileId, removed: false, error: f.message);
        return;
      } catch (_) {
        _settle(profileId, removed: false, error: AppStrings.somethingWentWrong);
        return;
      }
      _settle(profileId, removed: true);
    });
    return ok;
  }

  // Re-reads state after the await: another row's unblock may have changed
  // the list in the meantime.
  void _settle(String profileId, {required bool removed, String? error}) {
    final current = state;
    if (current is! BlockedUsersLoaded) return;
    emit(BlockedUsersLoaded(
      removed
          ? current.users.where((u) => u.profileId != profileId).toList()
          : current.users,
      unblocking: {...current.unblocking}..remove(profileId),
      error: error,
    ));
  }
}
