import '../../models/birthday.dart';
import '../../models/profile.dart';

/// The signed-in user as providers see it; each one picks what it may send.
class AnalyticsUser {
  const AnalyticsUser({required this.id, this.phone, this.birthday, this.city});

  factory AnalyticsUser.fromProfile(Profile profile, {String? phone}) =>
      AnalyticsUser(
        id: profile.id,
        phone: phone,
        birthday: profile.birthday,
        city: profile.city,
      );

  final String id;

  /// E.164 digits without '+', as Supabase stores it.
  final String? phone;
  final Birthday? birthday;
  final String? city;
}
