import 'dart:typed_data';

import '../models/wish.dart';

/// The wish wall. One responsibility: reading and writing wishes.
abstract interface class WishRepository {
  /// A person's wall, newest first, with author names resolved where the
  /// viewer is connected to the author and null where they are not.
  Future<List<Wish>> wishesFor(int personId);

  /// The signed-in user's own wall: [wishesFor] their own `people` row, or
  /// empty when they have none yet (it is created when they claim it).
  Future<List<Wish>> wishesToMe();

  /// Posts a wish. RLS refuses unless the caller celebrates [personId].
  /// [occasionYear] comes from `Birthday.occasionYear`, never from the user.
  /// [photoPath] is a path returned by [uploadPhoto].
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
    String? photoPath,
  });

  /// Stores a photo for a wish about to be posted and returns its path.
  /// [extension] is `jpg`, `png` or `webp`.
  Future<String> uploadPhoto(Uint8List bytes, {required String extension});

  /// Removes an uploaded photo whose wish was never posted. Cleanup only:
  /// never throws.
  Future<void> removePhoto(String path);

  /// A short-lived URL for the wish photo at [path]. The bucket is private,
  /// so a stored path is never directly loadable.
  Future<String> photoUrl(String path);
}
