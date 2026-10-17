import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/wish.dart';
import 'wish_repository.dart';

class WishRepositoryImpl implements WishRepository {
  const WishRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Wish>> wishesFor(int personId) async {
    try {
      final rows = await _client
          .from(ApiParams.wishes)
          .select()
          .eq(ApiParams.subjectPersonId, personId)
          .order(ApiParams.createdAt, ascending: false);

      final wishes = (rows as List)
          .map((r) => Wish.fromRow(r as Map<String, dynamic>))
          .toList();
      if (wishes.isEmpty) return wishes;

      // Second step, and it cannot be avoided: profiles_select_own restricts
      // profiles to their owner, and there is no FK from wishes to people, so
      // PostgREST cannot embed the author. Resolve names from `people`, where
      // RLS filters to authors already in the viewer's graph. Anyone else
      // comes back missing and their wish renders unattributed -- intended.
      final authorIds =
          wishes.map((w) => w.authorProfileId).toSet().toList(growable: false);

      final people = await _client
          .from(ApiParams.people)
          .select('${ApiParams.profileId}, ${ApiParams.displayName}')
          .inFilter(ApiParams.profileId, authorIds);

      final names = <String, String>{
        for (final p in people as List)
          (p as Map<String, dynamic>)[ApiParams.profileId] as String:
              p[ApiParams.displayName] as String,
      };

      return wishes
          .map((w) => w.withAuthorName(names[w.authorProfileId]))
          .toList(growable: false);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Wish>> wishesToMe() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthFailure('no session');
    final int? myPersonId;
    try {
      final row = await _client
          .from(ApiParams.people)
          .select(ApiParams.id)
          .eq(ApiParams.profileId, me)
          .maybeSingle();
      myPersonId = row?[ApiParams.id] as int?;
    } catch (e) {
      throw mapError(e);
    }
    if (myPersonId == null) return const [];
    return wishesFor(myPersonId);
  }

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  }) async {
    final authorId = _client.auth.currentUser?.id;
    if (authorId == null) throw const AuthFailure('no session');
    try {
      await _client.from(ApiParams.wishes).insert({
        ApiParams.authorProfileId: authorId,
        ApiParams.subjectPersonId: personId,
        ApiParams.body: body,
        ApiParams.occasionYear: occasionYear,
      });
    } catch (e) {
      throw mapError(e);
    }
  }
}
