import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/countdown_pill.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../models/celebration.dart';
import '../../repositories/graph_repository.dart';
import '../../router/active_tab.dart';
import '../../router/home_shell.dart';
import '../notifications/notification_bell.dart';
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
      child: RefreshWhenShown(
        tab: HomeShell.calendarTab,
        onShown: (c) => c.read<CalendarCubit>().refresh(),
        child: CalendarView(now: _now ?? DateTime.now),
      ),
    );
  }
}

/// Split out from [CalendarScreen] so a widget test can drive it with a
/// mocked [CalendarCubit], same as `ProfileView`.
class CalendarView extends StatelessWidget {
  const CalendarView({super.key, this.now = DateTime.now});

  /// For "today": the ring on its cell and the countdowns.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.calendarTitle),
        actions: const [NotificationBell(), SizedBox(width: AppSpacing.xs)],
      ),
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                children: [
                  _MonthHeader(state: state, now: now()),
                  const SizedBox(height: AppSpacing.md - 4),
                  _MonthCard(state: state, now: now()),
                  const SizedBox(height: AppSpacing.md),
                  _DayCard(state: state, now: now()),
                ],
              ),
            ),
        },
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Month name and how many birthdays it holds, the arrows, and -- when the
/// grid is on another month -- a way straight back to today.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.state, required this.now});

  final CalendarLoaded state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<CalendarCubit>();
    final total = state.birthdaysPerDay.values.fold(0, (a, b) => a + b);
    final summary = switch (total) {
      0 => AppStrings.calendarNoneThisMonth,
      1 => AppStrings.calendarOneThisMonth,
      _ => AppStrings.calendarManyThisMonthTemplate.replaceFirst('%s', '$total'),
    };
    final onThisMonth =
        state.month.year == now.year && state.month.month == now.month;

    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateLabels.monthYear(state.month),
                  key: const Key('calendar_month_label'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  key: const Key('calendar_month_summary'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (!onThisMonth)
          TextButton(
            key: const Key('calendar_today'),
            onPressed: cubit.goToToday,
            child: const Text(AppStrings.calendarToday),
          ),
        IconButton.outlined(
          key: const Key('calendar_prev_month'),
          style: IconButton.styleFrom(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          icon: const Icon(Icons.chevron_left),
          tooltip: AppStrings.calendarPreviousMonth,
          onPressed: () => cubit.changeMonth(-1),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.outlined(
          key: const Key('calendar_next_month'),
          style: IconButton.styleFrom(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          icon: const Icon(Icons.chevron_right),
          tooltip: AppStrings.calendarNextMonth,
          onPressed: () => cubit.changeMonth(1),
        ),
      ],
    );
  }
}

/// The month grid on a card. Swipe sideways to change month.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.state, required this.now});

  final CalendarLoaded state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<CalendarCubit>();
    final month = state.month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = month.weekday - 1; // Monday = 1
    final counts = state.birthdaysPerDay;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 200) return;
        HapticFeedback.selectionClick();
        cubit.changeMonth(v < 0 ? 1 : -1);
      },
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm + 2,
            AppSpacing.sm,
            AppSpacing.sm + 2,
            AppSpacing.sm + 2,
          ),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final d in DateLabels.weekdays)
                Center(
                  child: Text(
                    d.substring(0, 1),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
              for (var day = 1; day <= daysInMonth; day++)
                _DayCell(
                  day: day,
                  birthdays: counts[day] ?? 0,
                  isToday: _sameDay(DateTime(month.year, month.month, day), now),
                  isSelected:
                      _sameDay(DateTime(month.year, month.month, day), state.selected),
                  onTap: () =>
                      cubit.select(DateTime(month.year, month.month, day)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A day: tinted when someone has a birthday (with a count when it is more
/// than one), ringed when it is today, filled when selected.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.birthdays,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final int day;
  final int birthdays;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasBirthday = birthdays > 0;
    final (background, foreground) = isSelected
        ? (scheme.primary, scheme.onPrimary)
        : hasBirthday
            ? (scheme.primaryContainer, scheme.onPrimaryContainer)
            : (Colors.transparent, scheme.onSurface);

    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        key: Key('calendar_day_$day'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                key: hasBirthday ? Key('calendar_dot_$day') : null,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: isToday && !isSelected
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: hasBirthday || isToday || isSelected
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (birthdays > 1)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  key: Key('calendar_count_$day'),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: scheme.tertiary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$birthdays',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The selected day: who has a birthday on it, or -- when nobody does --
/// when the next one is, one tap away.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.state, required this.now});

  final CalendarLoaded state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = state.selected;
    final people = state.onSelected;
    final next = state.nextAfterSelected;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateLabels.dayHeading(day),
                    key: const Key('calendar_selected_heading'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_sameDay(day, now))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm + 2,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Text(
                      AppStrings.calendarToday,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (people.isNotEmpty)
            for (final (i, c) in people.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 72,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              _PersonRow(celebration: c, now: now),
            ]
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.celebrations.any((c) => c.person.birthday != null)
                        ? AppStrings.calendarNoBirthdays
                        : AppStrings.calendarNobodyYet,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (next != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      key: const Key('calendar_next_birthday'),
                      onPressed: () =>
                          context.read<CalendarCubit>().show(next.date),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(
                        AppStrings.calendarNextTemplate
                            .replaceFirst(
                              '%1',
                              next.celebration.person.displayName,
                            )
                            .replaceFirst(
                              '%2',
                              DateLabels.birthday(
                                next.celebration.person.birthday!,
                              ),
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.celebration,
    required this.now,
  });

  final Celebration celebration;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = celebration.person;
    return ListTile(
      key: Key('calendar_person_${person.id}'),
      leading: InitialAvatar(name: person.displayName, radius: 22),
      title: Text(
        person.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      trailing: person.birthday == null
          ? null
          : CountdownPill(birthday: person.birthday!, now: now, compact: true),
      onTap: () => context.go('/person/${person.id}'),
    );
  }
}
