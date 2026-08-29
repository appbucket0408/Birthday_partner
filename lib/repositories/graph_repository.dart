import '../models/birthday.dart';
import '../models/celebration.dart';

/// The Celebrating timeline's data source: the edges the signed-in user
/// owns, each with its person embedded, plus the three row actions a
/// timeline entry exposes. Spec §6.3.
abstract interface class GraphRepository {
  /// The signed-in user's celebration edges, person embedded. Grouping and
  /// sorting for the timeline is the Cubit's job (Task 12), not this
  /// repository's.
  Future<List<Celebration>> celebrations();

  /// Sets [personId]'s birthday via `rpc_update_person_birthday`. Throws
  /// [ServerFailure] with code:
  ///  - '45002' if the caller holds no celebration edge to this person --
  ///    `people.id` is a sequential bigint and would otherwise be an open
  ///    write target;
  ///  - '45003' if the person has claimed their own profile -- their own
  ///    birthday wins, so no celebrator may rewrite it;
  ///  - '23514' if the date is impossible (e.g. April 31) -- `security
  ///    definer` does not exempt this write from the table's own CHECK
  ///    constraints.
  Future<void> updateBirthday(int personId, Birthday birthday);

  /// Renames a celebration edge's private label. The only client write left
  /// on `celebrations` besides delete (`grant update (nickname)`). A guard
  /// trigger rejects this if the target has since blocked the caller, so
  /// that error must reach the caller rather than being swallowed.
  Future<void> updateNickname(int celebrationId, String? nickname);

  /// Deletes the edge. A plain DELETE -- `celebrations_delete_own` survived
  /// Phase 2a's write lockdown, so no RPC is needed.
  Future<void> stopCelebrating(int celebrationId);
}
