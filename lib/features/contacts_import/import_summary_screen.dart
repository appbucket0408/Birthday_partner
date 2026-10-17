import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/import_outcome.dart';
import 'import_cubit.dart';
import 'import_state.dart';


class ImportSummaryScreen extends StatelessWidget {
  const ImportSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImportCubit, ImportState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: state is ImportDone
            ? _Summary(summary: state.summary)
            : const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: FilledButton(
              key: const Key('summary_done'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              // I2: '/import' replaced the location, so this screen's
              // Navigator only ever contains the disclosure screen (pushed)
              // and this one -- popUntil((r) => r.isFirst) landed back on the
              // disclosure screen, not the timeline, with no sign the import
              // actually worked. go('/timeline') is the only way back to a
              // screen that shows the result.
              onPressed: () => context.go('/timeline'),
              child: const Text(AppStrings.importDone),
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final added = summary.added;
    final invalid = [
      for (final r in summary.results)
        if (r.status == ImportStatus.invalidPhone ||
            r.status == ImportStatus.invalidName)
          r,
    ];
    final hasSelf =
        summary.results.any((r) => r.status == ImportStatus.self);

    final (title, body) = switch (added) {
      0 when summary.failed > 0 => (AppStrings.importAddedFailed, null),
      0 when summary.duplicates > 0 =>
        (AppStrings.importAddedNone, AppStrings.importAddedNoneBody),
      0 => (AppStrings.importAddedNone, null),
      1 => (AppStrings.importAddedOne, AppStrings.importAddedBody),
      _ => (
          AppStrings.importAddedManyTemplate.replaceFirst('%s', '$added'),
          AppStrings.importAddedBody,
        ),
    };
    final details = [
      if (summary.duplicates > 0 && added > 0)
        AppStrings.importDuplicatesTemplate
            .replaceFirst('%s', '${summary.duplicates}'),
      if (summary.skipped > 0)
        AppStrings.importSkippedTemplate
            .replaceFirst('%s', '${summary.skipped}'),
      if (hasSelf) AppStrings.importSelfSkipped,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          CircleAvatar(
            radius: 44,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              added > 0 ? '🎉' : '👍',
              style: const TextStyle(fontSize: 40),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            key: const Key('summary_title'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (body != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final d in details)
                  Chip(
                    label: Text(d),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (summary.failed > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            _Problem(
              key: const Key('summary_failed'),
              children: [
                Text(
                  AppStrings.importFailedTemplate
                      .replaceFirst('%s', '${summary.failed}'),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    key: const Key('summary_retry'),
                    onPressed: () => context.read<ImportCubit>().commit(),
                    child: const Text(AppStrings.retry),
                  ),
                ),
              ],
            ),
          ],
          if (invalid.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _Problem(
              key: const Key('summary_invalid'),
              children: [
                Text(
                  AppStrings.importInvalidTitle,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final o in invalid)
                  Text(
                    _readable(o.phone),
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
  static String _readable(String e164) {
    try {
      final p = PhoneNumber.parse(e164);
      return '+${p.countryCode} ${p.formatNsn()}';
    } catch (_) {
      return e164;
    }
  }
}

class _Problem extends StatelessWidget {
  const _Problem({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
