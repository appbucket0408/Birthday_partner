import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/gift_repository.dart';
import 'gift_list_state.dart';

/// The gift list screen's cubit (spec §7): the sender's own gifts and their
/// status, reached from the profile. One action, `load()`.
///
/// Mixes in [ReentrancyGuard] for the same reason every other cubit in this
/// phase does: a re-entrant `load()` -- the profile entry point and a
/// pull-to-refresh both firing in the same instant, say -- must not race two
/// reads against the same state.
class GiftListCubit extends Cubit<GiftListState> with ReentrancyGuard {
  /// [now] is injectable so the hold-expiry flag in [load] never depends on
  /// the real clock -- the same convention every cubit in this app follows
  /// (`ProfileCubit`, `CatalogCubit`, `SlotPickerScreen`).
  GiftListCubit(this._gifts, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const GiftListLoading());

  final GiftRepository _gifts;
  final DateTime Function() _now;

  Future<void> load() => guard('load', () async {
        emit(const GiftListLoading());
        try {
          final gifts = await _gifts.myGifts();
          final now = _now();
          final expiredIds = {
            for (final gift in gifts)
              if (gift.isHoldExpiredAt(now)) gift.id,
          };
          emit(GiftListLoaded(gifts, expiredIds));
        } on AppFailure catch (f) {
          emit(GiftListError(f.message));
        } catch (_) {
          emit(const GiftListError(AppStrings.somethingWentWrong));
        }
      });
}
