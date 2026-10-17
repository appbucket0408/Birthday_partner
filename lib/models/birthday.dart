import '../api/api_params.dart';

/// Where a birthday sits relative to today. The boundaries are chosen, not
/// obvious: Today is day 0, This week is days 1-7, This month is days 8-31,
/// and anything further out is Later.
enum TimelineGroup { today, thisWeek, thisMonth, later }

/// Month and day are required together; the year is optional because device
/// address books routinely carry a birthday with no year, and reminders only
/// ever need month and day.
class Birthday {
  const Birthday({required this.month, required this.day, this.year});

  final int month;
  final int day;
  final int? year;

  static Birthday? fromRow(Map<String, dynamic> row) {
    final month = row[ApiParams.birthMonth] as int?;
    final day = row[ApiParams.birthDay] as int?;
    if (month == null || day == null) return null;
    return Birthday(
      month: month,
      day: day,
      year: row[ApiParams.birthYear] as int?,
    );
  }

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  /// The next date this birthday is celebrated on or after [from].
  ///
  /// A Feb 29 birthday falls on **Feb 28** in non-leap years. This keeps the
  /// celebration inside February rather than sliding into March, and it is the
  /// same rule the pg_cron reminder fan-out uses -- the two must not disagree.
  DateTime nextOccurrence(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final thisYear = inYear(today.year);
    return thisYear.isBefore(today) ? inYear(today.year + 1) : thisYear;
  }

  /// The date this birthday is celebrated on in [year], with the Feb 29 rule
  /// above applied. Public so the calendar marks a leap-day birthday on the
  /// same day the timeline and the reminder fan-out treat as the birthday.
  DateTime inYear(int year) {
    if (month == 2 && day == 29 && !isLeapYear(year)) {
      return DateTime(year, 2, 28);
    }
    return DateTime(year, month, day);
  }

  /// Whether [day] is this birthday -- the only day a wish can be written.
  /// Uses [inYear], so a Feb 29 birthday is on Feb 28 in a non-leap year,
  /// the same day the countdown and the reminders treat as the birthday.
  bool isOn(DateTime day) {
    final date = inYear(day.year);
    return date.month == day.month && date.day == day.day;
  }

  /// The year of the birthday occurrence this wish is *for*.
  ///
  /// The occurrence nearest to [from], with a tie going to the past. A
  /// December birthday wished on 5 January attaches to last December; wished
  /// on 20 December it attaches to this December. Belated and early wishes
  /// both land on the occasion the user meant, and nobody is asked a question
  /// they would not understand.
  ///
  /// Ties resolve backwards because a wish is far more often belated than six
  /// months early. [inYear]'s Feb 29 rule applies unchanged, so this agrees
  /// with the reminder fan-out.
  int occasionYear(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final next = nextOccurrence(from);

    final thisYear = inYear(today.year);
    final previous =
        thisYear.isAfter(today) ? inYear(today.year - 1) : thisYear;

    final daysToNext = next.difference(today).inDays;
    final daysSincePrevious = today.difference(previous).inDays;

    return daysSincePrevious <= daysToNext ? previous.year : next.year;
  }

  TimelineGroup groupFrom(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final days = nextOccurrence(from).difference(today).inDays;
    if (days == 0) return TimelineGroup.today;
    if (days <= 7) return TimelineGroup.thisWeek;
    if (days <= 31) return TimelineGroup.thisMonth;
    return TimelineGroup.later;
  }

  @override
  bool operator ==(Object other) =>
      other is Birthday &&
      other.month == month &&
      other.day == day &&
      other.year == year;

  @override
  int get hashCode => Object.hash(month, day, year);
}
