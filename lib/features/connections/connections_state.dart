import '../../models/celebration.dart';
import '../../models/person.dart';

sealed class ConnectionsState {
  const ConnectionsState();
}

final class ConnectionsLoading extends ConnectionsState {
  const ConnectionsLoading();
}

/// Both directions of the signed-in user's graph, for the two tabs.
///
/// [iCelebrate] are the user's own edges (they carry the celebration id that
/// "stop celebrating" needs). [celebrateMe] are the members who celebrate the
/// user. [pending] holds person ids with a write in flight, so only that
/// row's button shows progress. [error] is a transient message from the last
/// failed write -- the lists stay as they were.
final class ConnectionsLoaded extends ConnectionsState {
  const ConnectionsLoaded({
    required this.iCelebrate,
    required this.celebrateMe,
    this.pending = const {},
    this.error,
  });

  final List<Celebration> iCelebrate;
  final List<Person> celebrateMe;
  final Set<int> pending;
  final String? error;

  bool celebrates(int personId) =>
      iCelebrate.any((c) => c.person.id == personId);

  bool celebratesMe(int personId) =>
      celebrateMe.any((p) => p.id == personId);

  ConnectionsLoaded copyWith({
    List<Celebration>? iCelebrate,
    Set<int>? pending,
    String? error,
  }) =>
      ConnectionsLoaded(
        iCelebrate: iCelebrate ?? this.iCelebrate,
        celebrateMe: celebrateMe,
        pending: pending ?? this.pending,
        error: error,
      );
}

final class ConnectionsError extends ConnectionsState {
  const ConnectionsError(this.message);

  final String message;
}
