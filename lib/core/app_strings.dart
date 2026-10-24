abstract final class AppStrings {
  // Generic
  static const appName = 'Candlewish';
  static const retry = 'Try again';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const somethingWentWrong = 'Something went wrong. Please try again.';
  static const noConnection = 'No internet connection.';

  // Router -- errorBuilder (whole-branch review §8 should-fix 4). Shown for
  // ANY unmatched location, not just the one instance ('/gifts') that was
  // fixed by adding a real route: with no errorBuilder configured at all,
  // every other typo or dead link still lands on go_router's own default
  // error page, which has no way back into the app.
  static const routeNotFoundTitle = 'Page not found';
  static const routeNotFoundBody =
      "That page doesn't exist, or the link is out of date.";
  static const routeNotFoundAction = 'Go to timeline';

  // Force update -- Remote Config's min_supported_build is above this build.
  static const forceUpdateTitle = 'A better Candlewish is ready';
  static const forceUpdateBody =
      "Your friends' wishes are waiting. Update now to keep every birthday "
      'reminder and wish coming your way. It only takes a moment.';
  static const forceUpdateAction = 'Get the update';

  // Soft update -- Remote Config's latest_build is above this build.
  static const softUpdateTitle = 'Something new is here';
  static const softUpdateBody =
      'A fresh version of Candlewish is ready, with improvements to help '
      'you celebrate the people you love. It only takes a moment.';
  static const softUpdateAction = 'Update';
  static const softUpdateLater = 'Later';

  // Onboarding — sign in (phone; email only in EMAIL_SIGN_IN test builds)
  static const signInTitle = 'Welcome to Candlewish';
  static const signInSubtitle =
      'Never miss the birthdays of the people you love.';
  static const signInPhoneTab = 'Phone';
  static const signInEmailTab = 'Email';
  static const phoneHint = 'Phone number';
  static const phoneInvalid = 'That does not look like a valid number.';
  static const emailHint = 'Email address';
  static const emailInvalid = 'That does not look like a valid email.';
  static const sendCode = 'Send code';
  static const otpTitle = 'Enter the code';
  static const otpSubtitle = 'We sent a 6-digit code to';
  static const otpChange = 'Change';
  static const otpVerify = 'Verify';
  static const otpIncorrect = 'That code is not right.';
  static const otpExpired = 'That code has expired. Ask for a new one.';
  static const resendCode = 'Resend code';
  static const resendCooldownTemplate = 'Resend code in %ss';
  static const claimConflict =
      'This account is already linked to a different phone number.';
  static const welcomeBackTemplate = 'Welcome back, %s';
  static const welcomeBackBody = 'Opening your dashboard…';

  // Onboarding — sign up (profile setup)
  static const setupTitle = 'Create your profile';
  static const setupSubtitle = 'So your friends can find and celebrate you.';
  static const setupName = 'Full name';
  static const setupHandle = 'Username';
  static const setupCity = 'City';
  static const setupBirthday = 'Birthday';
  static const setupBirthdayPick = 'Pick your birthday';
  static const setupNameRequired = 'Please enter your name.';
  static const setupHandleRequired = 'Please pick a username.';
  static const setupBirthdayRequired = 'Please pick your birthday.';
  static const setupHandleTaken = 'That username is already taken.';
  static const setupNoYear = 'Hide my birth year';
  static const setupSubmit = 'Create account';
  static const setupSignOut = 'Not you? Sign out';
  static const setupAddPhoto = 'Add a photo';
  static const setupChangePhoto = 'Change photo';

  // Profile photo
  static const photoFromGallery = 'Choose from gallery';
  static const photoFromCamera = 'Take a photo';
  static const photoRemove = 'Remove photo';
  static const photoUnsupported = 'Please choose a JPG, PNG or WebP photo.';
  static const photoUploadFailed = 'Your photo could not be uploaded.';

  // Sign up — linking a phone to an email account. The phone is how friends
  // find you, so an email sign-up must verify one before it can finish.
  static const linkPhoneTitle = 'Your phone number';
  static const linkPhoneBody =
      'Friends find you by the number saved in their contacts. We text you a '
      'code to confirm it is yours.';
  static const linkPhoneVerified = 'Phone number verified';
  static const linkPhoneRequired = 'Please verify your phone number first.';
  static const phoneAlreadyRegistered =
      'This number already has an account. Sign out and sign in with it '
      'instead.';

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
  // Play's prominent disclosure: WHAT is read and WHY, stated on this screen
  // before the permission prompt. Keep both halves in this sentence.
  static const importDisclosureBody =
      'Candlewish reads the names and numbers in your contacts so you can pick '
      'who you want to celebrate.';
  static const importTrustStaysTitle = 'Stays on your phone';
  static const importTrustStaysBody =
      'Your contacts are never stored on our servers.';
  static const importTrustSharedTitle = 'Never shared';
  static const importTrustSharedBody =
      'Nobody is messaged or told that you looked them up.';
  static const importTrustChooseTitle = 'You choose';
  static const importTrustChooseBody =
      'Nobody is added until you pick them.';
  static const importDisclosureContinue = 'Continue';
  static const importDisclosureSkip = 'Not now';
  static const importPermissionDenied =
      'Candlewish needs access to your contacts to find people you know. You '
      'can turn it on in Settings.';
  static const importPickTitle = 'Who do you celebrate?';
  static const importOnApp = 'On Candlewish';
  static const importOnAppHint = "You'll get their birthday and reminders.";
  static const importNotOnApp = 'Not on Candlewish yet';
  static const importNotOnAppHint =
      'Their birthday shows up once they join. You can invite them from your '
      'Dashboard.';
  static const importSelectPrompt = 'Select people to add';
  static const importAddOne = 'Add 1 person';
  static const importAddManyTemplate = 'Add %s people';
  static const importSelectAll = 'Select all';
  static const importClearAll = 'Clear';
  static const importNoContacts = 'No contacts with a phone number found.';
  static const importAddedOne = 'You added 1 person';
  static const importAddedManyTemplate = 'You added %s people';
  static const importAddedNone = 'Nobody new to add';
  static const importAddedFailed = 'Nothing was added yet';
  static const importAddedBody = "They're on your Dashboard now.";
  static const importAddedNoneBody =
      'Everyone you picked was already in your list.';
  static const importFailedTemplate =
      "%s couldn't be added just now. Try again in a moment.";
  static const importInvalidTitle = "These numbers couldn't be added:";
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
  static const timelineAddPeople = 'Add people';
  static const timelineAddPeopleHint = 'Find friends from your contacts';
  static const timelineStopCelebrating = 'Stop celebrating';
  static const timelineWaitingToJoin = 'Waiting to join';
  static const timelineWaitingToJoinHint =
      "They aren't on Candlewish yet. Their birthday shows up here once they "
      'join.';
  static const timelineInvite = 'Invite';

  /// %1 is their name, %2 the download link.
  static const inviteMessageTemplate =
      "Hi %1! I've added you on Candlewish so I never miss your day 🎂 Join and "
      'add your birthday: %2';

  // Settings
  static const settingsTitle = 'Settings';
  static const settingsSectionNotifications = 'Notifications';
  static const settingsSectionAccount = 'Account';
  static const settingsReminders = 'Birthday reminders';
  static const reminderChannelName = 'Birthday reminders';
  static const reminderChannelDescription =
      'A heads-up before the birthdays you celebrate.';
  static const wishChannelName = 'New wishes';
  static const wishChannelDescription =
      'When someone leaves a wish on your wall.';
  static const settingsRemindersBody =
      'Get a notification before each birthday you celebrate.';
  static const settingsWishNotifications = 'New wishes';
  static const settingsWishNotificationsBody =
      'Get a notification when someone leaves a wish on your wall.';
  static const settingsSignOut = 'Sign out';
  static const settingsDeleteAccount = 'Delete account';
  static const settingsDeleteTitle = 'Delete your account?';
  static const settingsDeleteBody =
      'Your profile, the people you celebrate, and your wishes are deleted. '
      'People who celebrate you will keep a "Deleted user" in their list. '
      'This cannot be undone.';
  static const settingsDeleteConfirm = 'Delete everything';

  // Person page
  static const personCelebratorCountTemplate = '%s people celebrate them';
  static const personCelebratorCountOne = '1 person celebrates them';
  static const personNoBirthday = 'Not on Candlewish yet';
  static const personNoBirthdayHint =
      'Their birthday shows up here once they join.';
  static const personToday = '🎉 Birthday today!';
  static const personTomorrow = 'Tomorrow';
  static const personInDaysTemplate = 'in %s days';
  static const personWishesTitle = 'Wishes';
  static const personWallEmpty = 'No wishes yet. Be the first.';
  static const personWriteWish = 'Write a wish';
  static const personWishOnBirthday =
      'You can write them a wish on their birthday.';
  static const personWishOpensTemplate = 'Wishes open on %s';
  static const wishAuthorUnknown = 'Someone who celebrates them';
  static const wishHint = 'Say something nice 🎂';
  static const wishComposerTitle = 'Create a wish';
  static const wishComposerForTemplate = 'Wishing %s a happy birthday';
  static const wishSheetSubtitle = 'Your wish shows on their wish wall.';
  static const wishSheetPublicSubtitle =
      'Public: your wish shows on their wall and in the feed, where everyone '
      'on Candlewish can see it.';
  static const wishSuggestions = [
    'Happy birthday! 🎂',
    'Have an amazing year ahead ✨',
    'Wishing you all the happiness 💛',
    'Many happy returns of the day! 🎉',
  ];
  static const wishPost = 'Post wish';
  static const wishTooLong = 'A wish can be at most 250 characters.';
  // wishes_one_message_per_year: one typed wish per person per birthday year.
  static const wishAlreadyThisYear =
      'You have already wished them for this birthday.';
  static const wishEmpty = 'Write something first.';
  static const wishPostFailed = 'That wish could not be posted.';
  static const wishPosting = 'Posting your wish…';
  static const wishPosted = 'Wish posted';
  static const wishAddPhoto = 'Add a photo';
  static const wishAddPhotoHint = 'One photo from your gallery';
  static const wishReplacePhoto = 'Replace';
  static const wishRemovePhoto = 'Remove photo';
  static const wishPhotoUploadFailed =
      'Your photo could not be uploaded. Nothing was posted -- try again.';
  static const wishPhotoAccessDenied =
      'Allow photo access in Settings to add a photo.';
  static const wishPhotoUnreadable = 'That photo could not be opened.';
  static const wishPhotoTooLarge =
      'That photo is too large. Please choose another.';
  static const wishPostTitle = 'Wish';

  // Feed
  // Notifications screen and bell.
  static const notificationsTitle = 'Notifications';
  static const notificationsBellTooltip = 'Notifications';
  static const notificationsEmptyTitle = 'Nothing yet';
  static const notificationsEmptyBody =
      'Birthday reminders and wishes people leave you will show up here.';
  static const notificationWishTemplate = '%s left you a birthday wish.';
  static const notificationTodayTemplate = "It's %s's birthday today.";
  static const notificationTomorrowTemplate = "%s's birthday is tomorrow.";
  static const notificationInDaysTemplate = "%1's birthday is in %2 days.";
  static const notificationOther = 'Something new for you.';
  static const notificationSomeone = 'Someone';
  // The banner shown when Android has notifications turned off for the app.
  static const notificationsOffTitle = 'Notifications are off on this phone';
  static const notificationsOffBody =
      "You won't get birthday reminders or wish alerts until you turn them on.";
  static const notificationsTurnOn = 'Turn on';

  static const feedTitle = 'Feed';
  static const feedWished = 'wished';
  static const feedSentCakeTo = 'sent a cake to';
  static const feedJustNow = 'Just now';
  static const feedYesterday = 'Yesterday';
  static const feedCakeBody = 'Sent a birthday cake 🎂';
  static const feedAuthorUnknown = 'Someone';
  static const feedSubjectUnknown = 'someone';
  static const feedEmptyTitle = 'Your feed is quiet';
  static const feedEmptyBody =
      'Birthday wishes and photos from the people you celebrate show up '
      'here. Add people, and wish them on their birthday to share the '
      'first one.';
  static const feedSeeBirthdays = 'See upcoming birthdays';
  static const feedLoadMoreFailed = 'Older wishes could not be loaded.';
  static const feedEnd = "You're all caught up";
  static const feedEndBody = "That's every wish from your circle for now.";
  static const feedBackToTop = 'Back to top';

  // Bottom navigation
  static const navFeed = 'Feed';
  static const navDashboard = 'Dashboard';
  static const navCalendar = 'Calendar';
  static const navProfile = 'Profile';

  // Calendar
  static const calendarTitle = 'Calendar';
  static const calendarPreviousMonth = 'Previous month';
  static const calendarNextMonth = 'Next month';
  static const calendarNoBirthdays = 'No birthdays on this day.';
  static const calendarTurnsTemplate = 'turns %s';
  static const calendarYearUnknown = 'year unknown';
  static const calendarToday = 'Today';
  static const calendarNoneThisMonth = 'No birthdays this month';
  static const calendarOneThisMonth = '1 birthday this month';
  static const calendarManyThisMonthTemplate = '%s birthdays this month';
  static const calendarNextTemplate = 'Next: %1 · %2';
  static const calendarNobodyYet =
      'Birthdays of the people you celebrate show up here.';

  // Profile
  static const profileTitle = 'You';
  static const profileCelebrating = 'I celebrate';
  static const profileCelebrates = 'Celebrate me';
  static const celebratesYou = 'Celebrates you';
  static const celebrateBack = 'Celebrate back';
  static const celebratingAlready = 'Celebrating';
  static const profileWishesReceived = 'Wishes received';
  static const profileWishesSent = 'Wishes sent';
  static const profileWishWall = 'Wishes I received';
  static const profileWishWallEmptyTitle = 'No wishes yet';
  static const profileWishWallEmpty =
      'When friends wish you, their notes appear here.';
  static const profileInviteFriends = 'Invite friends';

  /// %1 is the user's handle, %2 the download link.
  static const profileInviteMessageTemplate =
      "I'm on Candlewish so I never miss a friend's day 🎂 Add me (@%1) and "
      'add your birthday too: %2';
  static const profileWishAuthorUnknown = 'Someone';
  static const profileCelebratingEmpty = 'You are not celebrating anyone yet.';
  static const profileCelebratesEmpty = 'Nobody celebrates you yet.';

  // Connections (the I celebrate / Celebrate me screen)
  static const connectionsSearch = 'Search';
  static const connectionsNoMatchesTemplate = 'No one matches "%s".';
  static const connectionsCelebratesEmptyHint =
      'When someone adds you, they show up here.';
  static const connectionsStopTitleTemplate = 'Stop celebrating %s?';
  static const connectionsStopBody =
      "They'll leave your Dashboard and Calendar, and you won't get reminders "
      'for their birthday. You can add them again any time.';

  // Gifting -- "Send a cake" is a Coming soon screen until payments exist.
  static const cakeComingSoonBadge = 'COMING SOON';
  static const cakeTitleTemplate = 'Send %s a birthday cake';
  static const cakeYourFriend = 'your friend';
  static const cakeSubtitle =
      "We're baking something special: a fresh cake at their door on their "
      'birthday, ordered right here.';
  static const cakeFeatureFreshTitle = 'Fresh from local bakeries';
  static const cakeFeatureFreshBody = 'Baked the same day, never frozen.';
  static const cakeFeatureDeliveryTitle = 'Delivered on the day';
  static const cakeFeatureDeliveryBody =
      'Pick a time slot; they share their address, you never need it.';
  static const cakeFeatureNoteTitle = 'With your note';
  static const cakeFeatureNoteBody = 'A personal message arrives with the cake.';
  static const cakeNotifyMe = "Notify me when it's live";
  static const cakeRegisteredTitle = "You're on the list";
  static const cakeRegisteredBody =
      "We'll let you know the moment cake gifting opens.";

  // Gifting
  static const giftSendCake = 'Send a cake';
  static const giftCatalogTitle = 'Choose a cake';
  static const giftAreaLabel = 'Delivering to';
  static const giftNoAreas = 'No delivery areas are available yet.';
  static const giftNoProducts = 'Nothing available in this area yet.';
  static const giftNeedsBirthday =
      'Add their birthday first — a cake needs a date to arrive on.';
  static const giftSlotTitle = 'Pick a delivery window';
  static const giftSlotRemainingTemplate = '%s left';
  static const giftSlotFull = 'Full';
  static const giftNoSlots = 'No delivery windows are open for this area yet.';
  static const giftDraftTitle = 'Confirm the details';
  static const giftDraftRecipientTemplate = 'For %s';
  static const giftMessageHint = 'Add a message (optional)';
  static const giftCreate = 'Reserve this slot';
  static const giftSlotJustFilled =
      'That slot just filled. Please pick another window.';
  static const giftPickAnotherSlot = 'Choose another time';
  static const giftNotCelebrating =
      'You can only send a cake to someone you celebrate.';
  static const giftHoldNoticeTitle = 'Slot reserved for 15 minutes';
  static const giftHoldNoticeBody =
      'Checkout is not built yet, so this gift stays a draft and the slot is '
      'released when the hold expires. Nothing has been charged.';
  static const giftSeeMyGifts = 'See my gifts';
  static const giftListTitle = 'My gifts';
  static const giftListEmpty = 'You have not sent a cake yet.';
  static const giftCityPending = 'Address not confirmed yet';
  static const giftCityTemplate = 'Delivering to %s';
  static const giftHoldExpired = 'Slot hold expired';
  static const giftProductTemplate = 'Product #%s';

  // GiftStatus carries eleven DB states plus an `unknown` fallback (Task 3);
  // every one needs a human label on the list row.
  static const giftStatusDraft = 'Draft';
  static const giftStatusPaid = 'Paid';
  static const giftStatusAwaitingConfirm = 'Awaiting confirmation';
  static const giftStatusConfirmed = 'Confirmed';
  static const giftStatusPlaced = 'Placed';
  static const giftStatusOutForDelivery = 'Out for delivery';
  static const giftStatusDelivered = 'Delivered';
  static const giftStatusExpired = 'Expired';
  static const giftStatusDeclined = 'Declined';
  static const giftStatusDeliveryFailed = 'Delivery failed';
  static const giftStatusRefunded = 'Refunded';
  static const giftStatusUnknown = 'Unknown';

  // Ops console (M4 Phase 1). A separate web entry point; these never appear
  // in the consumer app.
  static const opsTitle = 'Ops console';
  static const opsEmail = 'Email';
  static const opsPassword = 'Password';
  static const opsSignIn = 'Sign in';
  static const opsSignOut = 'Sign out';
  static const opsNotStaff = 'That account is not a staff account.';
  static const opsSessionExpired =
      'Your session has expired. Please sign in again.';
  static const opsCatalogTab = 'Catalog';
  static const opsSlotsTab = 'Delivery slots';
  static const opsNotFound = 'That page does not exist.';
  static const opsBackToCatalog = 'Back to the catalog';

  // Ops catalog (Task 4)
  static const opsAddProduct = 'Add product';
  static const opsProductName = 'Name';
  static const opsProductFlavour = 'Flavour (optional)';
  static const opsProductSize = 'Size (optional)';
  static const opsProductPrice = 'Price in rupees';
  static const opsPriceInvalid =
      'Enter a price greater than zero, with at most two decimal places.';
  static const opsNameRequired = 'A product needs a name.';
  static const opsActive = 'Active';
  static const opsInactive = 'Inactive';
  static const opsNoAreas = 'No service areas exist yet.';
  static const opsNoProducts = 'No products in this area yet.';

  // Ops delivery slots (Task 5)
  static const opsAddSlot = 'Add delivery window';
  static const opsSlotDate = 'Date';
  static const opsWindowStart = 'Starts';
  static const opsWindowEnd = 'Ends';
  static const opsCapacity = 'Capacity';
  static const opsReservedTemplate = '%s reserved';
  static const opsWindowOrder = 'The window must end after it starts.';
  static const opsCapacityBelowReservedTemplate =
      'Capacity cannot go below the %s already reserved.';
  static const opsCapacityNegative = 'Capacity cannot be negative.';
  static const opsDuplicateWindow =
      'A window already starts at that time on that date.';
  static const opsNoSlots = 'No delivery windows in this range.';
  static const opsDateInvalid = 'Enter the date as YYYY-MM-DD.';
}
