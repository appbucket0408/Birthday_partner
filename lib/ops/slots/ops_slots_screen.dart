import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/delivery_slot.dart';
import '../../repositories/ops_repository.dart';
import 'ops_slots_cubit.dart';
import 'ops_slots_state.dart';

/// The delivery calendar for one service area over a date range.
class OpsSlotsScreen extends StatelessWidget {
  const OpsSlotsScreen({super.key, required this.from, required this.to});

  /// Passed in rather than computed here. Every date this console writes
  /// comes from an explicit choice or from a value read back -- never from
  /// DateTime.now() on the client, which disagreed with Postgres's UTC
  /// `current_date` for 5.5 hours nightly in M3 Phase 1b.
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          OpsSlotsCubit(context.read<OpsRepository>())..load(from: from, to: to),
      child: const OpsSlotsView(),
    );
  }
}

class OpsSlotsView extends StatelessWidget {
  const OpsSlotsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.opsSlotsTab),
        actions: [
          TextButton(
            key: const Key('ops_go_catalog'),
            onPressed: () => context.go('/catalog'),
            child: const Text(AppStrings.opsCatalogTab),
          ),
        ],
      ),
      body: BlocBuilder<OpsSlotsCubit, OpsSlotsState>(
        builder: (context, state) {
          if (state is OpsSlotsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is OpsSlotsError) {
            return Center(
              child: Text(state.message, key: const Key('ops_slots_error')),
            );
          }

          final loaded = state as OpsSlotsLoaded;
          if (loaded.slots.isEmpty) {
            return const Center(child: Text(AppStrings.opsNoSlots));
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              for (final s in loaded.slots) _SlotRow(slot: s),
            ],
          );
        },
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot});
  final DeliverySlot slot;

  String get _date =>
      '${slot.slotDate.year.toString().padLeft(4, '0')}-'
      '${slot.slotDate.month.toString().padLeft(2, '0')}-'
      '${slot.slotDate.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('ops_slot_${slot.id}'),
      title: Text('$_date  ${slot.windowStart}–${slot.windowEnd}'),
      subtitle: Text(
        '${AppStrings.opsCapacity}: ${slot.capacity} · '
        '${AppStrings.opsReservedTemplate.replaceFirst('%s', '${slot.reserved}')}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('ops_slot_minus_${slot.id}'),
            icon: const Icon(Icons.remove),
            onPressed: () => context
                .read<OpsSlotsCubit>()
                .changeCapacity(slot.id, capacity: slot.capacity - 1),
          ),
          IconButton(
            key: Key('ops_slot_plus_${slot.id}'),
            icon: const Icon(Icons.add),
            onPressed: () => context
                .read<OpsSlotsCubit>()
                .changeCapacity(slot.id, capacity: slot.capacity + 1),
          ),
        ],
      ),
    );
  }
}
