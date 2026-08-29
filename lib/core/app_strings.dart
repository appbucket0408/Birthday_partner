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
  static const phoneSubtitle = 'We use it to find the people you already know.';
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

  // Onboarding — profile setup
  static const setupTitle = 'Tell us about you';
  static const setupName = 'Your name';
  static const setupHandle = 'Username';
  static const setupCity = 'City';
  static const setupBirthday = 'Your birthday';
  static const setupBirthdayHelp = 'The year is optional.';
  static const setupNameRequired = 'Please enter your name.';
  static const setupHandleRequired = 'Please pick a username.';
  static const setupBirthdayRequired = 'Please pick your birthday.';
  static const setupHandleTaken = 'That username is already taken.';
  static const setupNoYear = 'I would rather not say the year';
  static const finish = 'Finish';

  // Contacts import
  //
  // Deliberately no string here that names a suppressed contact. The API
  // itself never labels one either (Task 2: add_celebrations reports it as
  // the same opaque ImportStatus.skipped as any other non-actionable skip,
  // because a labelled status made the endpoint an oracle for who had asked
  // to be forgotten). It is folded into importSkippedTemplate with every
  // other skip and shown with no reason -- naming it would reveal to the
  // importer that the person asked to be removed. Do not add one.
  static const importDisclosureTitle = 'Find people you already know';
  static const importDisclosureBody =
      'Birthday reads the names and numbers in your contacts so you can pick '
      'who you want to celebrate. Your contacts are never stored on our '
      'servers and are never shared with anyone.';
  static const importDisclosureContinue = 'Continue';
  static const importDisclosureSkip = 'Not now';
  static const importPermissionDenied =
      'Birthday needs access to your contacts to find people you know. You '
      'can turn it on in Settings.';
  static const importPickTitle = 'Who do you celebrate?';
  static const importOnApp = 'On Birthday';
  static const importNoBirthday = 'No birthday';
  static const importAddSelected = 'Add selected';
  static const importFillTitle = 'Add their birthdays';
  static const importFillBody =
      'Your address book did not have a birthday for these people. You can '
      'add them now or later.';
  static const importSummaryTitle = 'Import complete';
  static const importAddedTemplate = '%s added';
  static const importSkippedTemplate = '%s skipped';
  static const importDuplicatesTemplate = '%s already in your list';
  static const importSelfSkipped = 'We skipped your own number.';
  static const importCouldNotAddTemplate = 'Could not add %s';
  static const importDone = 'Done';

  // Timeline
  static const timelineTitle = 'Celebrating';
  static const timelineToday = 'Today';
  static const timelineThisWeek = 'This week';
  static const timelineThisMonth = 'This month';
  static const timelineLater = 'Later';
  static const timelineEmptyTitle = 'Nobody yet';
  static const timelineEmptyBody =
      'Import your contacts to start celebrating the people you know.';
  static const timelineImportCta = 'Import contacts';
  static const timelineEditBirthday = 'Edit birthday';
  static const timelineEditNickname = 'Edit nickname';
  static const timelineStopCelebrating = 'Stop celebrating';
  static const timelineNoBirthdayYet = 'No birthday yet';
  static const timelineBirthdayNotEditable =
      'They are on Birthday, so only they can change their birthday.';
  static const timelineNicknameBlocked = 'You can no longer edit this person.';

  // Settings
  static const settingsTitle = 'Settings';
  static const settingsReminders = 'Birthday reminders';
  static const settingsRemindersBody =
      'Get a notification before each birthday you celebrate.';
  static const settingsSignOut = 'Sign out';
  static const settingsDeleteAccount = 'Delete account';
  static const settingsDeleteTitle = 'Delete your account?';
  static const settingsDeleteBody =
      'Your profile, the people you celebrate, and your wishes are deleted. '
      'People who celebrate you will keep a "Deleted user" in their list. '
      'This cannot be undone.';
  static const settingsDeleteConfirm = 'Delete everything';
}
