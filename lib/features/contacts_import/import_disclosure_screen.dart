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

/// Play's prominent-disclosure screen. No permission API is touched until
/// Continue is pressed -- ImportCubit is built here but [ImportCubit.start]
/// is only called from the button handler below, never from build().
class ImportDisclosureScreen extends StatelessWidget {
  const ImportDisclosureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ImportCubit(ContactsRepositoryImpl(ApiClient.instance)),
      child: const _ImportDisclosureView(),
    );
  }
}

class _ImportDisclosureView extends StatelessWidget {
  const _ImportDisclosureView();

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

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    AppStrings.importDisclosureTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppStrings.importDisclosureBody),
                  if (state is ImportPermissionDenied) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      AppStrings.importPermissionDenied,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  // I1: start() previously had no error handling at all, so
                  // a failure of requestPermission/readDeviceContacts/
                  // resolve left the cubit stuck in ImportLoadingContacts --
                  // which this screen rendered as a permanently-disabled
                  // spinner behind Continue, with no error and no retry.
                  // ImportFailed now carries a human-readable message and
                  // the button below is what lets the user try again.
                  if (state is ImportFailed) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      state.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const Key('import_continue'),
                    onPressed: requesting
                        ? null
                        : () => context.read<ImportCubit>().start(),
                    child: requesting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.importDisclosureContinue),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    key: const Key('import_skip'),
                    // I2: '/import' is entered via context.go, which
                    // *replaces* the location -- this disclosure screen is
                    // the Navigator's only entry, so Navigator.pop() here
                    // had nothing left to pop back to. There is no AppBar
                    // or back button on this screen, so this and the
                    // summary screen's Done button are the only two ways
                    // out of the whole import flow.
                    onPressed: () => context.go('/timeline'),
                    child: const Text(AppStrings.importDisclosureSkip),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
