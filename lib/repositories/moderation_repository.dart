import '../models/blocked_user.dart';
import '../models/report_reason.dart';

/// Report and block, from the consumer app. Staff review lives in
/// `OpsRepository`.
abstract interface class ModerationRepository {
  /// Reports a post. Reporting the same post twice is not an error. The post
  /// is hidden from the caller's feed and walls from then on.
  Future<void> reportWish(int wishId, ReportReason reason);

  /// Reports a person.
  Future<void> reportUser(String profileId, ReportReason reason);

  /// Blocks [profileId]. Removes every celebration between the two of them
  /// and hides each one's posts from the other. Blocking twice is not an
  /// error.
  Future<void> block(String profileId);

  Future<void> unblock(String profileId);

  Future<List<BlockedUser>> blockedUsers();
}
