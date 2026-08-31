import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../models/delivery_slot.dart';
import '../../models/product.dart';
import '../../repositories/gift_repository.dart';
import 'draft_screen.dart';

/// The slot picker (spec §7): delivery windows for the product's service
/// area, each showing what capacity is left. Pushed (not routed) from
/// [CatalogScreen]'s `_openSlotPicker`, so the default back arrow is
/// supplied by the framework -- unlike the `context.go` routes elsewhere in
/// this app, which need an explicit `leading`.
///
/// [birthday] is carried forward non-nullable (Amendment A2): `CatalogCubit`
/// refuses to emit `CatalogLoaded` for a person with no birthday, so within
/// that state a present birthday is an invariant, asserted once at the push
/// site rather than threaded onward as `Birthday?` -- Task 7's draft screen
/// needs a real `Birthday` for `Birthday.nextOccurrence` and cannot resolve
/// a null case of its own.
///
/// **Only slots on the occasion date are shown (Amendment A3).** Spec §11
/// open question 1 settles that the sender may not choose the occasion date
/// -- a cake dated anything other than the birthday is a different product
/// -- so this screen computes `birthday.nextOccurrence(now)` once and shows
/// only slots that fall exactly on that calendar day.
/// `GiftRepository.slotsIn` filters `>=`, not `=` (`gift_repository.dart`),
/// so the request alone is not sufficient: the exact-date filter below is
/// applied client-side, on top of it. If no window exists on that date, the
/// picker is legitimately empty and shows [AppStrings.giftNoSlots] -- that
/// is correct behaviour, not a bug to soften with a nearby-dates fallback.
class SlotPickerScreen extends StatefulWidget {
  const SlotPickerScreen({
    super.key,
    required this.personId,
    required this.recipientName,
    required this.product,
    required this.birthday,
    DateTime Function()? now,
  }) : _now = now;

  final int personId;
  // Threaded straight through to DraftScreen (fix round 1, item 1):
  // CatalogLoaded already carries the whole Person, so CatalogScreen passes
  // `state.person.displayName` here rather than this screen or DraftCubit
  // re-fetching it via a PersonRepository it doesn't have.
  final String recipientName;
  final Product product;
  final Birthday birthday;
  final DateTime Function()? _now;

  @override
  State<SlotPickerScreen> createState() => _SlotPickerScreenState();
}

enum _Status { loading, loaded, error }

class _SlotPickerScreenState extends State<SlotPickerScreen> {
  _Status _status = _Status.loading;
  List<DeliverySlot> _slots = const [];
  String _errorMessage = '';
  late final DateTime _occasionDate;

  @override
  void initState() {
    super.initState();
    final now = widget._now ?? DateTime.now;
    _occasionDate = widget.birthday.nextOccurrence(now());
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.loading);
    try {
      final slots = await context.read<GiftRepository>().slotsIn(
            widget.product.serviceAreaId,
            onOrAfter: _occasionDate,
          );
      if (!mounted) return;
      setState(() {
        // `slotsIn` returns everything on or after `_occasionDate` --
        // narrowed here to exact calendar-day equality (Amendment A3).
        // Comparing y/m/d rather than DateTime equality directly: `slotDate`
        // could in principle carry a time component, and a stray time of
        // day would make equality fail spuriously.
        _slots = slots.where(_isOnOccasionDate).toList();
        _status = _Status.loaded;
      });
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _errorMessage = f.message;
        _status = _Status.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppStrings.somethingWentWrong;
        _status = _Status.error;
      });
    }
  }

  bool _isOnOccasionDate(DeliverySlot slot) =>
      slot.slotDate.year == _occasionDate.year &&
      slot.slotDate.month == _occasionDate.month &&
      slot.slotDate.day == _occasionDate.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.giftSlotTitle)),
      body: switch (_status) {
        _Status.loading => const Center(child: CircularProgressIndicator()),
        _Status.error => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _load,
                  child: const Text(AppStrings.retry),
                ),
              ],
            ),
          ),
        _Status.loaded when _slots.isEmpty => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(AppStrings.giftNoSlots, textAlign: TextAlign.center),
            ),
          ),
        _Status.loaded => ListView(
            children: [
              for (final slot in _slots)
                ListTile(
                  key: Key('slot_${slot.id}'),
                  enabled: slot.isBookable,
                  title: Text('${slot.windowStart}–${slot.windowEnd}'),
                  trailing: Text(
                    slot.isBookable
                        ? AppStrings.giftSlotRemainingTemplate.replaceFirst(
                            '%s',
                            '${slot.remaining}',
                          )
                        : AppStrings.giftSlotFull,
                  ),
                  // A full slot must not be tappable (Amendment A4): the
                  // picker disables it rather than letting the user
                  // discover it by hitting `delivery_slots_not_oversold`
                  // with a reserve that is real van capacity.
                  onTap: slot.isBookable
                      ? () => _selectSlot(context, slot)
                      : null,
                ),
            ],
          ),
      },
    );
  }

  /// Pushes the real [DraftScreen] (Amendment B2 -- Task 5's placeholder,
  /// which Task 6 kept alive as `_DraftScreenPlaceholder`, is gone).
  ///
  /// [_occasionDate] -- already computed once, in [initState] -- is what
  /// travels forward, not [widget.birthday]: [DraftScreen] (and
  /// `DraftCubit.create`) must not recompute `birthday.nextOccurrence` a
  /// second time from their own clock, because a second derivation could
  /// disagree with this one (a session crossing midnight between the two
  /// screens is enough) and nothing server-side would catch it. See
  /// `draft_cubit.dart`'s class doc.
  void _selectSlot(BuildContext context, DeliverySlot slot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DraftScreen(
          recipientPersonId: widget.personId,
          recipientName: widget.recipientName,
          product: widget.product,
          slot: slot,
          occasionDate: _occasionDate,
        ),
      ),
    );
  }
}
