import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/contacts_repository_impl.dart';
import 'import_cubit.dart';
import 'import_pick_screen.dart';
import 'import_state.dart';


class ImportDisclosureScreen extends StatelessWidget {
  const ImportDisclosureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ImportCubit(ContactsRepositoryImpl(ApiClient.instance)),
      child: const ImportDisclosureView(),
    );
  }
}

class ImportDisclosureView extends StatelessWidget {
  const ImportDisclosureView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImportCubit, ImportState>(
      listenWhen: (prev, next) =>
          prev is! ImportPicking && next is ImportPicking,
      listener: (context, state) {
        final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (state is ImportPicking && isCurrent) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<ImportCubit>(),
                child: const ImportPickScreen(),
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        final requesting = state is ImportRequestingPermission ||
            state is ImportLoadingContacts;

        final theme = Theme.of(context);
        final error = switch (state) {
          ImportPermissionDenied() => AppStrings.importPermissionDenied,
          ImportFailed(:final message) => message,
          _ => null,
        };

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const Key('import_close'),
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => context.go('/timeline'),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          child: const Icon(Icons.contacts_outlined, size: 40),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          AppStrings.importDisclosureTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          AppStrings.importDisclosureBody,
                          key: const Key('import_disclosure_body'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const _TrustPoint(
                          icon: Icons.lock_outline,
                          title: AppStrings.importTrustStaysTitle,
                          body: AppStrings.importTrustStaysBody,
                        ),
                        const _TrustPoint(
                          icon: Icons.visibility_off_outlined,
                          title: AppStrings.importTrustSharedTitle,
                          body: AppStrings.importTrustSharedBody,
                        ),
                        const _TrustPoint(
                          icon: Icons.check_circle_outline,
                          title: AppStrings.importTrustChooseTitle,
                          body: AppStrings.importTrustChooseBody,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _ErrorBox(message: error),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
                // Pinned to the bottom, in thumb reach -- the same place as
                // the sign-in screen's main button.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: const Key('import_continue'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: requesting
                            ? null
                            : () => context.read<ImportCubit>().start(),
                        child: requesting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(AppStrings.importDisclosureContinue),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        key: const Key('import_skip'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => context.go('/timeline'),
                        child: const Text(AppStrings.importDisclosureSkip),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One privacy promise: an icon in a tinted circle, a bold line, and one
/// line of detail -- scannable, where the old paragraph was not.
class _TrustPoint extends StatelessWidget {
  const _TrustPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.secondaryContainer,
            foregroundColor: theme.colorScheme.onSecondaryContainer,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('import_error'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
