import '../models/birthday.dart';
import 'app_strings.dart';

/// Month names for the few places that print a date. The app has no `intl`
/// dependency, and English month names do not justify adding one.
abstract final class DateLabels {
  static const months = [
    'January', 'February', 'March', 'April', 'May', 'June', // ignore: require_trailing_commas
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', // ignore: require_trailing_commas
    'Sunday',
  ];

  /// "12 March". The year is left off even when known: it is an age, not
  /// part of the birthday a reader recognises.
  static String birthday(Birthday birthday) =>
      '${birthday.day} ${months[birthday.month - 1]}';

  /// "October 2026".
  static String monthYear(DateTime date) =>
      '${months[date.month - 1]} ${date.year}';

  /// "Saturday, 21 October".
  static String dayHeading(DateTime date) =>
      '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';

  /// How long ago, the way a feed says it: "Just now", "12m", "3h",
  /// "Yesterday", then "17 October" -- with the year only when it is not
  /// this one.
  static String ago(DateTime date, DateTime now) {
    final local = date.toLocal();
    final current = now.toLocal();
    final elapsed = current.difference(local);
    if (elapsed.inMinutes < 1) return AppStrings.feedJustNow;
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '${elapsed.inHours}h';
    if (days == 1) return AppStrings.feedYesterday;
    final label = '${local.day} ${months[local.month - 1]}';
    return local.year == current.year ? label : '$label ${local.year}';
  }

  /// "21 October 2026", in local time -- when a wish was posted.
  static String posted(DateTime date) {
    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
