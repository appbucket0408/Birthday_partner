import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../models/celebration.dart';
import '../../repositories/graph_repository.dart';
import 'calendar_cubit.dart';
import 'calendar_state.dart';

/// The Calendar tab. [GraphRepository] is read off context (registered in
/// `app.dart`); [now] exists only so a test can fix the clock.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          CalendarCubit(context.read<GraphRepository>(), now: _now)..load(),
      child: const CalendarView(),
    );
  }
}

/// Split out from [CalendarScreen] so a widget test can drive it with a
/// mocked [CalendarCubit], same as `ProfileView`.
class CalendarView extends StatelessWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.calendarTitle)),
      body: BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, state) => switch (state) {
          CalendarLoading() => const Center(child: CircularProgressIndicator()),
          CalendarError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<CalendarCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          CalendarLoaded() => RefreshIndicator(
              onRefresh: () => context.read<CalendarCubit>().load(),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _MonthHeader(month: state.month),
                  const SizedBox(height: AppSpacing.sm),
                  _MonthGrid(state: state),
                  const SizedBox(height: AppSpacing.md),
                  _DayList(
                    day: state.selected,
                    people: state.onSelected,
                  ),
                ],
              ),
            ),
        },
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CalendarCubit>();
    return Row(
      children: [
        IconButton(
          key: const Key('calendar_prev_month'),
          icon: const Icon(Icons.chevron_left),
          tooltip: AppStrings.calendarPreviousMonth,
          onPressed: () => cubit.changeMonth(-1),
        ),
        Expanded(
          child: Text(
            DateLabels.monthYear(month),
            key: const Key('calendar_month_label'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: const Key('calendar_next_month'),
          icon: const Icon(Icons.chevron_right),
          tooltip: AppStrings.calendarNextMonth,
          onPressed: () => cubit.changeMonth(1),
        ),
      ],
    );
  }
}

/// A Monday-first month grid. Days with a birthday carry a dot; the selected
/// day is filled.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.state});

  final CalendarLoaded state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final month = state.month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = month.weekday - 1; // Monday = 1
    final marked = state.birthdayDays;
    final selected = state.selected;

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final d in DateLabels.weekdays)
          Center(
            child: Text(
              d.substring(0, 1),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
        for (var day = 1; day <= daysInMonth; day++)
          _DayCell(
            day: day,
            hasBirthday: marked.contains(day),
            isSelected: selected.year == month.year &&
                selected.month == month.month &&
                selected.day == day,
            onTap: () => context
                .read<CalendarCubit>()
                .select(DateTime(month.year, month.month, day)),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.hasBirthday,
    required this.isSelected,
    required this.onTap,
  });

  final int day;
  final bool hasBirthday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = isSelected ? scheme.onPrimary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? scheme.primary : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: Key('calendar_day_$day'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day', style: TextStyle(color: fg)),
              const SizedBox(height: 2),
              Container(
                key: hasBirthday ? Key('calendar_dot_$day') : null,
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasBirthday
                      ? (isSelected ? scheme.onPrimary : scheme.primary)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.day, required this.people});

  final DateTime day;
  final List<Celebration> people;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                DateLabels.dayHeading(day),
                key: const Key('calendar_selected_heading'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Text(AppStrings.calendarNoBirthdays),
              )
            else
              for (final c in people)
                ListTile(
                  key: Key('calendar_person_${c.person.id}'),
                  leading: InitialAvatar(name: c.label),
                  title: Text(c.label),
                  subtitle: Text(_ageLine(c)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/person/${c.person.id}'),
                ),
          ],
        ),
      ),
    );
  }

  String _ageLine(Celebration c) {
    final born = c.person.birthday?.year;
    if (born == null) return AppStrings.calendarYearUnknown;
    return AppStrings.calendarTurnsTemplate.replaceFirst('%s', '${day.year - born}');
  }
}
