import '../models/celebration.dart';

/// The Celebrating timeline's data source: the edges the signed-in user
/// owns, each with its person embedded, plus the one row action a timeline
/// entry exposes (stop celebrating). Nobody edits another person's name or
/// birthday. Spec §6.3.
abstract interface class GraphRepository {
  /// The signed-in user's celebration edges, person embedded. Grouping and
  /// sorting for the timeline is the Cubit's job (Task 12), not this
  /// repository's.
  Future<List<Celebration>> celebrations();


  /// Deletes the edge. A plain DELETE -- `celebrations_delete_own` survived
  /// Phase 2a's write lockdown, so no RPC is needed.
  Future<void> stopCelebrating(int celebrationId);
}
