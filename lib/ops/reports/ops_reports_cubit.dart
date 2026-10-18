import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/ops_reports_repository.dart';
import 'ops_reports_state.dart';

class OpsReportsCubit extends Cubit<OpsReportsState> with ReentrancyGuard {
  OpsReportsCubit(this._reports) : super(const OpsReportsLoading());
  final OpsReportsRepository _reports;

  Future<void> load() => guard('load', () async {
        emit(const OpsReportsLoading());
        try {
          emit(OpsReportsLoaded(await _reports.openReports()));
        } on AuthFailure catch (f) {
          emit(OpsReportsError(f.message, sessionExpired: true));
        } on AppFailure catch (f) {
          emit(OpsReportsError(f.message));
        } catch (_) {
          emit(const OpsReportsError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> removePost(int reportId) => _decide(
        reportId,
        () => _reports.removePost(reportId),
        AppStrings.opsRemoved,
      );

  Future<void> dismiss(int reportId) => _decide(
        reportId,
        () => _reports.dismiss(reportId),
        AppStrings.opsDismissed,
      );

  /// One decision closes every open report on the same target server-side,
  /// so the queue is re-read afterwards rather than patched locally.
  Future<void> _decide(
    int reportId,
    Future<void> Function() write,
    String done,
  ) =>
      guard('decide:$reportId', () async {
        final current = state;
        if (current is! OpsReportsLoaded) return;
        emit(OpsReportsLoaded(
          current.reports,
          busy: {...current.busy, reportId},
        ));
        try {
          await write();
          emit(OpsReportsLoaded(await _reports.openReports(), message: done));
        } on AuthFailure catch (f) {
          emit(OpsReportsError(f.message, sessionExpired: true));
        } on AppFailure catch (f) {
          _release(reportId, f.message);
        } catch (_) {
          _release(reportId, AppStrings.somethingWentWrong);
        }
      });

  void _release(int reportId, String message) {
    final current = state;
    if (current is! OpsReportsLoaded) return;
    emit(OpsReportsLoaded(
      current.reports,
      busy: {...current.busy}..remove(reportId),
      message: message,
    ));
  }
}
