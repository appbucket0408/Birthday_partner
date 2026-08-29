import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/birthday.dart';
import '../models/profile.dart';
import 'auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> sendOtp(String phoneE164) async {
    try {
      await _client.auth.signInWithOtp(phone: phoneE164);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async {
    try {
      await _client.auth.verifyOTP(
        phone: phoneE164,
        token: token,
        type: OtpType.sms,
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<int> claimProfile() async {
    try {
      final res = await _client.functions.invoke(ApiEndpoints.claimProfile);
      final data = res.data as Map<String, dynamic>;
      return data['person_id'] as int;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Profile> loadProfile() async {
    final id = currentUserId;
    if (id == null) throw const AuthFailure('no session');
    try {
      final row = await _client
          .from(ApiParams.profiles)
          .select()
          .eq(ApiParams.id, id)
          .single();
      return Profile.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    final id = currentUserId;
    if (id == null) throw const AuthFailure('no session');
    try {
      await _client.from(ApiParams.profiles).update({
        ApiParams.handle: handle,
        ApiParams.displayName: displayName,
        ApiParams.city: city,
        ApiParams.birthMonth: birthday.month,
        ApiParams.birthDay: birthday.day,
        ApiParams.birthYear: birthday.year,
      }).eq(ApiParams.id, id);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke(ApiEndpoints.deleteAccount);
      await _client.auth.signOut();
    } catch (e) {
      throw mapError(e);
    }
  }
}
