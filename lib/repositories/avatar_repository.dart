import 'dart:typed_data';

/// The signed-in user's profile photo. One responsibility: storing it,
/// clearing it, and turning its stored path into something displayable.
abstract interface class AvatarRepository {
  /// Uploads [bytes] as the new photo, points the profile at it, and removes
  /// the previous one. [extension] is `jpg`, `png` or `webp`. Returns the
  /// stored path.
  Future<String> upload(Uint8List bytes, {required String extension});

  /// Clears the profile's photo and deletes the stored file(s).
  Future<void> remove();

  /// A short-lived URL for the photo at [path]. The bucket is private, so a
  /// stored path is never directly loadable.
  Future<String> signedUrl(String path);
}
