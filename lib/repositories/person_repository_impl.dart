import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../models/member_preview.dart';
import '../models/person.dart';
import 'person_repository.dart';

class PersonRepositoryImpl implements PersonRepository {
  const PersonRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<Person> person(int personId) async {
    try {
      final row = await _client
          .from(ApiParams.people)
          .select()
          .eq(ApiParams.id, personId)
          .single();
      return Person.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<int> celebratorCount(int personId) async {
    try {
      final result = await _client.rpc(
        ApiEndpoints.rpcPersonCelebratorCount,
        params: {ApiParams.pPersonId: personId},
      );
      return result as int;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<MemberPreview?> preview(int personId) async {
    try {
      final rows = await _client.rpc(
        ApiEndpoints.rpcMemberPreview,
        params: {ApiParams.pPersonId: personId},
      ) as List;
      return rows.isEmpty
          ? null
          : MemberPreview.fromRow(rows.first as Map<String, dynamic>);
    } catch (e) {
      throw mapError(e);
    }
  }
}
