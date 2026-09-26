import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/delivery_slot.dart';
import '../../repositories/ops_repository.dart';
import '../signin/signin_cubit.dart';
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

class OpsSlotsView extends StatefulWidget {
  const OpsSlotsView({super.key});

  @override
  State<OpsSlotsView> createState() => _OpsSlotsViewState();
}

class _OpsSlotsViewState extends State<OpsSlotsView> {
  final _date = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _capacity = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    _start.dispose();
    _end.dispose();
    _capacity.dispose();
    super.dispose();
  }

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
          TextButton(
            key: const Key('ops_sign_out'),
            onPressed: () => context.read<SignInCubit>().signOut(),
            child: const Text(AppStrings.opsSignOut),
          ),
        ],
      ),
      // A dead session is not this screen's problem to render. Routing
      // back to sign-in is the only outcome the user can act on -- an
      // inline "JWT expired" behind a Retry button offers a retry that
      // fails identically, forever.
      body: BlocListener<OpsSlotsCubit, OpsSlotsState>(
        listenWhen: (_, s) => s is OpsSlotsError && s.sessionExpired,
        listener: (context, _) {
          context.read<SignInCubit>().sessionExpired();
          context.go('/signin');
        },
        child: BlocBuilder<OpsSlotsCubit, OpsSlotsState>(
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

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Without this the console is stuck on whichever area happens
              // to load first -- and M3 Phase 1a's seed failure was exactly
              // a product and a slot in DIFFERENT areas.
              DropdownButton<int>(
                key: const Key('ops_slots_area_dropdown'),
                value: loaded.selectedAreaId,
                isExpanded: true,
                items: [
                  for (final a in loaded.areas)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (id) {
                  if (id != null) {
                    context.read<OpsSlotsCubit>().selectArea(id);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (loaded.slots.isEmpty)
                const Text(AppStrings.opsNoSlots)
              else
                for (final s in loaded.slots) _SlotRow(slot: s),
              const Divider(height: AppSpacing.xl),
              _addForm(context, loaded),
            ],
          );
          },
        ),
      ),
    );
  }

  /// Creating a window is this screen's reason to exist: the capacity
  /// editor can only adjust slots that already exist, and a new city has
  /// none.
  ///
  /// The DATE comes from the range the cubit already holds -- chosen by the
  /// caller, never from DateTime.now() in here. Postgres runs UTC and this
  /// host runs IST, and M3 Phase 1b shipped a fixture that passed by day
  /// and failed by night for exactly that reason.
  Widget _addForm(BuildContext context, OpsSlotsLoaded loaded) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppStrings.opsAddSlot),
          TextField(
            key: const Key('ops_new_date'),
            controller: _date,
            decoration: const InputDecoration(
              labelText: AppStrings.opsSlotDate,
              hintText: 'YYYY-MM-DD',
            ),
          ),
          TextField(
            key: const Key('ops_new_start'),
            controller: _start,
            decoration:
                const InputDecoration(labelText: AppStrings.opsWindowStart),
          ),
          TextField(
            key: const Key('ops_new_end'),
            controller: _end,
            decoration:
                const InputDecoration(labelText: AppStrings.opsWindowEnd),
          ),
          TextField(
            key: const Key('ops_new_capacity'),
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: AppStrings.opsCapacity),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('ops_add_slot'),
            onPressed: () {
              // Parsed here, strictly, rather than handed to the database:
              // an unparseable date would otherwise reach Postgres as a
              // cast error with no useful message. Strict YYYY-MM-DD, so
              // '20-11-2026' is refused rather than silently reinterpreted.
              final raw = _date.text.trim();
              final parsed = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)
                  ? DateTime.tryParse(raw)
                  : null;
              if (parsed == null) {
                context.read<OpsSlotsCubit>().rejectDate();
                return;
              }
              context.read<OpsSlotsCubit>().addSlot(
                    slotDate: parsed,
                    windowStart: _start.text.trim(),
                    windowEnd: _end.text.trim(),
                    capacity: int.tryParse(_capacity.text.trim()) ?? -1,
                  );
            },
            child: const Text(AppStrings.opsAddSlot),
          ),
        ],
      );
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
