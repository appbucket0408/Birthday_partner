import '../models/wish.dart';

/// The wish wall. One responsibility: reading and writing wishes.
abstract interface class WishRepository {
  /// A person's wall, newest first, with author names resolved where the
  /// viewer is connected to the author and null where they are not.
  Future<List<Wish>> wishesFor(int personId);

  /// Posts a wish. RLS refuses unless the caller celebrates [personId].
  /// [occasionYear] comes from `Birthday.occasionYear`, never from the user.
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
  });
}
