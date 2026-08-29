import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../router/session_cubit.dart';
import 'phone_cubit.dart';
import 'phone_state.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PhoneCubit, PhoneState>(
      listener: (context, state) {
        if (state is PhoneVerified) {
          context.read<SessionCubit>().onSignedIn();
        }
      },
      builder: (context, state) {
        final phone = switch (state) {
          PhoneCodeSent(:final phoneE164) => phoneE164,
          PhoneVerifying(:final phoneE164) => phoneE164,
          _ => '',
        };
        final error = state is PhoneCodeSent ? state.error : null;

        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.otpTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppStrings.otpSubtitleTemplate.replaceFirst('%s', phone),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('otp_field'),
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: AppStrings.otpHint,
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                    onChanged: (v) {
                      if (v.length == 6) {
                        context.read<PhoneCubit>().submitCode(v);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (state is PhoneVerifying)
                    const Center(child: CircularProgressIndicator())
                  else
                    TextButton(
                      key: const Key('resend_button'),
                      onPressed: _remaining > 0
                          ? null
                          : () {
                              context.read<PhoneCubit>().resend();
                              _startCooldown();
                            },
                      child: Text(
                        _remaining > 0
                            ? AppStrings.resendCooldownTemplate.replaceFirst(
                                '%s',
                                '$_remaining',
                              )
                            : AppStrings.resendCode,
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
