import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
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
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    for (final contact in picking.contacts)
                      CheckboxListTile(
                        key: Key('contact_${contact.phoneE164}'),
                        value: picking.selected.contains(contact.phoneE164),
                        onChanged: (_) => context
                            .read<ImportCubit>()
                            .toggle(contact.phoneE164),
                        title: Text(contact.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(contact.phoneE164),
                            if (picking.resolved
                                .any((r) => r.phone == contact.phoneE164))
                              const Text(AppStrings.importOnApp),
                          ],
                        ),
                      ),
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
