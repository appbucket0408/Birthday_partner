import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import 'signin_cubit.dart';
import 'signin_state.dart';

/// Staff sign-in. Email and password rather than the app's phone OTP: OTP
/// needs a live SMS provider, which this project does not have, and the
/// console must not inherit that dead end.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.opsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: BlocBuilder<SignInCubit, SignInState>(
            builder: (context, state) {
              final busy = state is SignInBusy;
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('ops_email'),
                      controller: _email,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(labelText: AppStrings.opsEmail),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('ops_password'),
                      controller: _password,
                      enabled: !busy,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: AppStrings.opsPassword,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      key: const Key('ops_signin_button'),
                      onPressed: busy
                          ? null
                          : () => context.read<SignInCubit>().submit(
                                email: _email.text.trim(),
                                password: _password.text,
                              ),
                      child: const Text(AppStrings.opsSignIn),
                    ),
                    if (state is SignInRefused) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        state.message,
                        key: const Key('ops_signin_message'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (state is SignInError) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        state.message,
                        key: const Key('ops_signin_message'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
