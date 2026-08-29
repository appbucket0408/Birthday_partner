import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import 'person_cubit.dart';
import 'person_state.dart';

/// Opens the compose sheet (spec §7.2): a modal, not a route -- same
/// reasoning that kept `/otp` unrouted in Phase 2b, a URL-addressable
/// compose screen would have nothing in memory to post to. The live
/// [PersonCubit] is handed down explicitly via `BlocProvider.value` because
/// `showModalBottomSheet` builds its content under the root navigator, one
/// level above wherever `context.read<PersonCubit>()` would otherwise find
/// it.
Future<void> showWishComposeSheet(BuildContext context) {
  final cubit = context.read<PersonCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => BlocProvider<PersonCubit>.value(
      value: cubit,
      child: const WishComposeSheet(),
    ),
  );
}

class WishComposeSheet extends StatefulWidget {
  const WishComposeSheet({super.key});

  @override
  State<WishComposeSheet> createState() => _WishComposeSheetState();
}

class _WishComposeSheetState extends State<WishComposeSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = AppStrings.wishEmpty);
      return;
    }
    if (text.length > 500) {
      setState(() => _error = AppStrings.wishTooLong);
      return;
    }
    setState(() => _error = null);

    final cubit = context.read<PersonCubit>();
    await cubit.postWish(text);

    // The await above is the async gap Task 8 of Phase 2b was bitten by --
    // this widget can have been unmounted (the sheet dismissed some other
    // way, the page navigated away) while postWish() was in flight. Nothing
    // below may touch `context` or call `setState` until this is checked.
    if (!mounted) return;

    if (cubit.state is PersonError) {
      setState(() => _error = AppStrings.wishPostFailed);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PersonCubit, PersonState>(
      builder: (context, state) {
        final posting = state is PersonLoaded && state.posting;
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.md,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('wish_body_field'),
                controller: _controller,
                maxLength: 500,
                maxLines: 4,
                enabled: !posting,
                decoration: InputDecoration(
                  hintText: AppStrings.wishHint,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                key: const Key('wish_post'),
                onPressed: posting ? null : _submit,
                child: posting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(AppStrings.wishPost),
              ),
            ],
          ),
        );
      },
    );
  }
}
