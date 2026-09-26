import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import 'staff_auth_repository.dart';

class StaffAuthRepositoryImpl implements StaffAuthRepository {
  const StaffAuthRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
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
  Future<bool> isStaff() async {
    final userId = _client.auth.currentUser?.id;
    // No session is not an error -- the console asks this before it knows
    // whether anyone is signed in.
    if (userId == null) return false;

    try {
      // profiles_select_own restricts this to the caller's own row, so the
      // filter is belt-and-braces rather than the boundary. Explicit column,
      // never `select()`: a column added to profiles later cannot leak into
      // a console read by default.
      final row = await _client
          .from(ApiParams.profiles)
          .select(ApiParams.isStaff)
          .eq(ApiParams.id, userId)
          .maybeSingle();

      if (row == null) return false;
      return (row[ApiParams.isStaff] as bool?) ?? false;
    } catch (e) {
      throw mapError(e);
    }
  }
}
