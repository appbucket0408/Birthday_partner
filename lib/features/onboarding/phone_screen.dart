import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/auth_repository.dart';
import 'otp_screen.dart';
import 'phone_cubit.dart';
import 'phone_state.dart';

class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => PhoneCubit(c.read<AuthRepository>()),
      child: const _PhoneView(),
    );
  }
}

class _PhoneView extends StatefulWidget {
  const _PhoneView();

  @override
  State<_PhoneView> createState() => _PhoneViewState();
}

class _PhoneViewState extends State<_PhoneView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PhoneCubit, PhoneState>(
      listener: (context, state) {
        if (state is PhoneCodeSent) {
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
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    AppStrings.phoneTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppStrings.phoneSubtitle),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('phone_field'),
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: AppStrings.phoneHint,
                      border: const OutlineInputBorder(),
                      errorText: state is PhoneError ? state.message : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const Key('send_code_button'),
                    onPressed: state is PhoneSending
                        ? null
                        : () => context.read<PhoneCubit>().submitPhone(
                            _controller.text,
                          ),
                    child: state is PhoneSending
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
