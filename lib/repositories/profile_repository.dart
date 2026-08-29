import '../models/birthday_stat.dart';
import '../models/person.dart';

/// The signed-in user's own profile data. One responsibility.
///
/// Deliberately does NOT own the Celebrating list: GraphRepository.celebrations()
/// already returns it, and the profile's list screen reuses that rather than
/// duplicating the query here.
abstract interface class ProfileRepository {
  /// The per-year track record, newest year first.
  Future<List<BirthdayStat>> stats();

  /// The people who celebrate the signed-in user, excluding anyone they have
  /// blocked. A celebrator with no claimed person row is omitted -- there is
  /// no name to show.
  Future<List<Person>> celebrates();
}
