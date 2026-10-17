import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../models/birthday.dart';
import '../../repositories/auth_repository.dart';
import '../../router/session_cubit.dart';
import 'code_field.dart';
import 'phone_link_cubit.dart';
import 'profile_setup_cubit.dart';
import 'profile_setup_state.dart';

/// Sign-up: where a new account lands after its first code. Someone who
/// signed in by email has no verified phone yet, so for them this screen
/// also verifies one (see [PhoneLinkCubit]) before the account can finish.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (c) => ProfileSetupCubit(c.read<AuthRepository>()),
        ),
        BlocProvider(create: (c) => PhoneLinkCubit(c.read<AuthRepository>())),
      ],
      child: _ProfileSetupView(
        // Read once: verifying the phone on this screen flips it to true, and
        // the section must stay on screen (showing "verified") when it does.
        needsPhone: !context.read<AuthRepository>().hasVerifiedPhone,
      ),
    );
  }
}

class _ProfileSetupView extends StatefulWidget {
  const _ProfileSetupView({required this.needsPhone});

  final bool needsPhone;

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
  String? _phoneError;

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

  String? get _birthdayLabel {
    final d = _birthdayDate;
    if (d == null) return null;
    final label = DateLabels.birthday(Birthday(month: d.month, day: d.day));
    return _omitYear ? label : '$label ${d.year}';
  }

  void _submit(BuildContext context) {
    final name = _nameController.text.trim();
    // '@' is shown as a prefix, but people type it anyway.
    final handle = _handleController.text.trim().replaceFirst(RegExp('^@'), '');
    final city = _cityController.text.trim();
    final date = _birthdayDate;
    final phoneOk = !widget.needsPhone ||
        context.read<PhoneLinkCubit>().state is PhoneLinkDone;

    setState(() {
      _nameError = name.isEmpty ? AppStrings.setupNameRequired : null;
      _handleError = handle.isEmpty ? AppStrings.setupHandleRequired : null;
      _birthdayError = date == null ? AppStrings.setupBirthdayRequired : null;
      _phoneError = phoneOk ? null : AppStrings.linkPhoneRequired;
    });

    if (_nameError != null ||
        _handleError != null ||
        _birthdayError != null ||
        _phoneError != null) {
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

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.md),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        final handleTakenMessage =
            state is ProfileSetupError && state.handleTaken
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
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppStrings.setupTitle,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AppStrings.setupSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // The avatar follows the name as it is typed.
                  Center(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _nameController,
                      builder: (_, value, __) =>
                          InitialAvatar(name: value.text, radius: 40),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('setup_name'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: InputDecoration(
                      labelText: AppStrings.setupName,
                      border: _border,
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('setup_handle'),
                    controller: _handleController,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: AppStrings.setupHandle,
                      prefixText: '@',
                      border: _border,
                      errorText: _handleError ?? handleTakenMessage,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  InkWell(
                    key: const Key('setup_birthday'),
                    onTap: _pickBirthday,
                    borderRadius: BorderRadius.circular(AppSpacing.md),
                    child: InputDecorator(
                      isEmpty: _birthdayDate == null,
                      decoration: InputDecoration(
                        labelText: AppStrings.setupBirthday,
                        hintText: AppStrings.setupBirthdayPick,
                        border: _border,
                        errorText: _birthdayError,
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                      ),
                      child: _birthdayLabel == null
                          ? null
                          : Text(_birthdayLabel!),
                    ),
                  ),
                  CheckboxListTile(
                    key: const Key('setup_no_year'),
                    value: _omitYear,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(AppStrings.setupNoYear),
                    onChanged: (value) {
                      setState(() => _omitYear = value ?? false);
                    },
                  ),
                  TextField(
                    key: const Key('setup_city'),
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.addressCity],
                    decoration: InputDecoration(
                      labelText: AppStrings.setupCity,
                      border: _border,
                    ),
                  ),
                  if (widget.needsPhone) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _PhoneLinkSection(
                      requiredError: _phoneError,
                      onDone: () => setState(() => _phoneError = null),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (generalError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        generalError,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    key: const Key('setup_submit'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: saving ? null : () => _submit(context),
                    child: saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.setupSubmit),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Without this, someone who typed the wrong email (or hit
                  // a number that already has an account) has no way back
                  // to the sign-in screen.
                  TextButton(
                    key: const Key('setup_sign_out'),
                    onPressed: saving
                        ? null
                        : () => context.read<SessionCubit>().signOut(),
                    child: const Text(AppStrings.setupSignOut),
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

/// Number field → code boxes → "verified", driven by [PhoneLinkCubit].
class _PhoneLinkSection extends StatefulWidget {
  const _PhoneLinkSection({required this.requiredError, required this.onDone});

  final String? requiredError;
  final VoidCallback onDone;

  @override
  State<_PhoneLinkSection> createState() => _PhoneLinkSectionState();
}

class _PhoneLinkSectionState extends State<_PhoneLinkSection> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<PhoneLinkCubit, PhoneLinkState>(
      listener: (context, state) {
        if (state is PhoneLinkDone) widget.onDone();
        if (state is PhoneLinkCodeSent && state.error != null) {
          _codeController.clear();
        }
      },
      builder: (context, state) {
        final cubit = context.read<PhoneLinkCubit>();
        return Card(
          key: const Key('setup_phone_section'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(AppStrings.linkPhoneTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.linkPhoneBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ...switch (state) {
                  PhoneLinkDone(:final phoneE164) => [
                      Row(
                        key: const Key('setup_phone_verified'),
                        children: [
                          Icon(Icons.verified, color: theme.colorScheme.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '${AppStrings.linkPhoneVerified} · $phoneE164',
                            ),
                          ),
                        ],
                      ),
                    ],
                  PhoneLinkCodeSent() || PhoneLinkVerifying() => [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${AppStrings.otpSubtitle} ${_sentTo(state)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: state is PhoneLinkVerifying
                                ? null
                                : cubit.editNumber,
                            child: const Text(AppStrings.otpChange),
                          ),
                        ],
                      ),
                      CodeField(
                        controller: _codeController,
                        fieldKey: const Key('setup_phone_code'),
                        enabled: state is! PhoneLinkVerifying,
                        errorText:
                            state is PhoneLinkCodeSent ? state.error : null,
                        onCompleted: cubit.verify,
                      ),
                    ],
                  PhoneLinkIdle() || PhoneLinkSending() => [
                      TextField(
                        key: const Key('setup_phone'),
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: InputDecoration(
                          labelText: AppStrings.phoneHint,
                          prefixText: '+91 ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.md),
                          ),
                          errorText: (state is PhoneLinkIdle
                                  ? state.error
                                  : null) ??
                              widget.requiredError,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        key: const Key('setup_phone_send'),
                        onPressed: state is PhoneLinkSending
                            ? null
                            : () => cubit.send(_phoneController.text),
                        child: state is PhoneLinkSending
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(AppStrings.sendCode),
                      ),
                    ],
                },
              ],
            ),
          ),
        );
      },
    );
  }

  String _sentTo(PhoneLinkState state) => switch (state) {
        PhoneLinkCodeSent(:final phoneE164) => phoneE164,
        PhoneLinkVerifying(:final phoneE164) => phoneE164,
        _ => '',
      };
}
