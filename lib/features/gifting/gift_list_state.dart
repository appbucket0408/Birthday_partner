import '../../models/gift.dart';

/// The gift list's state machine (spec §7): the sender's own gifts and their
/// status, reached from the profile. Three flat branches, the same
/// convention `DraftState` and `CatalogState` follow: nothing more
/// expressive is needed for "not yet tried / loaded / failed" -- there is
/// exactly one action, `load()`.
sealed class GiftListState {
  const GiftListState();
}

/// Nothing loaded yet, or a reload in flight. The initial state.
class GiftListLoading extends GiftListState {
  const GiftListLoading();
}

/// [gifts] is exactly what `GiftRepository.myGifts()` returned, newest-first
/// (the repository orders by `created_at desc` server-side) -- this state
/// never re-sorts.
///
/// [expiredIds] is computed once, at load time, against the cubit's
/// injected clock (`Gift.isHoldExpiredAt`) -- never against the real clock
/// at render time, so the screen's "hold expired" flag cannot drift from
/// whatever moment `load()` actually ran, and a test never depends on when
/// it happens to execute.
class GiftListLoaded extends GiftListState {
  const GiftListLoaded(this.gifts, this.expiredIds);
  final List<Gift> gifts;
  final Set<int> expiredIds;
}

/// [message] is always human-readable -- either an [AppFailure]'s own
/// message or [AppStrings.somethingWentWrong], never a raw exception's
/// `toString()`.
class GiftListError extends GiftListState {
  const GiftListError(this.message);
  final String message;
}
