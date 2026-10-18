import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/logger.dart';
import '../models/ops_report.dart';
import 'ops_reports_repository.dart';

class OpsReportsRepositoryImpl implements OpsReportsRepository {
  const OpsReportsRepositoryImpl(this._client);
  final SupabaseClient _client;

  StorageFileApi get _photos =>
      _client.storage.from(ApiParams.wishPhotosBucket);

  @override
  Future<List<OpsReport>> openReports() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcOpsOpenReports);
      return [
        for (final r in rows as List)
          OpsReport.fromRow(r as Map<String, dynamic>),
      ];
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> removePost(int reportId) async {
    final String? photoPath;
    try {
      photoPath = await _client.rpc(
        ApiEndpoints.rpcOpsResolveReport,
        params: {ApiParams.pReportId: reportId, ApiParams.pAction: 'remove'},
      ) as String?;
    } catch (e) {
      throw mapError(e);
    }
    // SQL cannot delete a Storage object, so the function hands the path
    // back. The post is already gone and unreachable either way; a failure
    // here only leaves an orphaned file, so it is logged, not surfaced.
    if (photoPath == null) return;
    try {
      await _photos.remove([photoPath]);
    } catch (e, s) {
      Log.error('removed post photo cleanup failed', e, s);
    }
  }

  @override
  Future<void> dismiss(int reportId) async {
    try {
      await _client.rpc(
        ApiEndpoints.rpcOpsResolveReport,
        params: {ApiParams.pReportId: reportId, ApiParams.pAction: 'dismiss'},
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<String> photoUrl(String path) async {
    try {
      return await _photos.createSignedUrl(path, 600);
    } catch (e) {
      throw mapError(e);
    }
  }
}
