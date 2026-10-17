import '../../models/celebration.dart';

sealed class CalendarState {
  const CalendarState();
}

final class CalendarLoading extends CalendarState {
  const CalendarLoading();
}

/// [month] is the first day of the month on screen; [selected] is the day
/// whose birthdays are listed under the grid. They move independently:
/// paging to another month does not move the selection.
final class CalendarLoaded extends CalendarState {
  const CalendarLoaded({
    required this.celebrations,
    required this.month,
    required this.selected,
  });

  final List<Celebration> celebrations;
  final DateTime month;
  final DateTime selected;

  /// Days of [month] with at least one birthday on them, for the dots.
  Set<int> get birthdayDays => {
    for (final c in celebrations)
      if (c.person.birthday?.inYear(month.year) case final date?
          when date.month == month.month)
        date.day,
  };

  /// Everyone whose birthday falls on [selected], by name.
  List<Celebration> get onSelected => [
    for (final c in celebrations)
      if (c.person.birthday?.inYear(selected.year) case final date?
          when date.month == selected.month && date.day == selected.day)
        c,
  ]..sort((a, b) => a.person.displayName.compareTo(b.person.displayName));

  CalendarLoaded copyWith({DateTime? month, DateTime? selected}) =>
      CalendarLoaded(
        celebrations: celebrations,
        month: month ?? this.month,
        selected: selected ?? this.selected,
      );
}

final class CalendarError extends CalendarState {
  const CalendarError(this.message);

  final String message;
}
