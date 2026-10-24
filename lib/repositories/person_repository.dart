import '../models/member_preview.dart';
import '../models/person.dart';

/// Reads about a single person. One responsibility: this is deliberately NOT
/// folded into GraphRepository, which reads the timeline. A consumer of one
/// should not be forced to depend on the other.
abstract interface class PersonRepository {
  /// The person, if the caller may see them. RLS decides: they are visible
  /// when the caller celebrates them, when they celebrate the caller, or when
  /// they are the caller's own person row.
  Future<Person> person(int personId);

  /// How many people celebrate them. A number, never names.
  ///
  /// Throws [ServerFailure] with code '45004' when the caller cannot see the
  /// person -- people.id is a sequential bigint, so the count is gated.
  Future<int> celebratorCount(int personId);

  /// A member on the public feed the caller is not connected to; null when
  /// they are not discoverable.
  Future<MemberPreview?> preview(int personId);
}
