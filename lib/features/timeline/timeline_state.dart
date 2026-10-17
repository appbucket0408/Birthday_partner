import '../../models/birthday.dart';
import '../../models/celebration.dart';

sealed class TimelineState {
  const TimelineState();
}

final class TimelineLoading extends TimelineState {
  const TimelineLoading();
}

/// [groups] keys the signed-in user's celebrations by [TimelineGroup] --
/// except a `null` key, which is its own bucket for a celebration whose
/// person has no birthday at all -- someone not on the app yet, since only a
/// person sets their own birthday. The reminder fan-out skips them (there is
/// nothing to remind about), but they are still someone this user
/// celebrates, so they stay listed.
///
/// [error] is a transient message from the last row action
/// (stopCelebrating) that failed -- not a reason to
/// blank the screen, since [groups] is still the last-known-good list. A
/// later successful action clears it (see [TimelineCubit._emitGrouped]).
final class TimelineLoaded extends TimelineState {
  const TimelineLoaded(this.groups, {this.error});

  final Map<TimelineGroup?, List<Celebration>> groups;
  final String? error;
}

/// Distinct from `TimelineLoaded({})`: an empty edge list is a different
/// screen (the import-contacts pitch), not a loaded list that happens to be
/// empty.
final class TimelineEmpty extends TimelineState {
  const TimelineEmpty();
}

final class TimelineError extends TimelineState {
  const TimelineError(this.message);

  final String message;
}
