import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/logger.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../models/celebration.dart';
import '../../models/person.dart';
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

  // The working copy every action mutates locally instead of re-fetching --
  // stopCelebrating in particular must remove its row "without a full
  // reload" per the task brief, and editBirthday/editNickname piggyback on
  // the same mechanism rather than inventing a second one.
  List<Celebration> _celebrations = const [];

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
      _emitGrouped();
    } catch (e) {
      emit(TimelineError('$e'));
    } finally {
      _inFlight.remove('load');
    }
  }

  /// Sets [personId]'s birthday. A 45003 (the person has claimed their own
  /// profile) is expected here -- any celebration can point at a claimed
  /// person -- and is mapped to a message the user can act on: give up on
  /// editing it, not "something went wrong".
  ///
  /// A 45002 (the caller holds no edge to this person) is NOT expected here:
  /// every personId this screen can pass in came from a celebration this
  /// user's own [celebrations] call returned, so the edge already exists.
  /// Seeing 45002 from this screen means personId leaked in from somewhere
  /// it should not have -- a bug, not a user-facing rejection -- so it is
  /// mapped to the generic message and logged, never shown as a specific
  /// explanation the user did nothing to deserve.
  Future<void> editBirthday(int personId, Birthday birthday) async {
    final key = 'birthday:$personId';
    if (!_inFlight.add(key)) return;
    try {
      await _repo.updateBirthday(personId, birthday);
      _celebrations = [
        for (final c in _celebrations)
          if (c.person.id == personId)
            Celebration(
              id: c.id,
              nickname: c.nickname,
              person: Person(
                id: c.person.id,
                displayName: c.person.displayName,
                isClaimed: c.person.isClaimed,
                birthday: birthday,
              ),
            )
          else
            c,
      ];
      _emitGrouped();
    } on ServerFailure catch (f) {
      if (f.code == '45002') {
        Log.error(
          'editBirthday got 45002 (no edge to this person) from the '
          'timeline -- every personId here should come from this user\'s '
          'own celebrations() list',
          f,
        );
      }
      _emitGrouped(
        error: f.code == '45003'
            ? AppStrings.timelineBirthdayNotEditable
            : AppStrings.somethingWentWrong,
      );
    } catch (_) {
      _emitGrouped(error: AppStrings.somethingWentWrong);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Renames a celebration's private label. The only failure mode on this
  /// write path is `private.guard_celebration`'s block check, which runs on
  /// ANY update to a `celebrations` row -- including a nickname edit -- and
  /// rejects it if the person has blocked this caller since the edge was
  /// created. There is no other rejection code to branch on here, so any
  /// [ServerFailure] on this call is read as that guard.
  Future<void> editNickname(int celebrationId, String? nickname) async {
    final key = 'nickname:$celebrationId';
    if (!_inFlight.add(key)) return;
    try {
      await _repo.updateNickname(celebrationId, nickname);
      _celebrations = [
        for (final c in _celebrations)
          if (c.id == celebrationId)
            Celebration(id: c.id, person: c.person, nickname: nickname)
          else
            c,
      ];
      _emitGrouped();
    } on ServerFailure catch (_) {
      _emitGrouped(error: AppStrings.timelineNicknameBlocked);
    } catch (_) {
      _emitGrouped(error: AppStrings.somethingWentWrong);
    } finally {
      _inFlight.remove(key);
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
    emit(TimelineLoaded(groups, error: error));
  }
}
