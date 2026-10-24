import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import 'force_update_cubit.dart';

/// Shown instead of the whole app while this build is unsupported. No way
/// past it but updating; Back leaves the app rather than revealing it.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    AppStrings.forceUpdateTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.forceUpdateBody,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    key: const Key('force_update_button'),
                    onPressed: () =>
                        context.read<ForceUpdateCubit>().openStore(),
                    child: const Text(AppStrings.forceUpdateAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
