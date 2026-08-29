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

  // profiles
  static const id = 'id';
  static const profileId = 'profile_id';
  static const handle = 'handle';
  static const displayName = 'display_name';
  static const city = 'city';
  static const remindersEnabled = 'reminders_enabled';

  // birthday parts, on both people and profiles
  static const birthMonth = 'birth_month';
  static const birthDay = 'birth_day';
  static const birthYear = 'birth_year';

  // celebrations
  static const celebratorProfileId = 'celebrator_profile_id';
  static const personId = 'person_id';
  static const nickname = 'nickname';
  static const source = 'source';

  // rpc_update_person_birthday
  static const pPersonId = 'p_person_id';
  static const pBirthMonth = 'p_birth_month';
  static const pBirthDay = 'p_birth_day';
  static const pBirthYear = 'p_birth_year';

  // wishes
  static const wishes = 'wishes';
  static const authorProfileId = 'author_profile_id';
  static const subjectPersonId = 'subject_person_id';
  static const body = 'body';
  static const kind = 'kind';
  static const occasionYear = 'occasion_year';
  static const createdAt = 'created_at';

  // my_birthday_stats
  static const statYear = 'stat_year';
  static const wishesSent = 'wishes_sent';
  static const wishesReceived = 'wishes_received';
  static const birthdaysCelebrated = 'birthdays_celebrated';

  // my_celebrates
  static const celebratorPersonId = 'celebrator_person_id';
}
