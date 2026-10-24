import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/analytics.dart';
import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/celebration.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/profile_repository.dart';
import 'connections_state.dart';

/// The "I celebrate" / "Celebrate me" screen: both directions of the
/// signed-in user's graph, and the two writes it offers -- celebrating
/// someone back, and stopping.
class ConnectionsCubit extends Cubit<ConnectionsState> with ReentrancyGuard {
  ConnectionsCubit(this._graph, this._profile)
      : super(const ConnectionsLoading());

  final GraphRepository _graph;
  final ProfileRepository _profile;

  Future<void> load() => guard('load', () async {
        emit(const ConnectionsLoading());
        try {
          final iCelebrate = await _graph.celebrations();
          final celebrateMe = await _profile.celebrates();
          emit(ConnectionsLoaded(
            iCelebrate: iCelebrate,
            celebrateMe: celebrateMe,
          ));
        } on AppFailure catch (f) {
          emit(ConnectionsError(f.message));
        } catch (_) {
          emit(const ConnectionsError(AppStrings.somethingWentWrong));
        }
      });

  /// Re-reads [ConnectionsLoaded.iCelebrate] afterwards rather than adding a
  /// row locally: the new edge's id is only known to the server, and
  /// "stop celebrating" on that row needs it.
  Future<void> celebrateBack(int personId) =>
      _write(personId, () async {
        await _graph.celebrateBack(personId);
        Analytics.log(
          AppEvent.celebrateBack,
          {AppParam.source: 'connections'},
        ).ignore();
        return _graph.celebrations();
      });

  Future<void> stopCelebrating(int personId) => _write(personId, () async {
        final s = state as ConnectionsLoaded;
        final edge = s.iCelebrate.where((c) => c.person.id == personId);
        if (edge.isEmpty) return s.iCelebrate;
        await _graph.stopCelebrating(edge.first.id);
        return [
          for (final c in s.iCelebrate)
            if (c.person.id != personId) c,
        ];
      });

  /// Runs one row's write with that row marked pending, keyed per person so
  /// a double tap fires once but two different rows can both be in flight.
  Future<void> _write(
    int personId,
    Future<List<Celebration>> Function() body,
  ) =>
      guard('write:$personId', () async {
        final s = state;
        if (s is! ConnectionsLoaded) return;
        emit(s.copyWith(pending: {...s.pending, personId}));
        try {
          final next = await body();
          final now = state as ConnectionsLoaded;
          emit(now.copyWith(
            iCelebrate: next,
            pending: {...now.pending}..remove(personId),
          ));
        } on AppFailure catch (f) {
          final now = state as ConnectionsLoaded;
          emit(now.copyWith(
            pending: {...now.pending}..remove(personId),
            error: f.message,
          ));
        } catch (_) {
          final now = state as ConnectionsLoaded;
          emit(now.copyWith(
            pending: {...now.pending}..remove(personId),
            error: AppStrings.somethingWentWrong,
          ));
        }
      });
}
