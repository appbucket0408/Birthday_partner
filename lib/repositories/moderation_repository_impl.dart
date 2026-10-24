import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/app_strings.dart';
import '../core/result.dart';
import '../models/blocked_person.dart';
import '../models/report_reason.dart';
import 'moderation_repository.dart';

class ModerationRepositoryImpl implements ModerationRepository {
  const ModerationRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<void> reportWish(int wishId, ReportReason reason) => _rpc(
        ApiEndpoints.rpcReportWish,
        {ApiParams.pWishId: wishId, ApiParams.pReason: reason.value},
      );

  @override
  Future<void> reportPerson(int personId, ReportReason reason) => _rpc(
        ApiEndpoints.rpcReportPerson,
        {ApiParams.pPersonId: personId, ApiParams.pReason: reason.value},
      );

  @override
  Future<void> block(String profileId) async {
    final me = _me();
    try {
      await _client.from(ApiParams.blocks).upsert(
        {
          ApiParams.blockerProfileId: me,
          ApiParams.blockedProfileId: profileId,
        },
        onConflict:
            '${ApiParams.blockerProfileId},${ApiParams.blockedProfileId}',
        ignoreDuplicates: true,
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> unblock(String profileId) async {
    final me = _me();
    try {
      await _client
          .from(ApiParams.blocks)
          .delete()
          .eq(ApiParams.blockerProfileId, me)
          .eq(ApiParams.blockedProfileId, profileId);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<BlockedPerson>> blockedPeople() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyBlockedPeople);
      return [
        for (final r in rows as List)
          BlockedPerson.fromRow(r as Map<String, dynamic>),
      ];
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> deleteWish(int wishId) async {
    final List rows;
    try {
      rows = await _client
          .from(ApiParams.wishes)
          .delete()
          .eq(ApiParams.id, wishId)
          .select(ApiParams.id);
    } catch (e) {
      throw mapError(e);
    }
    // RLS skips rows it hides instead of failing.
    if (rows.isEmpty) throw ServerFailure(AppStrings.wishDeleteFailed);
  }

  String _me() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('no session');
    return id;
  }

  Future<void> _rpc(String name, Map<String, dynamic> params) async {
    try {
      await _client.rpc(name, params: params);
    } catch (e) {
      throw mapError(e);
    }
  }
}
