import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/logger.dart';
import '../core/result.dart';
import '../models/feed_entry.dart';
import '../models/wish.dart';
import 'wish_repository.dart';

class WishRepositoryImpl implements WishRepository {
  WishRepositoryImpl(this._client);
  final SupabaseClient _client;
  static const _urlLifetime = Duration(hours: 1);
  static const _reuseFor = Duration(minutes: 50);
  final _urls = <String, ({String url, DateTime at})>{};

  StorageFileApi get _photos =>
      _client.storage.from(ApiParams.wishPhotosBucket);

  @override
  Future<List<Wish>> wishesFor(int personId) async {
    try {
      final rows = await _client
          .from(ApiParams.wishes)
          .select()
          .eq(ApiParams.subjectPersonId, personId)
          .order(ApiParams.createdAt, ascending: false);

      final wishes = (rows as List)
          .map((r) => Wish.fromRow(r as Map<String, dynamic>))
          .toList();
      if (wishes.isEmpty) return wishes;
      final authorIds =
          wishes.map((w) => w.authorProfileId).toSet().toList(growable: false);

      final people = await _client
          .from(ApiParams.people)
          .select('${ApiParams.profileId}, ${ApiParams.displayName}')
          .inFilter(ApiParams.profileId, authorIds);

      final names = <String, String>{
        for (final p in people as List)
          (p as Map<String, dynamic>)[ApiParams.profileId] as String:
              p[ApiParams.displayName] as String,
      };

      return wishes
          .map((w) => w.withAuthorName(names[w.authorProfileId]))
          .toList(growable: false);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<FeedEntry>> feed({DateTime? before, int limit = 20}) async {
    try {
      var query = _client.from(ApiParams.wishes).select();
      if (before != null) {
        query = query.lt(ApiParams.createdAt, before.toUtc().toIso8601String());
      }
      final rows = await query
          .order(ApiParams.createdAt, ascending: false)
          .limit(limit);

      final wishes = (rows as List)
          .map((r) => Wish.fromRow(r as Map<String, dynamic>))
          .toList();
      if (wishes.isEmpty) return const [];

      // Names come from `people`, as on the wall: authors outside the
      // viewer's graph come back missing and render unattributed.
      final authorIds =
          wishes.map((w) => w.authorProfileId).toSet().toList(growable: false);
      final subjectIds =
          wishes.map((w) => w.subjectPersonId).toSet().toList(growable: false);
      final lookups = await Future.wait([
        _client
            .from(ApiParams.people)
            .select('${ApiParams.profileId}, ${ApiParams.displayName}')
            .inFilter(ApiParams.profileId, authorIds),
        _client
            .from(ApiParams.people)
            .select('${ApiParams.id}, ${ApiParams.displayName}')
            .inFilter(ApiParams.id, subjectIds),
      ]);

      final authors = <String, String>{
        for (final p in lookups[0] as List)
          (p as Map<String, dynamic>)[ApiParams.profileId] as String:
              p[ApiParams.displayName] as String,
      };
      final subjects = <int, String>{
        for (final p in lookups[1] as List)
          (p as Map<String, dynamic>)[ApiParams.id] as int:
              p[ApiParams.displayName] as String,
      };

      return [
        for (final w in wishes)
          FeedEntry(
            wish: w.withAuthorName(authors[w.authorProfileId]),
            subjectName: subjects[w.subjectPersonId],
          ),
      ];
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<List<Wish>> wishesToMe() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthFailure('no session');
    final int? myPersonId;
    try {
      final row = await _client
          .from(ApiParams.people)
          .select(ApiParams.id)
          .eq(ApiParams.profileId, me)
          .maybeSingle();
      myPersonId = row?[ApiParams.id] as int?;
    } catch (e) {
      throw mapError(e);
    }
    if (myPersonId == null) return const [];
    return wishesFor(myPersonId);
  }

  @override
  Future<void> post({
    required int personId,
    required String body,
    required int occasionYear,
    String? photoPath,
  }) async {
    final authorId = _client.auth.currentUser?.id;
    if (authorId == null) throw const AuthFailure('no session');
    try {
      await _client.from(ApiParams.wishes).insert({
        ApiParams.authorProfileId: authorId,
        ApiParams.subjectPersonId: personId,
        ApiParams.body: body,
        ApiParams.occasionYear: occasionYear,
        if (photoPath != null) ApiParams.photoPath: photoPath,
      });
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String extension,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('no session');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$extension';
    try {
      await _photos.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: _contentType(extension)),
      );
    } catch (e) {
      throw mapError(e);
    }
    return path;
  }

  @override
  Future<void> removePhoto(String path) async {
    try {
      await _photos.remove([path]);
    } catch (e, s) {
      Log.error('unposted wish photo cleanup failed', e, s);
    }
  }

  @override
  Future<String> photoUrl(String path) async {
    final cached = _urls[path];
    if (cached != null && DateTime.now().difference(cached.at) < _reuseFor) {
      return cached.url;
    }
    try {
      final url = await _photos.createSignedUrl(path, _urlLifetime.inSeconds);
      _urls[path] = (url: url, at: DateTime.now());
      return url;
    } catch (e) {
      throw mapError(e);
    }
  }

  static String _contentType(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
