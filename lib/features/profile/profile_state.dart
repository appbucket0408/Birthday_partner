import '../../models/birthday_stat.dart';
import '../../models/profile.dart';
import '../../models/wish.dart';

sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

/// [celebratingCount] and [celebratesCount] back the two tappable counts
/// (`GraphRepository.celebrations()` and `ProfileRepository.celebrates()`
/// respectively). [wishesReceived] and [wishesSent] are all-time totals,
/// summed over every year in [stats]. [wall] is the wishes people sent the
/// signed-in user, newest first.
final class ProfileLoaded extends ProfileState {
  const ProfileLoaded({
    required this.profile,
    required this.celebratingCount,
    required this.celebratesCount,
    required this.wishesReceived,
    required this.wishesSent,
    required this.stats,
    this.wall = const [],
  });

  final Profile profile;
  final int celebratingCount;
  final int celebratesCount;
  final int wishesReceived;
  final int wishesSent;
  final List<BirthdayStat> stats;
  final List<Wish> wall;
}

final class ProfileError extends ProfileState {
  const ProfileError(this.message);

  final String message;
}
