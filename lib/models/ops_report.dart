import '../api/api_params.dart';
import 'report_reason.dart';

class OpsReport {
  const OpsReport({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.reportedProfileId,
    required this.reportedName,
    required this.reporterName,
    required this.reportCount,
    this.note,
    this.wishId,
    this.wishBody,
    this.wishPhotoPath,
    this.wishStillExists = false,
  });

  final int id;
  final DateTime createdAt;
  final ReportReason reason;
  final String? note;
  final int? wishId;
  final String? wishBody;
  final String? wishPhotoPath;
  final bool wishStillExists;
  final String reportedProfileId;
  final String reportedName;
  final String reporterName;

  /// Open reports on the same target, this one included.
  final int reportCount;

  bool get isAboutPost => wishId != null;

  factory OpsReport.fromRow(Map<String, dynamic> row) => OpsReport(
        id: row[ApiParams.id] as int,
        createdAt: DateTime.parse(row[ApiParams.createdAt] as String),
        reason: ReportReason.fromWire(row[ApiParams.reason] as String),
        note: row[ApiParams.note] as String?,
        wishId: row[ApiParams.wishId] as int?,
        wishBody: row[ApiParams.wishBody] as String?,
        wishPhotoPath: row[ApiParams.wishPhotoPath] as String?,
        wishStillExists: row[ApiParams.wishStillExists] as bool? ?? false,
        reportedProfileId: row[ApiParams.reportedProfileId] as String,
        reportedName: row[ApiParams.reportedName] as String,
        reporterName: row[ApiParams.reporterName] as String,
        reportCount: row[ApiParams.reportCount] as int,
      );
}
