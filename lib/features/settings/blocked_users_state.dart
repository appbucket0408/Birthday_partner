import '../../models/blocked_user.dart';

sealed class BlockedUsersState {
  const BlockedUsersState();
}

final class BlockedUsersLoading extends BlockedUsersState {
  const BlockedUsersLoading();
}

final class BlockedUsersError extends BlockedUsersState {
  const BlockedUsersError(this.message);
  final String message;
}

final class BlockedUsersLoaded extends BlockedUsersState {
  const BlockedUsersLoaded(
    this.users, {
    this.unblocking = const {},
    this.error,
  });

  final List<BlockedUser> users;
  final Set<String> unblocking;
  final String? error;
}
