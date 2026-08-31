import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/gift.dart';
import '../../repositories/gift_repository.dart';
import 'gift_list_cubit.dart';
import 'gift_list_state.dart';

/// The gift list (spec §7): "the sender's own gifts and their status,
/// reached from the profile." Fed by `GiftRepository.myGifts()`, which
/// already filters to the caller's own `sender_profile_id` server-side
/// (Task 4's contract assertion 7) -- this screen renders exactly what it
/// is handed, with no client-side filtering of its own.
class GiftListScreen extends StatelessWidget {
  const GiftListScreen({super.key, DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          GiftListCubit(context.read<GiftRepository>(), now: _now)..load(),
      child: const GiftListView(),
    );
  }
}

/// The screen's actual content, split out from [GiftListScreen] (not
/// underscore-private) for the same reason `DraftView` is split from
/// `DraftScreen`: a widget test can drive it with a mocked [GiftListCubit]
/// via `BlocProvider.value`.
class GiftListView extends StatelessWidget {
  const GiftListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.giftListTitle),
        // '/gifts' is reached with context.go, which REPLACES the page
        // stack -- Navigator.canPop() is false and automaticallyImplyLeading
        // finds nothing to pop, the same trap '/profile', '/import' and
        // '/settings' already needed an explicit `leading` for.
        leading: IconButton(
          key: const Key('gift_list_back_button'),
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: BlocBuilder<GiftListCubit, GiftListState>(
        builder: (context, state) => switch (state) {
          GiftListLoading() =>
            const Center(child: CircularProgressIndicator()),
          GiftListError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, key: const Key('gift_list_error')),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<GiftListCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          GiftListLoaded() when state.gifts.isEmpty => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  AppStrings.giftListEmpty,
                  key: Key('gift_list_empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          GiftListLoaded() => ListView(
              children: [
                for (final gift in state.gifts)
                  _GiftRow(
                    gift: gift,
                    holdExpired: state.expiredIds.contains(gift.id),
                  ),
              ],
            ),
        },
      ),
    );
  }
}

class _GiftRow extends StatelessWidget {
  const _GiftRow({required this.gift, required this.holdExpired});

  final Gift gift;
  final bool holdExpired;

  static String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _statusLabel(GiftStatus status) => switch (status) {
        GiftStatus.draft => AppStrings.giftStatusDraft,
        GiftStatus.paid => AppStrings.giftStatusPaid,
        GiftStatus.awaitingConfirm => AppStrings.giftStatusAwaitingConfirm,
        GiftStatus.confirmed => AppStrings.giftStatusConfirmed,
        GiftStatus.placed => AppStrings.giftStatusPlaced,
        GiftStatus.outForDelivery => AppStrings.giftStatusOutForDelivery,
        GiftStatus.delivered => AppStrings.giftStatusDelivered,
        GiftStatus.expired => AppStrings.giftStatusExpired,
        GiftStatus.declined => AppStrings.giftStatusDeclined,
        GiftStatus.deliveryFailed => AppStrings.giftStatusDeliveryFailed,
        GiftStatus.refunded => AppStrings.giftStatusRefunded,
        GiftStatus.unknown => AppStrings.giftStatusUnknown,
      };

  // Every gift in this phase has a null deliveryCity (spec §6 -- it is
  // written only at confirmation, which nothing in this phase reaches), so
  // giftCityPending is the expected, common case locally, not a bug.
  String _cityLabel() => gift.deliveryCity == null
      ? AppStrings.giftCityPending
      : AppStrings.giftCityTemplate.replaceFirst('%s', gift.deliveryCity!);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('gift_list_item_${gift.id}'),
      title: Text(
        AppStrings.giftProductTemplate.replaceFirst('%s', '${gift.productId}'),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dateLabel(gift.occasionDate)),
          Text(
            _statusLabel(gift.status),
            key: Key('gift_list_status_${gift.id}'),
          ),
          Text(_cityLabel(), key: Key('gift_list_city_${gift.id}')),
          if (holdExpired)
            Text(
              AppStrings.giftHoldExpired,
              key: Key('gift_list_hold_expired_${gift.id}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
