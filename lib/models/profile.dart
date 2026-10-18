import '../api/api_params.dart';
import 'birthday.dart';

/// A row in public.profiles.
///
/// The row is created by the private.handle_new_user trigger on signup, with a
/// placeholder handle ('u' + uuid without dashes) and display_name 'New user'.
/// Both are non-null from birth, so neither can tell a fresh account from a
/// finished one -- [hasCompletedOnboarding] reads the birthday instead, which
/// is required by the setup screen and null until it completes.
class Profile {
  const Profile({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.remindersEnabled,
    this.wishNotificationsEnabled = true,
    this.city,
    this.birthday,
    this.avatarPath,
  });

  final String id;
  final String handle;
  final String displayName;
  final bool remindersEnabled;
  final bool wishNotificationsEnabled;
  final String? city;
  final Birthday? birthday;
  final String? avatarPath;

  bool get hasCompletedOnboarding => birthday != null;

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
        id: row[ApiParams.id] as String,
        handle: row[ApiParams.handle] as String,
        displayName: row[ApiParams.displayName] as String,
        remindersEnabled: row[ApiParams.remindersEnabled] as bool,
        wishNotificationsEnabled:
            row[ApiParams.wishNotificationsEnabled] as bool? ?? true,
        city: row[ApiParams.city] as String?,
        birthday: Birthday.fromRow(row),
        avatarPath: row[ApiParams.avatarUrl] as String?,
      );
}
