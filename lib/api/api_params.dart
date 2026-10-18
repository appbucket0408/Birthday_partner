/// Column names and RPC argument names. Typos here are runtime errors that
/// PostgREST reports as "column does not exist", so they live in one place.
abstract final class ApiParams {
  // tables
  static const profiles = 'profiles';
  static const people = 'people';
  static const celebrations = 'celebrations';
  static const deviceTokens = 'device_tokens';

  // device_tokens
  static const token = 'token';
  static const platform = 'platform';
  static const rpcRegisterDeviceToken = 'register_device_token';
  static const pToken = 'p_token';
  static const pPlatform = 'p_platform';

  // profiles
  static const id = 'id';
  static const profileId = 'profile_id';
  static const handle = 'handle';
  static const displayName = 'display_name';
  static const city = 'city';
  static const remindersEnabled = 'reminders_enabled';
  static const wishNotificationsEnabled = 'wish_notifications_enabled';

  /// The profile photo's Storage PATH inside the `avatars` bucket, not a URL
  /// (see 20261017000001_avatars.sql).
  static const avatarUrl = 'avatar_url';
  static const avatarsBucket = 'avatars';

  /// Read by the ops console to explain a refusal. Never written from a
  /// client: `authenticated` has no update grant on this column
  /// (20260822000003_profiles.sql:54), and it is a DBA action by design.
  static const isStaff = 'is_staff';

  // birthday parts, on both people and profiles
  static const birthMonth = 'birth_month';
  static const birthDay = 'birth_day';
  static const birthYear = 'birth_year';

  // celebrations
  static const celebratorProfileId = 'celebrator_profile_id';
  static const personId = 'person_id';
  static const source = 'source';

  static const pPersonId = 'p_person_id';

  // wishes
  static const wishes = 'wishes';
  static const authorProfileId = 'author_profile_id';
  static const subjectPersonId = 'subject_person_id';
  static const body = 'body';
  static const kind = 'kind';
  static const occasionYear = 'occasion_year';
  static const createdAt = 'created_at';

  /// The wish photo's Storage PATH inside the `wish_photos` bucket, not a URL
  /// (see 20261018000001_wish_photos.sql).
  static const photoPath = 'photo_path';
  static const wishPhotosBucket = 'wish_photos';

  // my_notifications
  static const seen = 'seen';
  static const wishId = 'wish_id';
  static const offsetDays = 'offset_days';

  // feed_page
  static const pBefore = 'p_before';
  static const pLimit = 'p_limit';
  static const authorName = 'author_name';
  static const subjectName = 'subject_name';
  static const canOpenSubject = 'can_open_subject';

  // my_birthday_stats
  static const statYear = 'stat_year';
  static const wishesSent = 'wishes_sent';
  static const wishesReceived = 'wishes_received';
  static const birthdaysCelebrated = 'birthdays_celebrated';

  // my_celebrates
  static const celebratorPersonId = 'celebrator_person_id';

  // catalog
  static const serviceAreas = 'service_areas';
  static const products = 'products';
  static const deliverySlots = 'delivery_slots';
  static const gifts = 'gifts';
  static const serviceAreaId = 'service_area_id';
  static const name = 'name';
  static const flavour = 'flavour';
  static const size = 'size';
  static const priceMinor = 'price_minor';
  static const imageUrl = 'image_url';
  static const isActive = 'is_active';
  static const slotDate = 'slot_date';
  static const windowStart = 'window_start';
  static const windowEnd = 'window_end';
  static const capacity = 'capacity';
  static const reserved = 'reserved';

  // gifts
  static const senderProfileId = 'sender_profile_id';
  static const recipientPersonId = 'recipient_person_id';
  static const productId = 'product_id';
  static const slotId = 'slot_id';
  static const occasionDate = 'occasion_date';
  static const amountMinor = 'amount_minor';
  static const status = 'status';
  static const message = 'message';
  static const deliveryCity = 'delivery_city';
  static const slotHoldExpiresAt = 'slot_hold_expires_at';

  // rpc_create_gift
  static const pRecipientPersonId = 'p_recipient_person_id';
  static const pProductId = 'p_product_id';
  static const pSlotId = 'p_slot_id';
  static const pOccasionDate = 'p_occasion_date';
  static const pMessage = 'p_message';
}
