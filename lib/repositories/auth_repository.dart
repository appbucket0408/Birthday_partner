import '../models/birthday.dart';
import '../models/profile.dart';

/// Everything the app does with identity. The split from the implementation is
/// what keeps the data source swappable -- the spec's justification for using
/// the Supabase client directly instead of the house dio layer.
abstract interface class AuthRepository {
  String? get currentUserId;

  /// Sends the OTP. Locally this is served from [auth.sms.test_otp]; no SMS
  /// provider is configured and none is needed until Phase 2c.
  Future<void> sendOtp(String phoneE164);

  Future<void> verifyOtp({required String phoneE164, required String token});

  /// Links this session's verified phone to its person row. Returns the
  /// person id. Throws [ServerFailure] with code '409' when the profile has
  /// already claimed a different number.
  Future<int> claimProfile();

  Future<Profile> loadProfile();

  /// An UPDATE. The profiles row already exists -- private.handle_new_user
  /// creates it on signup. Throws [ServerFailure] with code '23505' when the
  /// handle is taken.
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  });

  Future<void> signOut();

  Future<void> deleteAccount();
}
