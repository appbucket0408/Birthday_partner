import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/initial_avatar.dart';
import '../../router/session_cubit.dart';
import 'code_field.dart';
import 'phone_cubit.dart';
import 'phone_state.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  /// How long a returning user sees "Welcome back" before the session moves
  /// the router on. Long enough to read, short enough not to feel like a
  /// loading screen.
  static const welcomeDelay = Duration(milliseconds: 1200);

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();

  // [auth.sms] max_frequency is 5s, so anything at or above that is safe;
  // 30s is the interval a user reads as "it is really coming".
  static const _cooldownSeconds = 30;
  int _remaining = _cooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remaining = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _cooldownLabel {
    final s = _remaining.toString().padLeft(2, '0');
    return AppStrings.resendCooldownTemplate.replaceFirst('%s', '0:$s');
  }

  Future<void> _onVerified(PhoneVerified state) async {
    final session = context.read<SessionCubit>();
    if (state.welcomeName != null) {
      await Future<void>.delayed(OtpScreen.welcomeDelay);
    }
    await session.onSignedIn();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<PhoneCubit, PhoneState>(
      listener: (context, state) {
        if (state is PhoneVerified) _onVerified(state);
        // A rejected code clears the boxes, so the next attempt is typed
        // fresh instead of backspaced over.
        if (state is PhoneCodeSent && state.error != null) _controller.clear();
      },
      builder: (context, state) {
        if (state case PhoneVerified(:final welcomeName?)) {
          return _WelcomeBack(name: welcomeName);
        }
        final destination = switch (state) {
          PhoneCodeSent(:final destination) => destination,
          PhoneVerifying(:final destination) => destination,
          _ => '',
        };
        final error = state is PhoneCodeSent ? state.error : null;
        final verifying = state is PhoneVerifying || state is PhoneVerified;

        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.otpTitle,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.otpSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          destination,
                          key: const Key('otp_destination'),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      TextButton(
                        key: const Key('otp_change_button'),
                        onPressed: verifying
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        child: const Text(AppStrings.otpChange),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CodeField(
                    controller: _controller,
                    fieldKey: const Key('otp_field'),
                    errorText: error,
                    enabled: !verifying,
                    onCompleted: (v) =>
                        context.read<PhoneCubit>().submitCode(v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: TextButton(
                      key: const Key('resend_button'),
                      onPressed: _remaining > 0 || verifying
                          ? null
                          : () {
                              context.read<PhoneCubit>().resend();
                              _startCooldown();
                            },
                      child: Text(
                        _remaining > 0 ? _cooldownLabel : AppStrings.resendCode,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => FilledButton(
                      key: const Key('otp_verify_button'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: verifying ||
                              value.text.length != CodeField.length
                          ? null
                          : () => context
                              .read<PhoneCubit>()
                              .submitCode(value.text),
                      child: verifying
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(AppStrings.otpVerify),
                    ),
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

class _WelcomeBack extends StatelessWidget {
  const _WelcomeBack({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('welcome_back'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InitialAvatar(name: name, radius: 36),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.welcomeBackTemplate.replaceFirst('%s', name),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.welcomeBackBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
