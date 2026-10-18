import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/ops_report.dart';
import 'package:birthday_app/models/report_reason.dart';
import 'package:birthday_app/ops/reports/ops_reports_cubit.dart';
import 'package:birthday_app/ops/reports/ops_reports_state.dart';
import 'package:birthday_app/repositories/ops_reports_repository.dart';
import 'package:flutter_test/flutter_test.dart';

OpsReport _report(int id, {int? wishId}) => OpsReport(
      id: id,
      createdAt: DateTime.utc(2026, 10, 18),
      reason: ReportReason.spam,
      reportedProfileId: 'p$id',
      reportedName: 'Asha',
      reporterName: 'Ravi',
      reportCount: 1,
      wishId: wishId,
      wishBody: wishId == null ? null : 'body',
      wishStillExists: wishId != null,
    );

class _FakeReports implements OpsReportsRepository {
  List<OpsReport> open = [_report(1, wishId: 10), _report(2)];
  Object? error;
  final removed = <int>[];
  final dismissed = <int>[];

  @override
  Future<List<OpsReport>> openReports() async {
    if (error != null) throw error!;
    return open;
  }

  @override
  Future<void> removePost(int reportId) async {
    if (error != null) throw error!;
    removed.add(reportId);
    open = open.where((r) => r.id != reportId).toList();
  }

  @override
  Future<void> dismiss(int reportId) async {
    if (error != null) throw error!;
    dismissed.add(reportId);
    open = open.where((r) => r.id != reportId).toList();
  }

  @override
  Future<String> photoUrl(String path) => throw UnimplementedError();
}

void main() {
  test('load shows the open queue', () async {
    final cubit = OpsReportsCubit(_FakeReports());
    await cubit.load();

    expect((cubit.state as OpsReportsLoaded).reports.map((r) => r.id), [1, 2]);
  });

  test('a dead session is flagged so the console routes to sign-in',
      () async {
    final repo = _FakeReports()..error = const AuthFailure('expired');
    final cubit = OpsReportsCubit(repo);
    await cubit.load();

    expect((cubit.state as OpsReportsError).sessionExpired, isTrue);
  });

  test('removing a post re-reads the queue and confirms', () async {
    final repo = _FakeReports();
    final cubit = OpsReportsCubit(repo);
    await cubit.load();

    await cubit.removePost(1);

    expect(repo.removed, [1]);
    final state = cubit.state as OpsReportsLoaded;
    expect(state.reports.map((r) => r.id), [2]);
    expect(state.message, AppStrings.opsRemoved);
  });

  test('dismissing re-reads the queue and confirms', () async {
    final repo = _FakeReports();
    final cubit = OpsReportsCubit(repo);
    await cubit.load();

    await cubit.dismiss(2);

    expect(repo.dismissed, [2]);
    expect((cubit.state as OpsReportsLoaded).message, AppStrings.opsDismissed);
  });

  test('a failed decision keeps the queue and says why', () async {
    final repo = _FakeReports();
    final cubit = OpsReportsCubit(repo);
    await cubit.load();
    repo.error = const ServerFailure('nope');

    await cubit.removePost(1);

    final state = cubit.state as OpsReportsLoaded;
    expect(state.reports.map((r) => r.id), [1, 2]);
    expect(state.busy, isEmpty);
    expect(state.message, 'nope');
  });
}
