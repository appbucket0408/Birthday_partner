import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/birthday.dart';
import 'import_cubit.dart';
import 'import_state.dart';
import 'import_summary_screen.dart';

/// Shown only for selected contacts with no birthday anywhere. Skippable:
/// leaving a row untouched and pressing Save keeps that contact's birthday
/// null, which addCelebrations already handles.
class ImportFillBirthdaysScreen extends StatefulWidget {
  const ImportFillBirthdaysScreen({super.key});

  @override
  State<ImportFillBirthdaysScreen> createState() =>
      _ImportFillBirthdaysScreenState();
}

class _ImportFillBirthdaysScreenState
    extends State<ImportFillBirthdaysScreen> {
  // Seeded to 1 Jan 2000, matching ProfileSetupScreen: opening the picker on
  // today's date nudges toward picking "today".
  static final _defaultSeed = DateTime(2000, 1, 1);

  final _dates = <String, DateTime>{};
  final _omitYear = <String, bool>{};

  Future<void> _pickBirthday(String phoneE164) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dates[phoneE164] ?? _defaultSeed,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() => _dates[phoneE164] = picked);
  }

  String _labelFor(String phoneE164) {
    final d = _dates[phoneE164];
    if (d == null) return AppStrings.setupBirthday;
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final omit = _omitYear[phoneE164] ?? false;
    return omit ? '$month/$day' : '$month/$day/${d.year}';
  }

  void _continue(BuildContext context) {
    final cubit = context.read<ImportCubit>();
    for (final entry in _dates.entries) {
      final omit = _omitYear[entry.key] ?? false;
      cubit.setBirthday(
        entry.key,
        Birthday(
          month: entry.value.month,
          day: entry.value.day,
          year: omit ? null : entry.value.year,
        ),
      );
    }
    cubit.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.importFillTitle)),
      body: BlocConsumer<ImportCubit, ImportState>(
        listenWhen: (prev, next) => prev is! ImportDone && next is ImportDone,
        listener: (context, state) {
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

          final names = {for (final c in state.contacts) c.phoneE164: c.name};
          final missing = state.missingBirthdays;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(AppStrings.importFillBody),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final phone in missing)
                      Padding(
                        key: Key('birthday_$phone'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              names[phone] ?? phone,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            OutlinedButton(
                              onPressed: () => _pickBirthday(phone),
                              child: Text(_labelFor(phone)),
                            ),
                            CheckboxListTile(
                              value: _omitYear[phone] ?? false,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: const Text(AppStrings.setupNoYear),
                              onChanged: (v) => setState(
                                () => _omitYear[phone] = v ?? false,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FilledButton(
                  key: const Key('fill_continue'),
                  onPressed: () => _continue(context),
                  child: const Text(AppStrings.save),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
