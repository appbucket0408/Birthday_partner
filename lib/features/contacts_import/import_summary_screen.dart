import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/import_outcome.dart';
import 'import_cubit.dart';
import 'import_state.dart';

/// Reads the final ImportSummary.
///
/// `suppressed` carries no string of its own anywhere in this screen -- it
/// is counted into [ImportSummary.skipped] alongside every other skip
/// reason before this screen ever sees it, so there is nothing here that
/// could distinguish it even if someone tried.
class ImportSummaryScreen extends StatelessWidget {
  const ImportSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.importSummaryTitle)),
      body: BlocBuilder<ImportCubit, ImportState>(
        builder: (context, state) {
          if (state is! ImportDone) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = state.summary;
          // invalid_phone / invalid_name are fixable, so the contact is
          // named (by phone, the only identifier ImportOutcome carries) so
          // the user knows which entry to go correct. `failed` is a server
          // condition the user cannot act on, so it is reported as a bare
          // count with a retry, naming nobody.
          final invalid = summary.results.where(
            (r) =>
                r.status == ImportStatus.invalidPhone ||
                r.status == ImportStatus.invalidName,
          );
          final hasSelf = summary.results.any(
            (r) => r.status == ImportStatus.self,
          );

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.importAddedTemplate.replaceFirst(
                      '%s',
                      '${summary.added}',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.importDuplicatesTemplate.replaceFirst(
                      '%s',
                      '${summary.duplicates}',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // No reason is ever shown here -- suppressed and every
                  // other skip are indistinguishable on this line.
                  Text(
                    AppStrings.importSkippedTemplate.replaceFirst(
                      '%s',
                      '${summary.skipped}',
                    ),
                  ),
                  if (hasSelf) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      AppStrings.importSelfSkipped,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (invalid.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    for (final outcome in invalid)
                      Text(
                        AppStrings.importCouldNotAddTemplate.replaceFirst(
                          '%s',
                          outcome.phone,
                        ),
                      ),
                  ],
                  if (summary.failed > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      AppStrings.importCouldNotAddTemplate.replaceFirst(
                        '%s',
                        '${summary.failed}',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      key: const Key('summary_retry'),
                      onPressed: () => context.read<ImportCubit>().commit(),
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                  const Spacer(),
                  FilledButton(
                    key: const Key('summary_done'),
                    // I2: '/import' replaced the location, so this screen's
                    // Navigator only ever contains the disclosure screen
                    // (pushed) and this one (pushed on top of it) --
                    // popUntil((r) => r.isFirst) landed back on the
                    // disclosure screen, not the timeline, with no sign the
                    // import actually worked. go('/timeline') is the only
                    // way back to a screen that shows the result.
                    onPressed: () => context.go('/timeline'),
                    child: const Text(AppStrings.importDone),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
