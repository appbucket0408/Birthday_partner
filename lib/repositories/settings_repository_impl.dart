import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import 'settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<void> setRemindersEnabled(bool enabled) async {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('no session');
    try {
      await _client
          .from(ApiParams.profiles)
          .update({ApiParams.remindersEnabled: enabled})
          .eq(ApiParams.id, id);
    } catch (e) {
      throw mapError(e);
    }
  }
}
