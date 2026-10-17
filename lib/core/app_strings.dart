abstract final class AppStrings {
  // Generic
  static const appName = 'Birthday';
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

  // Onboarding — sign in (phone or email)
  static const signInTitle = 'Welcome to Birthday';
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

  // Person page
  static const personCelebratorCountTemplate = '%s people celebrate them';
  static const personCelebratorCountOne = '1 person celebrates them';
  static const personNoBirthday = 'No birthday recorded yet';
  static const personWallEmpty = 'No wishes yet. Be the first.';
  static const personWriteWish = 'Write a wish';
  static const wishAuthorUnknown = 'Someone who celebrates them';
  static const wishHint = 'Say something nice';
  static const wishPost = 'Post';
  static const wishTooLong = 'A wish can be at most 500 characters.';
  static const wishEmpty = 'Write something first.';
  static const wishPostFailed = 'That wish could not be posted.';

  // Bottom navigation
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

  // Profile
  static const profileTitle = 'You';
  static const profileCelebrating = 'Celebrating';
  static const profileCelebrates = 'Celebrates';
  static const profileWishesReceived = 'Wishes received';
  static const profileWishesSent = 'Wishes sent';
  static const profileWishWall = 'Wishes I received';
  static const profileWishWallEmpty = 'Wishes people send you show up here.';
  static const profileWishAuthorUnknown = 'Someone';
  static const profileCelebratingEmpty = 'You are not celebrating anyone yet.';
  static const profileCelebratesEmpty = 'Nobody celebrates you yet.';

  // Gifting
  static const giftSendCake = 'Send a cake';
  static const giftCatalogTitle = 'Choose a cake';
  static const giftAreaLabel = 'Delivering to';
  static const giftNoAreas = 'No delivery areas are available yet.';
  static const giftNoProducts = 'Nothing available in this area yet.';

  // A person reached cold via a deep link (or any context.go straight to
  // '/gift/new/:personId') bypasses the person page's own gate entirely, so
  // CatalogCubit.load must refuse a null birthday itself rather than trust
  // the caller already checked. Task 7 derives the occasion date from
  // Birthday.nextOccurrence, so a missing birthday cannot be worked around
  // further down the flow either -- there is no date to fall back to.
  static const giftNeedsBirthday =
      'Add their birthday first — a cake needs a date to arrive on.';

  // Gifting -- slot picker (Task 6). Slots are filtered to the occasion date
  // client-side (spec §11 open question 1: a cake dated anything other than
  // the birthday is a different product), so giftNoSlots is the expected,
  // common outcome locally -- not a bug -- until the seed data carries a slot
  // dated to a recipient's actual next birthday.
  static const giftSlotTitle = 'Pick a delivery window';
  static const giftSlotRemainingTemplate = '%s left';
  static const giftSlotFull = 'Full';
  static const giftNoSlots = 'No delivery windows are open for this area yet.';

  // Gifting -- draft screen (Task 7). The occasion date shown here is
  // handed down from the slot picker's own computation, never recomputed
  // (Amendment B1) -- see draft_cubit.dart's class doc.
  static const giftDraftTitle = 'Confirm the details';
  // The recipient's own displayName is threaded down verbatim from
  // CatalogLoaded.person (fix round 1, item 1) -- through SlotPickerScreen
  // and into DraftScreen -- never a PersonRepository re-fetch and never an
  // id-based fallback. `%s` is the name, not the id.
  static const giftDraftRecipientTemplate = 'For %s';
  static const giftMessageHint = 'Add a message (optional)';
  static const giftCreate = 'Reserve this slot';
  static const giftSlotJustFilled =
      'That slot just filled. Please pick another window.';
  // Whole-branch review §8 fold-in: DraftError.slotFull was set but never
  // read -- draft_screen.dart rendered only `state.message`, which already
  // says the slot filled, but gave no way back to a live one. This is the
  // action that field now drives.
  static const giftPickAnotherSlot = 'Choose another time';
  static const giftNotCelebrating =
      'You can only send a cake to someone you celebrate.';
  static const giftHoldNoticeTitle = 'Slot reserved for 15 minutes';
  static const giftHoldNoticeBody =
      'Checkout is not built yet, so this gift stays a draft and the slot is '
      'released when the hold expires. Nothing has been charged.';
  static const giftSeeMyGifts = 'See my gifts';

  // Gifting -- gift list (Task 8). Reached from the profile (spec §7): the
  // sender's own gifts and their status.
  static const giftListTitle = 'My gifts';
  static const giftListEmpty = 'You have not sent a cake yet.';
  // Every gift in this phase has a null deliveryCity -- nothing confirms one
  // yet (spec §6) -- so rendering nothing here would look like a bug rather
  // than the honest state it is.
  static const giftCityPending = 'Address not confirmed yet';
  static const giftCityTemplate = 'Delivering to %s';
  static const giftHoldExpired = 'Slot hold expired';

  // Not in the brief's Step-1 list; the brief describes each row as showing
  // "the product" but neither GiftListCubit nor Gift carries a product NAME
  // -- only Gift.productId, an int. Threading a name would need either a
  // ProductRepository this cubit's interfaces don't authorize
  // (`GiftListCubit(GiftRepository, {now})` per the brief) or a join added to
  // GiftRepositoryImpl.myGifts(), which is out of this task's file list. The
  // same shape as Task 7's F6 (recipient shown by id): disclosed, not hidden.
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
