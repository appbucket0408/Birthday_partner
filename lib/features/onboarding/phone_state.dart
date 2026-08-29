sealed class PhoneState {
  const PhoneState();
}

final class PhoneIdle extends PhoneState {
  const PhoneIdle();
}

final class PhoneSending extends PhoneState {
  const PhoneSending();
}

/// The code screen. [error] is non-null after a rejected code, so the user
/// stays here with their number intact rather than being thrown out.
final class PhoneCodeSent extends PhoneState {
  const PhoneCodeSent(this.phoneE164, {this.error});
  final String phoneE164;
  final String? error;
}

final class PhoneVerifying extends PhoneState {
  const PhoneVerifying(this.phoneE164);
  final String phoneE164;
}

final class PhoneVerified extends PhoneState {
  const PhoneVerified();
}

final class PhoneError extends PhoneState {
  const PhoneError(this.message);
  final String message;
}
