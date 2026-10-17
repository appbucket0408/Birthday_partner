import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/initial_avatar.dart';
import 'person_cubit.dart';
import 'person_state.dart';

/// Matches the wishes_body_length check in the database.
const _maxWishLength = 250;

Future<void> showWishComposeSheet(BuildContext context) {
  final cubit = context.read<PersonCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
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
    if (text.length > _maxWishLength) {
      setState(() => _error = AppStrings.wishTooLong);
      return;
    }
    setState(() => _error = null);

    final cubit = context.read<PersonCubit>();
    await cubit.postWish(text);
    if (!mounted) return;

    final result = cubit.state;
    if (result is PersonLoaded && result.postError != null) {
      final alreadyWished = result.postError == AppStrings.wishAlreadyThisYear;
      setState(() => _error =
          alreadyWished ? AppStrings.wishAlreadyThisYear : AppStrings.wishPostFailed);
      return;
    }
    Navigator.of(context).pop();
  }

  void _useSuggestion(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<PersonCubit, PersonState>(
      builder: (context, state) {
        final posting = state is PersonLoaded && state.posting;
        final name = state is PersonLoaded ? state.person.displayName : '';
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    InitialAvatar(name: name, radius: 22),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.wishSheetTitleTemplate
                                .replaceFirst('%s', name),
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            AppStrings.wishSheetSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final suggestion in AppStrings.wishSuggestions)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: ActionChip(
                            label: Text(suggestion),
                            onPressed:
                                posting ? null : () => _useSuggestion(suggestion),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('wish_body_field'),
                  controller: _controller,
                  autofocus: true,
                  maxLength: _maxWishLength,
                  minLines: 3,
                  maxLines: 6,
                  enabled: !posting,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    hintText: AppStrings.wishHint,
                    errorText: _error,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  key: const Key('wish_post'),
                  onPressed: posting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: posting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text(AppStrings.wishPost),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
