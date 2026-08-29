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

  /// null until Phase 2c registers a push token via
  /// `register_device_token`. There is no client-side field to read a
  /// current token from yet, so this always resolves to null today -- see
  /// the guarded no-op below and the class doc on [deleteThisDeviceToken].
  String? get _currentDeviceToken => null;

  @override
  Future<void> deleteThisDeviceToken() async {
    final token = _currentDeviceToken;
    if (token == null) return;
    try {
      await _client
          .from(ApiParams.deviceTokens)
          .delete()
          .eq(ApiParams.token, token);
    } catch (e) {
      throw mapError(e);
    }
  }
}
