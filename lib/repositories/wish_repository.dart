import 'dart:typed_data';

import '../models/feed_entry.dart';
import '../models/wish.dart';

abstract interface class WishRepository {

  Future<List<Wish>> wishesFor(int personId);
  Future<List<Wish>> wishesToMe();
  Future<List<FeedEntry>> feed({DateTime? before, int limit = 20});
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
