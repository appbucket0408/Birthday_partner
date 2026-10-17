import '../models/celebration.dart';

/// The signed-in user's place in the graph: the edges they own (each with its
/// person embedded), who celebrates them, and the two edge writes a user can
/// make here -- celebrating back, and stopping. Nobody edits another
/// person's name or birthday. Spec §6.3.
abstract interface class GraphRepository {
  /// The signed-in user's celebration edges, person embedded. Grouping and
  /// sorting for the timeline is the Cubit's job (Task 12), not this
  /// repository's.
  Future<List<Celebration>> celebrations();

  /// The person ids of members who celebrate the signed-in user (via
  /// `my_celebrates()`). Ids only -- for marking "Celebrates you" and for
  /// telling who can be celebrated back.
  Future<Set<int>> celebratesMe();

  /// Celebrates [personId] back. Only works for someone who celebrates the
  /// signed-in user: `rpc_celebrate_back` refuses anyone else with
  /// [ServerFailure] code '45006'. Idempotent.
  Future<void> celebrateBack(int personId);

  /// Deletes the edge. A plain DELETE -- `celebrations_delete_own` survived
  /// Phase 2a's write lockdown, so no RPC is needed.
  Future<void> stopCelebrating(int celebrationId);
}
