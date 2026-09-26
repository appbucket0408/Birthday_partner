/// Staff sign-in for the ops console. One responsibility; deliberately NOT
/// folded into [AuthRepository], which owns the consumer flow — phone OTP,
/// person claiming, and account deletion.
///
/// The console uses email and password rather than phone OTP for a concrete
/// reason: OTP needs a live SMS provider, which this project does not have
/// yet, and inheriting that dependency would leave the console as unusable as
/// the confirm page. `[auth.email] enable_confirmations` is false, so an
/// administrator-provisioned account sends no email at all and needs no SMTP.
///
/// Accounts are created by an administrator, never here:
/// `admin.auth.admin.createUser(...)` followed by a DBA
/// `update public.profiles set is_staff = true`. `is_staff` is not writable by
/// `authenticated` (20260822000003_profiles.sql:54), and nothing in this
/// interface may set it.
abstract interface class StaffAuthRepository {
  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  /// The signed-in caller's own `profiles.is_staff`. False when there is no
  /// session — a signed-out caller is not an error here.
  ///
  /// This is for legibility, not security. Every staff policy
  /// (`service_areas_staff_write`, `products_staff_write`,
  /// `delivery_slots_staff_write`) gates on `private.is_staff()` server-side,
  /// so a non-staff session that somehow reached a console screen would read
  /// and write nothing. Checking here only lets the refusal say why.
  Future<bool> isStaff();
}
