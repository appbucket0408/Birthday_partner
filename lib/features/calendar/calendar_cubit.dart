import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/graph_repository.dart';
import 'calendar_state.dart';

/// The Calendar tab: the signed-in user's celebrations laid out on a month
/// grid, and the people whose birthday falls on the selected day.
///
/// Reads the same `GraphRepository.celebrations()` list the timeline does, so
/// the two tabs can never disagree about who is followed. Which date a
/// birthday lands on comes from `Birthday.inYear`, so a Feb 29 birthday is
/// marked on Feb 28 in a non-leap year, matching the timeline and reminders.
class CalendarCubit extends Cubit<CalendarState> with ReentrancyGuard {
  /// [now] is injectable for the same reason as [TimelineCubit]'s: the
  /// opening month and the default selection are both "today".
  CalendarCubit(this._repo, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const CalendarLoading());

  final GraphRepository _repo;
  final DateTime Function() _now;

  Future<void> load() => guard('load', () async {
        emit(const CalendarLoading());
        try {
          final celebrations = await _repo.celebrations();
          final now = _now();
          final today = DateTime(now.year, now.month, now.day);
          emit(
            CalendarLoaded(
              celebrations: celebrations,
              month: DateTime(today.year, today.month),
              selected: today,
            ),
          );
        } on AppFailure catch (f) {
          emit(CalendarError(f.message));
        } catch (_) {
          emit(const CalendarError(AppStrings.somethingWentWrong));
        }
      });

  /// Re-reads the celebrations without the loading state, keeping the month
  /// and day the user is looking at -- for when the tab is opened again
  /// after people were added or removed elsewhere. A failure keeps what is
  /// on screen.
  Future<void> refresh() => guard('load', () async {
        if (state is! CalendarLoaded) return;
        try {
          final celebrations = await _repo.celebrations();
          final s = state;
          if (s is CalendarLoaded) {
            emit(CalendarLoaded(
              celebrations: celebrations,
              month: s.month,
              selected: s.selected,
            ));
          }
        } catch (_) {
          // Keep the last good calendar.
        }
      });

  /// Moves the grid by [delta] months. `DateTime` normalises month 0 and 13
  /// into the neighbouring year, so December + 1 is January of the next.
  void changeMonth(int delta) {
    final s = state;
    if (s is! CalendarLoaded) return;
    emit(s.copyWith(month: DateTime(s.month.year, s.month.month + delta)));
  }

  /// Selects [day] and shows its month -- the empty day's "Next: ..." jump.
  void show(DateTime day) {
    final s = state;
    if (s is! CalendarLoaded) return;
    emit(s.copyWith(
      month: DateTime(day.year, day.month),
      selected: DateTime(day.year, day.month, day.day),
    ));
  }

  /// Back to this month, with today selected.
  void goToToday() => show(_now());

  void select(DateTime day) {
    final s = state;
    if (s is! CalendarLoaded) return;
    emit(s.copyWith(selected: DateTime(day.year, day.month, day.day)));
  }
}
