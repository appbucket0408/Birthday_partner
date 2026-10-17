import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../models/birthday_stat.dart';
import '../models/person.dart';
import 'profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<BirthdayStat>> stats() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyBirthdayStats);
      final stats = (rows as List)
          .map((r) => BirthdayStat.fromRow(r as Map<String, dynamic>))
          .toList();
      stats.sort((a, b) => b.year.compareTo(a.year));
      return stats;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Person>> celebrates() async {
    try {
      final rows = await _client.rpc(ApiEndpoints.rpcMyCelebrates);

      // my_celebrates() returns identities only -- a profile id and a person
      // id, never a name, because a row-level policy exposing incoming edges
      // would also hand over the source that reveals how they found you. Names come from `people`,
      // where can_see_person's "they celebrate me" branch makes exactly
      // these rows visible. The left join means celebrator_person_id can be
      // null for a celebrator who has not claimed their own row; those are
      // dropped -- there is no name to show.
      final personIds = (rows as List)
          .map(
              (r) => (r as Map<String, dynamic>)[ApiParams.celebratorPersonId])
          .whereType<int>()
          .toList(growable: false);
      if (personIds.isEmpty) return const [];

      final people = await _client
          .from(ApiParams.people)
          .select()
          .inFilter(ApiParams.id, personIds);

      return (people as List)
          .map((p) => Person.fromRow(p as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      throw mapError(e);
    }
  }
}
