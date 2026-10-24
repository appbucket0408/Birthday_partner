import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../models/celebration.dart';
import '../../repositories/graph_repository.dart';
import 'timeline_state.dart';

/// The Celebrating timeline (spec §6.3): groups the signed-in user's
/// celebrations by how soon each birthday falls, and carries the three row
/// actions the screen exposes.
class TimelineCubit extends Cubit<TimelineState> {
  /// [now] is injectable so tests never depend on the real clock -- a
  /// grouping test built against `DateTime.now()` passes in April and fails
  /// in October. Production leaves it unset and gets the real clock.
  TimelineCubit(this._repo, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const TimelineLoading());

  final GraphRepository _repo;
  final DateTime Function() _now;

  // The working copy the row action mutates locally instead of re-fetching --
  // stopCelebrating must remove its row "without a full reload" per the
  // task brief.
  List<Celebration> _celebrations = const [];

  // Who celebrates the viewer back. Only a label: a failed lookup leaves it
  // empty rather than failing the timeline.
  Set<int> _celebratesMe = const {};

  // Guards re-entrancy per (action, id) pair rather than with one flag for
  // the whole cubit: a double-tap on one row's "Stop celebrating" must not
  // fire two DELETEs, but that must not also block a legitimate edit on a
  // different row fired in the same instant. Same shape as
  // PhoneCubit.submitCode, ProfileSetupCubit.submit and ImportCubit.commit --
  // a synchronous flag set before the first await, cleared in a finally.
  final Set<String> _inFlight = {};

  Future<void> load() async {
    if (!_inFlight.add('load')) return;
    emit(const TimelineLoading());
    try {
      _celebrations = await _repo.celebrations();
      try {
        _celebratesMe = await _repo.celebratesMe();
      } catch (_) {
        _celebratesMe = const {};
      }
      _emitGrouped();
    } on AppFailure catch (f) {
      emit(TimelineError(f.message));
    } catch (_) {
      emit(const TimelineError(AppStrings.somethingWentWrong));
    } finally {
      _inFlight.remove('load');
    }
  }

  /// Re-fetches when the tab comes back, without a spinner; a failure keeps
  /// the last good timeline.
  Future<void> refresh() async {
    if (state is! TimelineLoaded && state is! TimelineEmpty) return;
    if (!_inFlight.add('load')) return;
    try {
      _celebrations = await _repo.celebrations();
      try {
        _celebratesMe = await _repo.celebratesMe();
      } catch (_) {}
      _emitGrouped();
    } catch (_) {
      // Keep the last good timeline.
    } finally {
      _inFlight.remove('load');
    }
  }

  /// Deletes the edge and drops it from the in-memory list -- no
  /// [_repo.celebrations] re-fetch, since the local list minus this one row
  /// is already the correct next state.
  Future<void> stopCelebrating(int celebrationId) async {
    final key = 'stop:$celebrationId';
    if (!_inFlight.add(key)) return;
    try {
      await _repo.stopCelebrating(celebrationId);
      _celebrations =
          _celebrations.where((c) => c.id != celebrationId).toList();
      _emitGrouped();
    } catch (_) {
      _emitGrouped(error: AppStrings.somethingWentWrong);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Regroups [_celebrations] off the injected clock and emits. Grouping
  /// arithmetic itself -- including the Feb 29 rule that must agree with the
  /// pg_cron reminder fan-out -- lives entirely in [Birthday.groupFrom]
  /// (Task 4); this only calls it and buckets the result. A `null` group key
  /// is a person with no birthday at all, which `groupFrom` cannot be asked
  /// about.
  void _emitGrouped({String? error}) {
    if (_celebrations.isEmpty) {
      emit(const TimelineEmpty());
      return;
    }
    final groups = <TimelineGroup?, List<Celebration>>{};
    for (final c in _celebrations) {
      final key = c.person.birthday?.groupFrom(_now());
      groups.putIfAbsent(key, () => []).add(c);
    }
    for (final entry in groups.entries) {
      final key = entry.key;
      if (key == null) continue; // nothing to order a "no birthday" row by
      entry.value.sort(
        (a, b) => a.person.birthday!
            .nextOccurrence(_now())
            .compareTo(b.person.birthday!.nextOccurrence(_now())),
      );
    }
    emit(TimelineLoaded(groups, error: error, celebratesMe: _celebratesMe));
  }
}
