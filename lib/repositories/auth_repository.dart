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

  /// Sends a 6-digit sign-in code by email, creating the account if the
  /// address is new. Locally the mail lands in Mailpit (port 54324).
  Future<void> sendEmailOtp(String email);

  Future<void> verifyEmailOtp({required String email, required String token});

  /// Whether this session's user has a verified phone. Phone sign-ins always
  /// do; an email sign-in does not until [verifyPhoneLink] succeeds, and
  /// [claimProfile] refuses a session without one.
  bool get hasVerifiedPhone;

  /// Starts attaching [phoneE164] to the signed-in (email) account by
  /// texting it a code. Throws [AuthFailure] with
  /// `AppStrings.phoneAlreadyRegistered` when another account owns it.
  Future<void> sendPhoneLink(String phoneE164);

  /// Confirms [sendPhoneLink]'s code. On success the phone is verified on
  /// this account and [claimProfile] can run.
  Future<void> verifyPhoneLink({
    required String phoneE164,
    required String token,
  });

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
