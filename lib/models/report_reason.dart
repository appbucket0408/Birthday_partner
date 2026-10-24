import '../core/app_strings.dart';

/// Values match reports_reason_valid in 20261024170000_moderation.sql.
enum ReportReason {
  spam('spam', AppStrings.reportReasonSpam),
  harassment('harassment', AppStrings.reportReasonHarassment),
  inappropriate('inappropriate', AppStrings.reportReasonInappropriate),
  impersonation('impersonation', AppStrings.reportReasonImpersonation),
  other('other', AppStrings.reportReasonOther);

  const ReportReason(this.value, this.label);

  final String value;
  final String label;
}
