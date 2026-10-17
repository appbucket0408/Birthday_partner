import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import 'gift_interest_repository.dart';

class GiftInterestRepositoryImpl implements GiftInterestRepository {
  const GiftInterestRepositoryImpl(this._client);
  final SupabaseClient _client;

  static const _table = 'gift_interest';
  static const _recipient = 'recipient_person_id';

  @override
  Future<bool> isRegistered(int personId) async {
    try {
      // RLS (gift_interest_select_own) narrows this to the caller's rows.
      final row = await _client
          .from(_table)
          .select('id')
          .eq(_recipient, personId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> register(int personId) async {
    try {
      await _client.from(_table).insert({_recipient: personId});
    } on PostgrestException catch (e) {
      // gift_interest_once: already registered is the outcome we wanted.
      if (e.code == '23505') return;
      throw mapError(e);
    } catch (e) {
      throw mapError(e);
    }
  }
}
