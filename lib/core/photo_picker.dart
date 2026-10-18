import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_strings.dart';

/// What the user did in [pickProfilePhoto] or [pickWishPhoto].
sealed class PhotoChoice {
  const PhotoChoice();
}

final class PhotoPicked extends PhotoChoice {
  const PhotoPicked(this.bytes, this.extension);
  final Uint8List bytes;

  /// `jpg`, `png` or `webp` -- the only types the avatars bucket accepts.
  final String extension;
}

final class PhotoRemoved extends PhotoChoice {
  const PhotoRemoved();
}

/// The picked file is not a type the bucket accepts.
final class PhotoUnsupported extends PhotoChoice {
  const PhotoUnsupported();
}

/// Bottom sheet → gallery or camera, resized on the device to 512px so an
/// upload is tens of kilobytes rather than a full camera frame. Returns null
/// when the user backs out at any point. [canRemove] adds "Remove photo".
Future<PhotoChoice?> pickProfilePhoto(
  BuildContext context, {
  required bool canRemove,
  ImagePicker? picker,
}) async {
  final source = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('photo_from_gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text(AppStrings.photoFromGallery),
            onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
          ),
          ListTile(
            key: const Key('photo_from_camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text(AppStrings.photoFromCamera),
            onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
          ),
          if (canRemove)
            ListTile(
              key: const Key('photo_remove'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheet).colorScheme.error,
              ),
              title: Text(
                AppStrings.photoRemove,
                style: TextStyle(color: Theme.of(sheet).colorScheme.error),
              ),
              onTap: () => Navigator.of(sheet).pop(const PhotoRemoved()),
            ),
        ],
      ),
    ),
  );
  if (source is PhotoRemoved) return source;
  if (source is! ImageSource) return null;

  final file = await (picker ?? ImagePicker()).pickImage(
    source: source,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
    preferredCameraDevice: CameraDevice.front,
  );
  return _toChoice(file);
}

/// Gallery only, one photo, resized on the device to 1440px -- enough for a
/// full-width post, small enough to stay well under the wish_photos bucket's
/// 5 MB limit. Returns null when the user backs out. Throws the picker's
/// PlatformException when photo access is denied.
Future<PhotoChoice?> pickWishPhoto({ImagePicker? picker}) async {
  final file = await (picker ?? ImagePicker()).pickImage(
    source: ImageSource.gallery,
    maxWidth: 1440,
    maxHeight: 1440,
    imageQuality: 85,
  );
  return _toChoice(file);
}

Future<PhotoChoice?> _toChoice(XFile? file) async {
  if (file == null) return null;

  final extension = switch (file.name.split('.').last.toLowerCase()) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    _ => null,
  };
  if (extension == null) return const PhotoUnsupported();
  return PhotoPicked(await file.readAsBytes(), extension);
}
