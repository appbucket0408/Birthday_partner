import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/logger.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/delivery_slot.dart';
import '../../repositories/ops_repository.dart';
import 'ops_slots_state.dart';

/// The delivery calendar: which windows exist in an area, and how many cakes
/// each can carry.
///
/// EVERY misuse is caught before the write, and the reason is specific. On
/// this schema four different constraints raise SQLSTATE 23514 --
/// `delivery_slots_window_ordered`, `delivery_slots_not_oversold`,
/// `delivery_slots_capacity_non_negative` and `products_price_positive` --
/// because 23514 is Postgres's GENERIC check-violation code. A failure that
/// reached the database could not be told apart from three unrelated rules,
/// so the console would have to guess. This is the same overload that caused
/// M3 Phase 1b's Critical bug, where a mistyped pincode was reported as an
/// invalid gift link.
///
/// The one exception is `delivery_slots_unique_window`, which raises 23505 --
/// distinguishable, and therefore mapped to its own message.
class OpsSlotsCubit extends Cubit<OpsSlotsState> with ReentrancyGuard {
  OpsSlotsCubit(this._ops) : super(const OpsSlotsLoading());

  final OpsRepository _ops;
  OpsSlotsLoaded? _loaded;

  /// [from] and [to] come from the caller — a date the user picked — never
  /// from DateTime.now() in here. Postgres runs UTC and the host may not.
  Future<void> load({required DateTime from, required DateTime to}) =>
      guard('load', () async {
        emit(const OpsSlotsLoading());
        try {
          final areas = await _ops.allServiceAreas();
          final selected = areas.isEmpty ? null : areas.first.id;
          final slots = selected == null
              ? <DeliverySlot>[]
              : await _ops.slotsBetween(selected, from: from, to: to);

          _loaded = OpsSlotsLoaded(
            areas: areas,
            selectedAreaId: selected,
            from: from,
            to: to,
            slots: slots,
          );
          emit(_loaded!);
        } on AuthFailure catch (f) {
          emit(OpsSlotsError(f.message, sessionExpired: true));
        } on AppFailure catch (f) {
          emit(OpsSlotsError(f.message));
        } catch (_) {
          emit(const OpsSlotsError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> selectArea(int serviceAreaId) => guard('selectArea', () async {
        final current = _loaded;
        if (current == null) return;
        await _reload(current.copyWith(selectedAreaId: serviceAreaId));
      });

  Future<void> setRange({required DateTime from, required DateTime to}) =>
      guard('setRange', () async {
        final current = _loaded;
        if (current == null) return;
        await _reload(current.copyWith(from: from, to: to));
      });

  Future<void> addSlot({
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  }) =>
      guard('addSlot', () async {
        final current = _loaded;
        final areaId = current?.selectedAreaId;
        if (current == null || areaId == null) return;

        // Compared as strings deliberately: both are 'HH:mm' or 'HH:mm:ss'
        // from the same picker, and lexicographic order on a zero-padded
        // 24-hour clock is chronological order.
        if (windowEnd.compareTo(windowStart) <= 0) {
          emit(const OpsSlotsError(AppStrings.opsWindowOrder));
          return;
        }
        if (capacity < 0) {
          emit(const OpsSlotsError(AppStrings.opsCapacityNegative));
          return;
        }

        try {
          await _ops.createSlot(
            serviceAreaId: areaId,
            slotDate: slotDate,
            windowStart: windowStart,
            windowEnd: windowEnd,
            capacity: capacity,
          );
          await _reload(current);
        } on AppFailure catch (f) {
          _emitFailure(f);
        } catch (_) {
          emit(const OpsSlotsError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> changeCapacity(int slotId, {required int capacity}) =>
      guard('changeCapacity:$slotId', () async {
        final current = _loaded;
        if (current == null) return;

        if (capacity < 0) {
          emit(const OpsSlotsError(AppStrings.opsCapacityNegative));
          return;
        }

        final slot = current.slots.where((s) => s.id == slotId).firstOrNull;
        // `reserved <= capacity` is enforced by delivery_slots_not_oversold,
        // so this check is not the only guard -- it exists so the user reads
        // a sentence naming the real count instead of a bare 23514.
        if (slot != null && capacity < slot.reserved) {
          emit(OpsSlotsError(
            AppStrings.opsCapacityBelowReservedTemplate
                .replaceFirst('%s', '${slot.reserved}'),
          ));
          return;
        }

        try {
          await _ops.setSlotCapacity(slotId, capacity: capacity);
          await _reload(current);
        } on AppFailure catch (f) {
          _emitFailure(f);
        } catch (_) {
          emit(const OpsSlotsError(AppStrings.somethingWentWrong));
        }
      });

  /// The screen parses the typed date and calls this when it cannot. Kept
  /// on the cubit so the refusal lands in the same state the rest of the
  /// validations use, rather than the screen growing a second error channel.
  void rejectDate() => emit(const OpsSlotsError(AppStrings.opsDateInvalid));

  Future<void> _reload(OpsSlotsLoaded base) async {
    final areaId = base.selectedAreaId;
    if (areaId == null) {
      _loaded = base;
      emit(base);
      return;
    }
    final slots =
        await _ops.slotsBetween(areaId, from: base.from, to: base.to);
    _loaded = base.copyWith(slots: slots);
    emit(_loaded!);
  }

  void _emitFailure(AppFailure f) {
    // The session is gone, not merely this request. Flagged so the screen
    // can route back to sign-in instead of offering a retry that cannot
    // succeed.
    if (f is AuthFailure) {
      emit(OpsSlotsError(f.message, sessionExpired: true));
      return;
    }
    // 23505 is unique_violation -- the ONE constraint on this table with a
    // code of its own, so it gets a message of its own.
    if (f is ServerFailure && f.code == '23505') {
      emit(const OpsSlotsError(AppStrings.opsDuplicateWindow));
      return;
    }
    // Anything else, 23514 included, is rendered as its own message and
    // LOGGED. Deliberately not mapped to a guess: four constraints share
    // that code, so naming one would be wrong three times out of four.
    if (f is ServerFailure && f.code == '23514') {
      Log.error('ops: unexpected 23514 on a slot write', f);
    }
    emit(OpsSlotsError(f.message));
  }
}
