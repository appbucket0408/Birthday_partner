import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/celebration.dart';
import 'graph_repository.dart';

class GraphRepositoryImpl implements GraphRepository {
  const GraphRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Celebration>> celebrations() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure('no session');
    try {
      final rows = await _client
          .from(ApiParams.celebrations)
          .select('${ApiParams.id}, '
              '${ApiParams.people}(${ApiParams.id}, ${ApiParams.displayName}, '
              '${ApiParams.profileId}, ${ApiParams.birthMonth}, '
              '${ApiParams.birthDay}, ${ApiParams.birthYear})')
          .eq(ApiParams.celebratorProfileId, userId);
      return rows.map(Celebration.fromRow).toList();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Set<int>> celebratesMe() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyCelebrates);
      // celebrator_person_id is null for a celebrator who has not claimed
      // their own row -- nobody to show or celebrate back.
      return {
        for (final r in rows as List)
          if ((r as Map<String, dynamic>)[ApiParams.celebratorPersonId]
              case final int id)
            id,
      };
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> celebrateBack(int personId) async {
    try {
      await _client.rpc(
        ApiEndpoints.rpcCelebrateBack,
        params: {ApiParams.pPersonId: personId},
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> stopCelebrating(int celebrationId) async {
    try {
      await _client
          .from(ApiParams.celebrations)
          .delete()
          .eq(ApiParams.id, celebrationId);
    } catch (e) {
      throw mapError(e);
    }
  }
}
