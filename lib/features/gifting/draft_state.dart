import '../../models/gift.dart';

/// The draft screen's state machine (spec §7): idle, saving, created, or
/// error. Deliberately four flat branches, not a richer shape -- the same
/// convention `CatalogState` and `SlotPickerScreen`'s private `_Status`
/// follow -- because the screen has exactly one action (`create`) and needs
/// nothing more expressive than "not yet tried / in flight / succeeded /
/// failed".
sealed class DraftState {
  const DraftState();
}

/// Nothing submitted yet. The initial state.
class DraftIdle extends DraftState {
  const DraftIdle();
}

/// `createDraft` is in flight. The screen disables its submit button on this
/// state -- not merely on the `ReentrancyGuard`'s own key, which a rebuild
/// cannot observe -- so a slow network still gives the user visible feedback
/// that the tap registered.
class DraftSaving extends DraftState {
  const DraftSaving();
}

/// The RPC succeeded and reserved the slot. [gift] is the row it returned --
/// carried here (not merely a boolean) so the screen can, in principle, show
/// gift-specific detail, though the hold notice itself (spec §7) needs
/// nothing from it beyond the fact that this state was reached.
class DraftCreated extends DraftState {
  const DraftCreated(this.gift);
  final Gift gift;
}

/// [slotFull] distinguishes the one failure the UI must phrase differently
/// enough to invite a different next action -- "pick another window" -- from
/// every other failure, which just needs an apology. Two users racing for
/// the last slot (`23514`) is the only case where trying the exact same
/// input again is pointless; everything else may simply be worth a retry.
class DraftError extends DraftState {
  const DraftError(this.message, {this.slotFull = false});
  final String message;
  final bool slotFull;
}
