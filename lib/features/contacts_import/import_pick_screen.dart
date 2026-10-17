import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
import '../../repositories/contacts_repository.dart';
import 'import_cubit.dart';
import 'import_state.dart';
import 'import_summary_screen.dart';

class ImportPickScreen extends StatelessWidget {
  const ImportPickScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.importPickTitle)),
      body: BlocConsumer<ImportCubit, ImportState>(
        listenWhen: (prev, next) => prev is! ImportDone && next is ImportDone,
        listener: (context, state) {
          // Only the route on top pushes the summary (same guard as
          // PhoneScreen / OtpScreen, Task 7), so a commit() retried from the
          // summary screen does not push a second one from here.
          final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
          if (state is ImportDone && isCurrent) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: context.read<ImportCubit>(),
                  child: const ImportSummaryScreen(),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is ImportCommitting) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.md),
                  Text('${state.done}/${state.total}'),
                ],
              ),
            );
          }
          if (state is ImportFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(AppStrings.somethingWentWrong),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<ImportCubit>().commit(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            );
          }
          if (state is! ImportPicking) {
            return const Center(child: CircularProgressIndicator());
          }

          final picking = state;
          // Split by whether the number already has an account. Only
          // members have a birthday (only a person sets their own), so the
          // two halves get different promises -- said here, at the moment
          // of choosing, rather than discovered later on an empty Calendar.
          final onAppPhones = {for (final r in picking.resolved) r.phone};
          int byName(DeviceContact a, DeviceContact b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase());
          final onApp = [
            for (final c in picking.contacts)
              if (onAppPhones.contains(c.phoneE164)) c,
          ]..sort(byName);
          final notOnApp = [
            for (final c in picking.contacts)
              if (!onAppPhones.contains(c.phoneE164)) c,
          ]..sort(byName);

          Widget tile(DeviceContact contact) => CheckboxListTile(
                key: Key('contact_${contact.phoneE164}'),
                value: picking.selected.contains(contact.phoneE164),
                onChanged: (_) =>
                    context.read<ImportCubit>().toggle(contact.phoneE164),
                title: Text(contact.name),
                subtitle: Text(contact.phoneE164),
              );

          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    if (onApp.isNotEmpty) ...[
                      const _SectionHeader(
                        key: Key('import_section_on_app'),
                        title: AppStrings.importOnApp,
                        hint: AppStrings.importOnAppHint,
                      ),
                      for (final c in onApp) tile(c),
                    ],
                    if (notOnApp.isNotEmpty) ...[
                      const _SectionHeader(
                        key: Key('import_section_not_on_app'),
                        title: AppStrings.importNotOnApp,
                        hint: AppStrings.importNotOnAppHint,
                      ),
                      for (final c in notOnApp) tile(c),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FilledButton(
                  key: const Key('add_selected'),
                  onPressed: picking.selected.isEmpty
                      ? null
                      : () => context.read<ImportCubit>().commit(),
                  child: const Text(AppStrings.importAddSelected),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionHeader(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
