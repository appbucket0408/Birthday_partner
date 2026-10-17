import 'package:flutter/material.dart';

import '../models/birthday.dart';
import 'app_spacing.dart';
import 'app_strings.dart';

class CountdownPill extends StatelessWidget {
  const CountdownPill({
    super.key,
    required this.birthday,
    required this.now,
    this.compact = false,
  });

  final Birthday birthday;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime(now.year, now.month, now.day);
    final days = birthday.nextOccurrence(now).difference(today).inDays;
    final (label, background, foreground) = switch (days) {
      0 => (AppStrings.personToday, scheme.primary, scheme.onPrimary),
      1 => (
        AppStrings.personTomorrow,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ => (
        AppStrings.personInDaysTemplate.replaceFirst('%s', '$days'),
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm + 2 : AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
      ),
      child: Text(
        label,
        style:
            (compact ? theme.textTheme.labelMedium : theme.textTheme.labelLarge)
                ?.copyWith(
                  color: foreground,
                  fontWeight: days == 0 ? FontWeight.w800 : FontWeight.w600,
                ),
      ),
    );
  }
}
