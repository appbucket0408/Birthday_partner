import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/analytics.dart';
import '../../core/app_links.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../models/profile.dart';
import 'wall_prompt_cubit.dart';

/// The share-your-wall card under the Dashboard header; needs a [WallPromptCubit].
class WallPromptCard extends StatelessWidget {
  const WallPromptCard({super.key, required this.profile, required this.share});

  final Profile profile;
  final Future<void> Function(String text) share;

  String _shareText(int days) {
    if (days == 0) {
      return AppStrings.wallShareTodayTemplate
          .replaceFirst('%1', profile.handle)
          .replaceFirst('%2', AppLinks.download);
    }
    return AppStrings.wallShareTemplate
        .replaceFirst('%1', DateLabels.birthday(profile.birthday!))
        .replaceFirst('%2', profile.handle)
        .replaceFirst('%3', AppLinks.download);
  }

  static String _title(int days) => switch (days) {
        0 => AppStrings.wallPromptToday,
        1 => AppStrings.wallPromptTomorrow,
        _ => AppStrings.wallPromptInDaysTemplate.replaceFirst('%s', '$days'),
      };

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WallPromptCubit, int?>(
      builder: (context, days) {
        if (days == null || profile.birthday == null) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Card(
          key: const Key('wall_prompt_card'),
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          elevation: 0,
          color: scheme.tertiaryContainer.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title(days),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('wall_prompt_close'),
                      tooltip: AppStrings.wallPromptClose,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () =>
                          context.read<WallPromptCubit>().dismiss(),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text(
                    AppStrings.wallPromptBody,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: const Key('wall_prompt_share'),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text(AppStrings.wallPromptShare),
                  onPressed: () {
                    Analytics.log(AppEvent.wallShared, {
                      AppParam.daysToBirthday: days,
                    }).ignore();
                    share(_shareText(days));
                    context.read<WallPromptCubit>().dismiss();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
