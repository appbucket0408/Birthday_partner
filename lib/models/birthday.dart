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
    final thisYear = _inYear(today.year);
    return thisYear.isBefore(today) ? _inYear(today.year + 1) : thisYear;
  }

  DateTime _inYear(int year) {
    if (month == 2 && day == 29 && !isLeapYear(year)) {
      return DateTime(year, 2, 28);
    }
    return DateTime(year, month, day);
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
