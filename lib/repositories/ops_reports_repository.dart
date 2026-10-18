import '../models/ops_report.dart';

/// The ops console's moderation queue. Separate from [OpsRepository] (the
/// catalog and delivery calendar) for the same reason that one is separate
/// from GiftRepository: one responsibility per repository.
///
/// Every call is staff-only server-side: `ops_open_reports` and
/// `ops_resolve_report` raise 42501 for anyone else, and the Storage
/// policies `wish_photos_select_staff` / `wish_photos_delete_staff` gate the
/// photo calls.
abstract interface class OpsReportsRepository {
  Future<List<OpsReport>> openReports();

  /// Deletes the reported post (and its photo) and closes every open report
  /// about it.
  Future<void> removePost(int reportId);

  /// Closes every open report on the same target without changing anything.
  Future<void> dismiss(int reportId);

  /// A short-lived URL for a reported photo, so staff can judge it.
  Future<String> photoUrl(String path);
}
