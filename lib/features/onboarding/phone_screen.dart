import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/auth_repository.dart';
import 'otp_screen.dart';
import 'phone_cubit.dart';
import 'phone_state.dart';

/// The one entry screen for new and returning users alike: a phone number
/// (or, in builds with [emailSignInEnabled], an email address), then a code.
/// Whether the person already has an account is only decided AFTER the code
/// is verified -- asking first would let anyone probe which numbers and
/// addresses are registered.
class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key, this.allowEmail = emailSignInEnabled});

  /// The launch app is phone-only: every account needs a verified phone
  /// anyway, and hosted email delivery needs custom SMTP. Email sign-in stays
  /// for test builds (--dart-define=EMAIL_SIGN_IN=true), which is how a
  /// hosted project without an SMS provider can still be signed into.
  static const emailSignInEnabled = bool.fromEnvironment('EMAIL_SIGN_IN');

  /// Whether the Phone/Email switch is shown. Tests set it directly.
  final bool allowEmail;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => PhoneCubit(c.read<AuthRepository>()),
      child: _PhoneView(allowEmail: allowEmail),
    );
  }
}

enum _Method { phone, email }

class _PhoneView extends StatefulWidget {
  const _PhoneView({required this.allowEmail});

  final bool allowEmail;

  @override
  State<_PhoneView> createState() => _PhoneViewState();
}

class _PhoneViewState extends State<_PhoneView> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  _Method _method = _Method.phone;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    final cubit = context.read<PhoneCubit>();
    switch (_method) {
      case _Method.phone:
        cubit.submitPhone(_phoneController.text);
      case _Method.email:
        cubit.submitEmail(_emailController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<PhoneCubit, PhoneState>(
      listener: (context, state) {
        // A wrong code re-emits PhoneCodeSent (PhoneVerifying ->
        // PhoneCodeSent with an error). This route stays mounted underneath
        // the pushed OtpScreen and keeps listening, so without the isCurrent
        // guard that second emission pushes a duplicate OtpScreen on top of
        // the first one -- do not remove this check.
        final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (state is PhoneCodeSent && isCurrent) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<PhoneCubit>(),
                child: const OtpScreen(),
              ),
            ),
          );
        }
      },
      listenWhen: (prev, next) =>
          prev is! PhoneCodeSent && next is PhoneCodeSent,
      builder: (context, state) {
        final sending = state is PhoneSending;
        final error = state is PhoneError ? state.message : null;
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  const Center(child: _BrandMark()),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    AppStrings.signInTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.signInSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (widget.allowEmail) ...[
                    SegmentedButton<_Method>(
                      key: const Key('signin_method'),
                      segments: const [
                        ButtonSegment(
                          value: _Method.phone,
                          icon: Icon(Icons.phone_outlined),
                          label: Text(AppStrings.signInPhoneTab),
                        ),
                        ButtonSegment(
                          value: _Method.email,
                          icon: Icon(Icons.mail_outline),
                          label: Text(AppStrings.signInEmailTab),
                        ),
                      ],
                      selected: {_method},
                      showSelectedIcon: false,
                      onSelectionChanged: sending
                          ? null
                          : (s) => setState(() => _method = s.single),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_method == _Method.phone)
                    TextField(
                      key: const Key('phone_field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      onSubmitted: (_) => _submit(context),
                      decoration: InputDecoration(
                        labelText: AppStrings.phoneHint,
                        // The number is parsed as Indian when typed without
                        // a country code (PhoneCubit.submitPhone's default).
                        prefixText: '+91 ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                        ),
                        errorText: error,
                      ),
                    )
                  else
                    TextField(
                      key: const Key('email_field'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      onSubmitted: (_) => _submit(context),
                      decoration: InputDecoration(
                        labelText: AppStrings.emailHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                        ),
                        errorText: error,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const Key('send_code_button'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: sending ? null : () => _submit(context),
                    child: sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.sendCode),
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

/// The app's mark until there is a real logo: a cake on a rounded tile in
/// the theme's own colours.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.cake, size: 38, color: scheme.onPrimary),
    );
  }
}
