import '../../models/person.dart';
import '../../models/wish.dart';

sealed class PersonState {
  const PersonState();
}

final class PersonLoading extends PersonState {
  const PersonLoading();
}

/// [posting] is true while a wish write is in flight -- the compose sheet
/// reads it to disable its own post button and show a spinner, on top of
/// (not instead of) [PersonCubit.guard]'s own re-entrancy protection: the
/// guard stops a second write from ever reaching the repository, and this
/// flag is what keeps the button from inviting a second tap in the first
/// place.
///
/// [viewerCelebrates] is whether the signed-in user's own celebration list
/// (`GraphRepository.celebrations()`) contains this person -- the only
/// client-visible signal that distinguishes "I celebrate them" from the
/// other two branches of `private.can_see_person` (my own profile, or they
/// celebrate me). The compose FAB is gated on this AND on `person.birthday`
/// being non-null: `wishes_insert_own` refuses the write server-side
/// regardless, so showing the affordance to a viewer who does not celebrate
/// this person would offer something that can only ever fail.
///
/// [postError] is a transient message from the last failed [postWish] --
/// not a reason to blank the screen, since [wishes] is still the
/// last-known-good wall. It is cleared at the start of the next attempt,
/// the same shape `TimelineLoaded.error` uses for row-action failures.
final class PersonLoaded extends PersonState {
  const PersonLoaded({
    required this.person,
    required this.celebratorCount,
    required this.wishes,
    required this.viewerCelebrates,
    this.posting = false,
    this.postError,
  });

  final Person person;
  final int celebratorCount;
  final List<Wish> wishes;
  final bool viewerCelebrates;
  final bool posting;
  final String? postError;
}

final class PersonError extends PersonState {
  const PersonError(this.message);

  final String message;
}
