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
final class PersonLoaded extends PersonState {
  const PersonLoaded({
    required this.person,
    required this.celebratorCount,
    required this.wishes,
    this.posting = false,
  });

  final Person person;
  final int celebratorCount;
  final List<Wish> wishes;
  final bool posting;
}

final class PersonError extends PersonState {
  const PersonError(this.message);

  final String message;
}
