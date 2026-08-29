import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/birthday.dart';
import '../../repositories/auth_repository.dart';
import '../../router/session_cubit.dart';
import 'profile_setup_cubit.dart';
import 'profile_setup_state.dart';

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => ProfileSetupCubit(c.read<AuthRepository>()),
      child: const _ProfileSetupView(),
    );
  }
}

class _ProfileSetupView extends StatefulWidget {
  const _ProfileSetupView();

  @override
  State<_ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<_ProfileSetupView> {
  final _nameController = TextEditingController();
  final _handleController = TextEditingController();
  final _cityController = TextEditingController();

  // Seeded to 1 Jan 2000 rather than DateTime.now(): the picker is for a
  // birthday, and opening on today's date nudges toward picking "today".
  static final _defaultSeed = DateTime(2000, 1, 1);

  DateTime? _birthdayDate;
  bool _omitYear = false;
  String? _nameError;
  String? _handleError;
  String? _birthdayError;

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdayDate ?? _defaultSeed,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    // The route can be popped/disposed while the dialog is open -- e.g. an
    // external session invalidation firing the router's redirect. Without
    // this guard the resolved future calls setState on a dead State.
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _birthdayDate = picked;
      _birthdayError = null;
    });
  }

  String get _birthdayLabel {
    final d = _birthdayDate;
    if (d == null) return AppStrings.setupBirthday;
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return _omitYear ? '$month/$day' : '$month/$day/${d.year}';
  }

  void _submit(BuildContext context) {
    final name = _nameController.text.trim();
    final handle = _handleController.text.trim();
    final city = _cityController.text.trim();
    final date = _birthdayDate;

    setState(() {
      _nameError = name.isEmpty ? AppStrings.setupNameRequired : null;
      _handleError = handle.isEmpty ? AppStrings.setupHandleRequired : null;
      _birthdayError = date == null ? AppStrings.setupBirthdayRequired : null;
    });

    if (_nameError != null || _handleError != null || _birthdayError != null) {
      return;
    }

    final birthday = Birthday(
      month: date!.month,
      day: date.day,
      year: _omitYear ? null : date.year,
    );

    context.read<ProfileSetupCubit>().submit(
          handle: handle,
          displayName: name,
          city: city,
          birthday: birthday,
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileSetupCubit, ProfileSetupState>(
      listener: (context, state) {
        if (state is ProfileSetupDone) {
          context.read<SessionCubit>().onProfileCompleted();
        }
      },
      builder: (context, state) {
        final saving = state is ProfileSetupSaving;
        // The handle-taken message is attached to the handle field, not shown
        // as a general failure -- see ProfileSetupError.handleTaken.
        final handleTakenMessage = state is ProfileSetupError && state.handleTaken
            ? state.message
            : null;
        final generalError = state is ProfileSetupError && !state.handleTaken
            ? state.message
            : null;

        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    AppStrings.setupTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('setup_name'),
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: AppStrings.setupName,
                      border: const OutlineInputBorder(),
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('setup_handle'),
                    controller: _handleController,
                    decoration: InputDecoration(
                      labelText: AppStrings.setupHandle,
                      border: const OutlineInputBorder(),
                      errorText: _handleError ?? handleTakenMessage,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('setup_city'),
                    controller: _cityController,
                    decoration: InputDecoration(
                      labelText: AppStrings.setupCity,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    key: const Key('setup_birthday'),
                    onPressed: _pickBirthday,
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                    ),
                    child: Text(_birthdayLabel),
                  ),
                  if (_birthdayError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        _birthdayError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(AppStrings.setupBirthdayHelp),
                  CheckboxListTile(
                    value: _omitYear,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(AppStrings.setupNoYear),
                    onChanged: (value) {
                      setState(() => _omitYear = value ?? false);
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (generalError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        generalError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    key: const Key('setup_submit'),
                    onPressed: saving ? null : () => _submit(context),
                    child: saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.finish),
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
