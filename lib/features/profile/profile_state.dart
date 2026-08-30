import '../../models/birthday_stat.dart';
import '../../models/profile.dart';

sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

/// [celebratingCount] and [celebratesCount] back the two tappable header
/// counts (`GraphRepository.celebrations()` and `ProfileRepository.celebrates()`
/// respectively); [wishesReceived] is read off [stats]'s row for the current
/// year, never the newest row in the list -- a past year with wishes and no
/// row yet for this year must show 0, not that past total. See
/// [ProfileCubit.load].
final class ProfileLoaded extends ProfileState {
  const ProfileLoaded({
    required this.profile,
    required this.celebratingCount,
    required this.celebratesCount,
    required this.wishesReceived,
    required this.stats,
  });

  final Profile profile;
  final int celebratingCount;
  final int celebratesCount;
  final int wishesReceived;
  final List<BirthdayStat> stats;
}

final class ProfileError extends ProfileState {
  const ProfileError(this.message);

  final String message;
}
