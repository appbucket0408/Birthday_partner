import '../core/app_strings.dart';


enum ReportReason {
  spam('spam', AppStrings.reportReasonSpam),
  harassment('harassment', AppStrings.reportReasonHarassment),
  inappropriate('inappropriate', AppStrings.reportReasonInappropriate),
  hate('hate', AppStrings.reportReasonHate),
  other('other', AppStrings.reportReasonOther);

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;

  static ReportReason fromWire(String value) =>
      values.firstWhere((r) => r.wire == value, orElse: () => other);
}
