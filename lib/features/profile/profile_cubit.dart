import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/logger.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/wish.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../repositories/wish_repository.dart';
import 'profile_state.dart';

/// The signed-in user's own standing in the loop (spec §7.3): the header
/// counts, and the wall of wishes they have received.
///
/// Mixes in [ReentrancyGuard] rather than hand-rolling a bool or a state
/// check, same reasoning as [PersonCubit]: the "in flight" state this cubit
/// would otherwise check is emitted only after the first await, and that is
/// exactly the window a double-tap lands in.
class ProfileCubit extends Cubit<ProfileState> with ReentrancyGuard {
  ProfileCubit(this._profile, this._graph, this._auth, this._wishes)
      : super(const ProfileLoading());

  final ProfileRepository _profile;
  final GraphRepository _graph;
  final AuthRepository _auth;
  final WishRepository _wishes;

  Future<void> load() => guard('load', () async {
        emit(const ProfileLoading());
        try {
          final profile = await _auth.loadProfile();
          final stats = await _profile.stats();
          final celebrates = await _profile.celebrates();
          final celebrations = await _graph.celebrations();
          final wall = await _loadWall();

          emit(
            ProfileLoaded(
              profile: profile,
              celebratingCount: celebrations.length,
              celebratesCount: celebrates.length,
              wishesReceived:
                  stats.fold(0, (sum, s) => sum + s.wishesReceived),
              wishesSent: stats.fold(0, (sum, s) => sum + s.wishesSent),
              stats: stats,
              wall: wall,
            ),
          );
        } on AppFailure catch (f) {
          emit(ProfileError(f.message));
        } catch (_) {
          emit(const ProfileError(AppStrings.somethingWentWrong));
        }
      });

  /// The wall is decoration under the counts, not the point of the page: a
  /// failure here is logged and shows an empty wall rather than replacing
  /// the whole profile with an error.
  Future<List<Wish>> _loadWall() async {
    try {
      return await _wishes.wishesToMe();
    } catch (e, s) {
      Log.error('profile wall failed to load', e, s);
      return const [];
    }
  }
}
