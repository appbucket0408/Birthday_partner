import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/app_strings.dart';
import '../core/logger.dart';
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
  Future<void> sendEmailOtp(String email) async {
    try {
      await _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  // `phone` is '' rather than null on an email-only user, and stays '' while
  // a phone change is pending (the pending number sits in `new_phone`).
  @override
  bool get hasVerifiedPhone =>
      (_client.auth.currentUser?.phone ?? '').isNotEmpty;

  @override
  Future<void> sendPhoneLink(String phoneE164) async {
    try {
      await _client.auth.updateUser(UserAttributes(phone: phoneE164));
    } on AuthException catch (e) {
      // A number already on another account. Saying so is not an oracle
      // worth hiding: the same number on the sign-in screen would simply
      // sign into that account.
      if (e.code == 'phone_exists') {
        throw const AuthFailure(AppStrings.phoneAlreadyRegistered);
      }
      throw mapError(e);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> verifyPhoneLink({
    required String phoneE164,
    required String token,
  }) async {
    try {
      await _client.auth.verifyOTP(
        phone: phoneE164,
        token: token,
        type: OtpType.phoneChange,
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
      return data[ApiParams.personId] as int;
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
    } catch (e) {
      // The Edge Function call IS the delete. If it threw, nothing happened
      // server-side, so this is a genuine failure the caller must see.
      throw mapError(e);
    }

    // The account is gone the instant the call above returns without
    // throwing. From here the operation must NOT be reported as a failure:
    // a caller who saw an exception here would reasonably retry
    // deleteAccount(), which re-invokes the Edge Function against a user
    // that no longer exists and gets back a 500 (see delete_account's own
    // KNOWN LIMIT comment on admin.deleteUser 404s) -- indistinguishable
    // from a real failure, even though nothing is actually wrong anymore.
    // So a signOut() failure here is logged, never rethrown. It also can't
    // leave a live session behind: gotrue's signOut(scope: local) clears
    // the local session before it ever touches the network, and only the
    // best-effort server-side call after that can throw. A second,
    // explicitly local-only attempt is made anyway so this stays correct
    // even if that internal ordering ever changes -- and its own failure is
    // swallowed too, since there is nothing further this method can do.
    try {
      await _client.auth.signOut();
    } catch (e, st) {
      Log.error(
        'deleteAccount: post-delete signOut failed, forcing local sign-out',
        e,
        st,
      );
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Best-effort; the account is already deleted regardless.
      }
    }
  }
}
