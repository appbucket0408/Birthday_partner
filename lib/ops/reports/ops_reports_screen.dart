import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../models/ops_report.dart';
import '../../repositories/ops_reports_repository.dart';
import '../signin/signin_cubit.dart';
import 'ops_reports_cubit.dart';
import 'ops_reports_state.dart';

class OpsReportsScreen extends StatelessWidget {
  const OpsReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          OpsReportsCubit(context.read<OpsReportsRepository>())..load(),
      child: const OpsReportsView(),
    );
  }
}

class OpsReportsView extends StatelessWidget {
  const OpsReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.opsReportsTab),
        actions: [
          TextButton(
            key: const Key('ops_reports_go_catalog'),
            onPressed: () => context.go('/catalog'),
            child: const Text(AppStrings.opsCatalogTab),
          ),
          TextButton(
            key: const Key('ops_reports_sign_out'),
            onPressed: () => context.read<SignInCubit>().signOut(),
            child: const Text(AppStrings.opsSignOut),
          ),
        ],
      ),
      body: BlocConsumer<OpsReportsCubit, OpsReportsState>(
        listenWhen: (_, s) =>
            (s is OpsReportsError && s.sessionExpired) ||
            (s is OpsReportsLoaded && s.message != null),
        listener: (context, state) {
          if (state is OpsReportsError) {
            context.read<SignInCubit>().sessionExpired();
            context.go('/signin');
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((state as OpsReportsLoaded).message!)),
          );
        },
        builder: (context, state) => switch (state) {
          OpsReportsLoading() =>
            const Center(child: CircularProgressIndicator()),
          OpsReportsError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<OpsReportsCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          OpsReportsLoaded(reports: []) =>
            const Center(child: Text(AppStrings.opsNoReports)),
          OpsReportsLoaded() => RefreshIndicator(
              onRefresh: () => context.read<OpsReportsCubit>().load(),
              child: ListView(
                key: const Key('ops_reports_list'),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  for (final r in state.reports)
                    _ReportCard(report: r, busy: state.busy.contains(r.id)),
                ],
              ),
            ),
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.busy});

  final OpsReport report;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<OpsReportsCubit>();
    final photo = report.wishPhotoPath;
    return Card(
      key: Key('ops_report_${report.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(report.reason.label)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  report.isAboutPost
                      ? AppStrings.opsReportPost
                      : AppStrings.opsReportPerson,
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                Text(
                  DateLabels.posted(report.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(report.reportedName, style: theme.textTheme.titleMedium),
            Text(
              '${AppStrings.opsReportedBy} ${report.reporterName}',
              style: theme.textTheme.bodySmall,
            ),
            if (report.reportCount > 1)
              Text(
                AppStrings.opsReportCountTemplate
                    .replaceFirst('%s', '${report.reportCount}'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            if (report.note case final note?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('"$note"', style: theme.textTheme.bodyMedium),
            ],
            if (report.isAboutPost) ...[
              const SizedBox(height: AppSpacing.sm),
              if (!report.wishStillExists)
                Text(
                  AppStrings.opsPostAlreadyGone,
                  style: theme.textTheme.bodySmall,
                ),
              if (photo != null) _ReportPhoto(path: photo),
              if (report.wishBody case final body?)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: SelectableText(body),
                ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('ops_dismiss_${report.id}'),
                  onPressed: busy ? null : () => cubit.dismiss(report.id),
                  child: const Text(AppStrings.opsDismiss),
                ),
                if (report.isAboutPost && report.wishStillExists) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    key: Key('ops_remove_${report.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: busy ? null : () => cubit.removePost(report.id),
                    child: const Text(AppStrings.opsRemovePost),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportPhoto extends StatelessWidget {
  const _ReportPhoto({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: context.read<OpsReportsRepository>().photoUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Image.network(url, fit: BoxFit.contain),
        );
      },
    );
  }
}
