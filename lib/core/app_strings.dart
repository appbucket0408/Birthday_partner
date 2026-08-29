abstract final class AppStrings {
  // Generic
  static const appName = 'Birthday';
  static const retry = 'Try again';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const somethingWentWrong = 'Something went wrong. Please try again.';
  static const noConnection = 'No internet connection.';

  // Onboarding — phone
  static const phoneTitle = 'What is your number?';
  static const phoneSubtitle =
      'We use it to find the people you already know.';
  static const phoneHint = 'Phone number';
  static const phoneInvalid = 'That does not look like a valid number.';
  static const sendCode = 'Send code';
  static const otpTitle = 'Enter the code';
  static const otpSubtitleTemplate = 'We sent a 6-digit code to %s.';
  static const otpHint = '6-digit code';
  static const otpIncorrect = 'That code is not right.';
  static const otpExpired = 'That code has expired. Ask for a new one.';
  static const resendCode = 'Resend code';
  static const resendCooldownTemplate = 'Resend in %ss';
  static const claimConflict =
      'This account is already linked to a different phone number.';
}
