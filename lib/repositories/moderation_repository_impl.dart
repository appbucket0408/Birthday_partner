import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/blocked_user.dart';
import '../models/report_reason.dart';
import 'moderation_repository.dart';

class ModerationRepositoryImpl implements ModerationRepository {
  const ModerationRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<void> reportWish(int wishId, ReportReason reason) async {
    try {
      await _client.rpc(
        ApiEndpoints.rpcReportWish,
        params: {ApiParams.pWishId: wishId, ApiParams.pReason: reason.wire},
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> reportUser(String profileId, ReportReason reason) async {
    try {
      await _client.rpc(
        ApiEndpoints.rpcReportUser,
        params: {
          ApiParams.pProfileId: profileId,
          ApiParams.pReason: reason.wire,
        },
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> block(String profileId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthFailure('no session');
    try {
      // blocks_all_own lets the owner write their own rows directly; the
      // side effects (edges, notifications) run in the blocks_apply trigger.
      // ignoreDuplicates makes a second tap a no-op instead of a 23505.
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
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthFailure('no session');
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
  Future<List<BlockedUser>> blockedUsers() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyBlockedUsers);
      return [
        for (final r in rows as List)
          BlockedUser.fromRow(r as Map<String, dynamic>),
      ];
    } catch (e) {
      throw mapError(e);
    }
  }
}
