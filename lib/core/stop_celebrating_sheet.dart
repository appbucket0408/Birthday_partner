import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_strings.dart';
import 'initial_avatar.dart';


Future<bool> confirmStopCelebrating(BuildContext context, String name) async {
  final stop = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InitialAvatar(name: name, radius: 32),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.connectionsStopTitleTemplate.replaceFirst(
                  '%s',
                  name,
                ),
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.connectionsStopBody,
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('connections_stop_confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(sheet).colorScheme.error,
                  foregroundColor: Theme.of(sheet).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(sheet).pop(true),
                child: const Text(AppStrings.timelineStopCelebrating),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(sheet).pop(false),
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return stop ?? false;
}
