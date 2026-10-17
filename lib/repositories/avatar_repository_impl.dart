import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/logger.dart';
import '../core/result.dart';
import 'avatar_repository.dart';

class AvatarRepositoryImpl implements AvatarRepository {
  AvatarRepositoryImpl(this._client);
  final SupabaseClient _client;

  // Signed URLs are cached for most of their life so every rebuild of an
  // avatar does not mint a new one -- and so NetworkImage, which caches by
  // URL, gets the same URL and does not re-download the photo.
  static const _urlLifetime = Duration(hours: 1);
  static const _reuseFor = Duration(minutes: 50);
  final _urls = <String, ({String url, DateTime at})>{};

  StorageFileApi get _bucket => _client.storage.from(ApiParams.avatarsBucket);

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('no session');
    return id;
  }

  @override
  Future<String> upload(Uint8List bytes, {required String extension}) async {
    final uid = _uid;
    // A new name every time, never an overwrite: a cached signed URL or
    // image for the old photo then cannot show stale pixels.
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$extension';
    try {
      await _bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: _contentType(extension)),
      );
      await _client
          .from(ApiParams.profiles)
          .update({ApiParams.avatarUrl: path}).eq(ApiParams.id, uid);
    } catch (e) {
      throw mapError(e);
    }
    await _removeAllExcept(uid, keep: path);
    return path;
  }

  @override
  Future<void> remove() async {
    final uid = _uid;
    try {
      await _client
          .from(ApiParams.profiles)
          .update({ApiParams.avatarUrl: null}).eq(ApiParams.id, uid);
    } catch (e) {
      throw mapError(e);
    }
    await _removeAllExcept(uid);
  }

  @override
  Future<String> signedUrl(String path) async {
    final cached = _urls[path];
    if (cached != null && DateTime.now().difference(cached.at) < _reuseFor) {
      return cached.url;
    }
    try {
      final url = await _bucket.createSignedUrl(path, _urlLifetime.inSeconds);
      _urls[path] = (url: url, at: DateTime.now());
      return url;
    } catch (e) {
      throw mapError(e);
    }
  }

  /// Old photos are cleanup, not the operation: the profile already points
  /// at the right file, so a failure here is logged, never thrown.
  Future<void> _removeAllExcept(String uid, {String? keep}) async {
    try {
      final files = await _bucket.list(path: uid);
      final stale = [
        for (final f in files)
          if ('$uid/${f.name}' != keep) '$uid/${f.name}',
      ];
      if (stale.isNotEmpty) await _bucket.remove(stale);
    } catch (e, s) {
      Log.error('old avatar cleanup failed', e, s);
    }
  }

  static String _contentType(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
