import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/staff_auth_repository.dart';
import 'signin_state.dart';

/// Staff sign-in for the ops console.
///
/// Mixes in [ReentrancyGuard] rather than a bool flag: the guard claims its
/// key synchronously, before the first await, which is the ordering that
/// stops a double-tap landing two sign-in requests in the gap before a flag
/// would have been set.
class SignInCubit extends Cubit<SignInState> with ReentrancyGuard {
  SignInCubit(this._auth) : super(const SignInIdle());

  final StaffAuthRepository _auth;

  Future<void> submit({
    required String email,
    required String password,
  }) =>
      guard('submit', () async {
        emit(const SignInBusy());
        try {
          await _auth.signIn(email: email, password: password);

          if (await _auth.isStaff()) {
            emit(const SignInReady());
            return;
          }

          // Sign back out before refusing. RLS is the real boundary -- every
          // staff policy gates on private.is_staff() -- so a non-staff
          // session could read nothing anyway. But leaving one alive would
          // mean the console itself handed out an authenticated client it
          // then refused to use, and that is a worse shape than simply not
          // having one.
          await _auth.signOut();
          emit(const SignInRefused(AppStrings.opsNotStaff));
        } on AppFailure catch (f) {
          emit(SignInError(f.message));
        } catch (_) {
          emit(const SignInError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> signOut() => guard('signOut', () async {
        try {
          await _auth.signOut();
          emit(const SignInIdle());
        } on AppFailure catch (f) {
          emit(SignInError(f.message));
        } catch (_) {
          emit(const SignInError(AppStrings.somethingWentWrong));
        }
      });

  /// Called when any screen meets an [AuthFailure]: the session is gone, so
  /// the console returns to sign-in with a message that says why, rather
  /// than rendering a generic error on whatever screen the user was on.
  void sessionExpired() => emit(const SignInError(AppStrings.opsSessionExpired));
}
