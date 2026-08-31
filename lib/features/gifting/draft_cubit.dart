import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/gift_repository.dart';
import 'draft_state.dart';

/// The draft screen's cubit (spec §7): one action, `create`, that reserves a
/// slot for fifteen minutes and leaves the sender at an honest dead end --
/// checkout does not exist yet.
///
/// **`occasionDate` is a required argument, never derived here (Amendment
/// B1).** The brief this task started from had this cubit take a `Birthday`
/// and call `Birthday.nextOccurrence` on an injected clock, the same way
/// `SlotPickerScreen` does. That is wrong: `SlotPickerScreen` already
/// computes `birthday.nextOccurrence(now())` once and filters its slots to
/// exactly that calendar day. A second, independent derivation here could
/// disagree with the first -- a session crossing midnight between the two
/// screens is enough -- and nothing server-side would catch it:
/// `private.create_gift` checks the sender, self-gift, product-active, and
/// the slot's area and capacity, but there is deliberately no
/// `slot_date = p_occasion_date` constraint (spec §11, open question 1). So
/// the client is the only guard against a cake dated one day and a van slot
/// booked for another, and it can only be a reliable one if there is a
/// single source of truth. Taking `occasionDate` as a plain argument, with
/// no `Birthday` and no injectable clock for this purpose, makes the two
/// dates structurally unable to diverge -- there is nothing left here to
/// derive from.
class DraftCubit extends Cubit<DraftState> with ReentrancyGuard {
  DraftCubit(this._gifts) : super(const DraftIdle());

  final GiftRepository _gifts;

  /// Reserves [slotId] for [recipientPersonId], dated [occasionDate] --
  /// handed down verbatim from wherever it was computed, never recomputed
  /// here (see the class doc).
  ///
  /// Guarded by [ReentrancyGuard]: a double-tap on "Reserve this slot" burns
  /// real van capacity, not merely a duplicate row, so a second call while
  /// the first is in flight is dropped rather than queued or replacing the
  /// first.
  Future<void> create({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) =>
      guard('create', () async {
        emit(const DraftSaving());
        try {
          final gift = await _gifts.createDraft(
            recipientPersonId: recipientPersonId,
            productId: productId,
            slotId: slotId,
            occasionDate: occasionDate,
            message: message,
          );
          emit(DraftCreated(gift));
        } on AppFailure catch (f) {
          // 23514 and 45005 are real SQLSTATEs `private.create_gift` raises
          // (see `GiftRepository.createDraft`'s doc) and each needs its own
          // actionable message, not the generic ServerFailure text: two
          // users racing for the last slot, and a sender aimed at someone
          // they do not celebrate, are both legitimate outcomes a user can
          // act on differently, not faults to apologise for identically.
          if (f is ServerFailure && f.code == '23514') {
            emit(const DraftError(AppStrings.giftSlotJustFilled, slotFull: true));
          } else if (f is ServerFailure && f.code == '45005') {
            emit(const DraftError(AppStrings.giftNotCelebrating));
          } else {
            emit(DraftError(f.message));
          }
        } catch (_) {
          emit(const DraftError(AppStrings.somethingWentWrong));
        }
      });
}
