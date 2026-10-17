sealed class PhoneState {
  const PhoneState();
}

final class PhoneIdle extends PhoneState {
  const PhoneIdle();
}

final class PhoneSending extends PhoneState {
  const PhoneSending();
}

/// The code screen. [destination] is where the code went: an E.164 number or
/// an email address. [error] is non-null after a rejected code, so the user
/// stays here with their input intact rather than being thrown out.
final class PhoneCodeSent extends PhoneState {
  const PhoneCodeSent(this.destination, {this.error});
  final String destination;
  final String? error;
}

final class PhoneVerifying extends PhoneState {
  const PhoneVerifying(this.destination);
  final String destination;
}

/// Signed in. [welcomeName] is set for a returning user who has already
/// finished signing up, so the code screen can greet them before the router
/// moves on; null for a new user, who goes straight to sign-up.
final class PhoneVerified extends PhoneState {
  const PhoneVerified({this.welcomeName});
  final String? welcomeName;
}

final class PhoneError extends PhoneState {
  const PhoneError(this.message);
  final String message;
}
