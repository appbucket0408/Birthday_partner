import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/delivery_slot.dart';
import '../../models/product.dart';
import '../../repositories/gift_repository.dart';
import 'draft_cubit.dart';
import 'draft_state.dart';

/// The draft screen (spec §7): recipient, product, slot, an optional
/// message, then create -- and an honest statement that the flow stops
/// here. Pushed (not routed) from [SlotPickerScreen]'s `_selectSlot`, the
/// same reasoning [SlotPickerScreen] itself documents: neither screen can
/// carry its accumulated selection through a URL.
///
/// [occasionDate] is handed down verbatim from the picker's own
/// `_occasionDate` -- computed there, once, via `birthday.nextOccurrence` --
/// and never recomputed here (Amendment B1; see `draft_cubit.dart`'s class
/// doc for why a second derivation would be a bug, not a redundancy).
///
/// [recipientName] is likewise handed down, not fetched: `CatalogLoaded`
/// already carries the whole `Person` (fix round 1, item 1), so
/// `state.person.displayName` threads forward through the same push chain
/// the birthday and the occasion date already use -- catalog ->
/// `SlotPickerScreen` -> here. Neither this screen nor `DraftCubit` takes a
/// `PersonRepository`: the data is already in hand, and re-fetching it would
/// add a dependency and a failure mode for something already known.
class DraftScreen extends StatelessWidget {
  const DraftScreen({
    super.key,
    required this.recipientPersonId,
    required this.recipientName,
    required this.product,
    required this.slot,
    required this.occasionDate,
  });

  final int recipientPersonId;
  final String recipientName;
  final Product product;
  final DeliverySlot slot;
  final DateTime occasionDate;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DraftCubit(context.read<GiftRepository>()),
      child: DraftView(
        recipientPersonId: recipientPersonId,
        recipientName: recipientName,
        product: product,
        slot: slot,
        occasionDate: occasionDate,
      ),
    );
  }
}

/// The screen's actual content, split out from [DraftScreen] (not
/// underscore-private) for the same reason `CatalogView` is split from
/// `CatalogScreen`: a widget test can drive it with a mocked [DraftCubit]
/// via `BlocProvider.value`.
class DraftView extends StatefulWidget {
  const DraftView({
    super.key,
    required this.recipientPersonId,
    required this.recipientName,
    required this.product,
    required this.slot,
    required this.occasionDate,
  });

  final int recipientPersonId;
  final String recipientName;
  final Product product;
  final DeliverySlot slot;
  final DateTime occasionDate;

  @override
  State<DraftView> createState() => _DraftViewState();
}

class _DraftViewState extends State<DraftView> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _messageController.text.trim();
    context.read<DraftCubit>().create(
          recipientPersonId: widget.recipientPersonId,
          productId: widget.product.id,
          slotId: widget.slot.id,
          occasionDate: widget.occasionDate,
          message: text.isEmpty ? null : text,
        );
  }

  /// The dead-end notice (spec §7, Amendment B3): plainly says the slot is
  /// held for fifteen minutes and that checkout is not built yet. **Not**
  /// "payment coming soon" -- a screen implying a payment step is next is
  /// worse than one that says outright there isn't one.
  Future<void> _showHoldNotice() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.giftHoldNoticeTitle),
        content: const Text(AppStrings.giftHoldNoticeBody),
        actions: [
          FilledButton(
            key: const Key('gift_see_my_gifts'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.giftSeeMyGifts),
          ),
        ],
      ),
    );
    // The dialog's own pop already happened above; this await is the same
    // async gap `wish_compose_sheet.dart` and `settings_screen.dart` guard
    // against. `context` is not touched again unless it is still mounted --
    // the user could have backgrounded and killed this route some other way
    // while the dialog was up.
    if (!mounted) return;
    context.go('/gifts');
  }

  String _windowLabel() {
    final d = widget.occasionDate;
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return '$date, ${widget.slot.windowStart}–${widget.slot.windowEnd}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DraftCubit, DraftState>(
      listener: (context, state) {
        if (state is DraftCreated) _showHoldNotice();
      },
      builder: (context, state) {
        final saving = state is DraftSaving;
        return Scaffold(
          appBar: AppBar(title: const Text(AppStrings.giftDraftTitle)),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.giftDraftRecipientTemplate.replaceFirst(
                    '%s',
                    widget.recipientName,
                  ),
                  key: const Key('gift_recipient_label'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(widget.product.name),
                Text(widget.product.priceLabel),
                const SizedBox(height: AppSpacing.sm),
                Text(_windowLabel(), key: const Key('gift_window_label')),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('gift_message_field'),
                  controller: _messageController,
                  // Matches `gifts_message_length` (280) -- enforced here
                  // too rather than letting the DB reject an over-length
                  // message after a round trip.
                  maxLength: 280,
                  maxLines: 3,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    hintText: AppStrings.giftMessageHint,
                  ),
                ),
                if (state is DraftError) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    state.message,
                    key: const Key('gift_draft_error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  key: const Key('gift_create'),
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(AppStrings.giftCreate),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
