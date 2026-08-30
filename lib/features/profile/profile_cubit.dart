import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/birthday_stat.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/profile_repository.dart';
import 'profile_state.dart';

/// The signed-in user's own standing in the loop (spec §7.3): the header
/// counts, and the per-year track record below them.
///
/// Mixes in [ReentrancyGuard] rather than hand-rolling a bool or a state
/// check, same reasoning as [PersonCubit]: the "in flight" state this cubit
/// would otherwise check is emitted only after the first await, and that is
/// exactly the window a double-tap lands in.
class ProfileCubit extends Cubit<ProfileState> with ReentrancyGuard {
  /// [now] is injectable so [wishesReceived] never depends on the real
  /// clock -- a test that reads the current year off `DateTime.now()` passes
  /// this year and fails on the next run past New Year's.
  ProfileCubit(
    this._profile,
    this._graph,
    this._auth, {
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(const ProfileLoading());

  final ProfileRepository _profile;
  final GraphRepository _graph;
  final AuthRepository _auth;
  final DateTime Function() _now;

  Future<void> load() => guard('load', () async {
        emit(const ProfileLoading());
        try {
          final profile = await _auth.loadProfile();
          final stats = await _profile.stats();
          final celebrates = await _profile.celebrates();
          final celebrations = await _graph.celebrations();

          emit(
            ProfileLoaded(
              profile: profile,
              celebratingCount: celebrations.length,
              celebratesCount: celebrates.length,
              wishesReceived: _wishesReceivedThisYear(stats),
              stats: stats,
            ),
          );
        } on AppFailure catch (f) {
          emit(ProfileError(f.message));
        } catch (_) {
          emit(const ProfileError(AppStrings.somethingWentWrong));
        }
      });

  /// The current year's row's `wishesReceived`, or 0 when [stats] has no row
  /// for this year -- NOT the newest row in the list. `ProfileRepository`
  /// returns [stats] newest-year-first, so `stats.first` would read as the
  /// same thing in the common case where a row for the current year already
  /// exists, and only diverges the moment it does not (a brand-new account
  /// mid-year, or a year that has passed with no wishes yet) -- exactly the
  /// case this method exists to get right.
  int _wishesReceivedThisYear(List<BirthdayStat> stats) {
    final currentYear = _now().year;
    for (final stat in stats) {
      if (stat.year == currentYear) return stat.wishesReceived;
    }
    return 0;
  }
}
