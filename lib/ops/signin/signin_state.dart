/// The ops console's sign-in states.
///
/// [SignInRefused] is deliberately distinct from [SignInError]: a refusal is
/// a correct, expected answer about who the caller is, while an error is
/// something going wrong. Folding them together would report a non-staff
/// account as a malfunction.
sealed class SignInState {
  const SignInState();
}

class SignInIdle extends SignInState {
  const SignInIdle();
}

class SignInBusy extends SignInState {
  const SignInBusy();
}

/// Signed in AND confirmed staff. The router admits the console's screens
/// only in this state.
class SignInReady extends SignInState {
  const SignInReady();
}

/// Authenticated, but not a staff account — and already signed back out.
class SignInRefused extends SignInState {
  const SignInRefused(this.message);
  final String message;
}

class SignInError extends SignInState {
  const SignInError(this.message);
  final String message;
}
