import '../../models/ops_report.dart';

sealed class OpsReportsState {
  const OpsReportsState();
}

class OpsReportsLoading extends OpsReportsState {
  const OpsReportsLoading();
}

/// [sessionExpired] routes the console back to sign-in, the same as the
/// catalog and slots screens.
class OpsReportsError extends OpsReportsState {
  const OpsReportsError(this.message, {this.sessionExpired = false});
  final String message;
  final bool sessionExpired;
}

/// [busy] holds the reports with a decision in flight. [message] is a
/// one-shot confirmation or failure for the snackbar.
class OpsReportsLoaded extends OpsReportsState {
  const OpsReportsLoaded(
    this.reports, {
    this.busy = const {},
    this.message,
  });

  final List<OpsReport> reports;
  final Set<int> busy;
  final String? message;
}
