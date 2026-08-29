import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/birthday.dart';
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
          .select('${ApiParams.id}, ${ApiParams.nickname}, '
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
  Future<void> updateBirthday(int personId, Birthday birthday) async {
    try {
      await _client.rpc(ApiEndpoints.rpcUpdatePersonBirthday, params: {
        ApiParams.pPersonId: personId,
        ApiParams.pBirthMonth: birthday.month,
        ApiParams.pBirthDay: birthday.day,
        ApiParams.pBirthYear: birthday.year,
      });
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> updateNickname(int celebrationId, String? nickname) async {
    try {
      await _client
          .from(ApiParams.celebrations)
          .update({ApiParams.nickname: nickname})
          .eq(ApiParams.id, celebrationId);
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
