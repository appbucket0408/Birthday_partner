import '../models/blocked_person.dart';
import '../models/report_reason.dart';

abstract interface class ModerationRepository {
  /// Queues the wish for staff review; reporting it twice is not an error.
  Future<void> reportWish(int wishId, ReportReason reason);
  Future<void> reportPerson(int personId, ReportReason reason);

  Future<void> block(String profileId);
  Future<void> unblock(String profileId);
  Future<List<BlockedPerson>> blockedPeople();

  /// Allowed for the author, and for the owner of the wall it is on.
  Future<void> deleteWish(int wishId);
}
