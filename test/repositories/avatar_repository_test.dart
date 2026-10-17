@Tags(['contract'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/avatar_repository.dart';
import 'package:birthday_app/repositories/avatar_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Profile photos against real local Storage (20261017000001_avatars.sql).
/// Signs in by EMAIL, not phone: a photo needs only a session, and an email
/// account keeps this suite off the shared test-phone pool entirely.
///
/// Run with:
///   fvm flutter test test/repositories/avatar_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late AvatarRepository avatars;

  // The smallest valid PNG: 1x1, transparent.
  final png = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, // ignore: require_trailing_commas
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    avatars = AvatarRepositoryImpl(ApiClient.instance);
  });

  Future<String> signInFresh() async {
    final email =
        'avatar${DateTime.now().microsecondsSinceEpoch}@example.com';
    await auth.sendEmailOtp(email);
    await auth.verifyEmailOtp(email: email, token: await mailedCode(email));
    return auth.currentUserId!;
  }

  Future<List<String>> storedFiles(String uid) async => [
        for (final f in await ApiClient.instance.storage
            .from('avatars')
            .list(path: uid))
          f.name,
      ];

  tearDown(() async {
    if (ApiClient.instance.auth.currentSession != null) {
      await auth.deleteAccount().catchError((_) {});
    }
  });

  test('upload stores the photo in the user\'s folder and points the '
      'profile at it', () async {
    final uid = await signInFresh();

    final path = await avatars.upload(png, extension: 'png');

    expect(path, startsWith('$uid/'));
    expect(path, endsWith('.png'));
    expect((await auth.loadProfile()).avatarPath, path);
  });

  test('the signed URL actually serves the image', () async {
    await signInFresh();
    final path = await avatars.upload(png, extension: 'png');

    final url = await avatars.signedUrl(path);
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(res.statusCode, 200);
      expect(body, png);
    } finally {
      client.close();
    }
  });

  test('a second upload replaces the first and deletes the old file',
      () async {
    final uid = await signInFresh();
    final first = await avatars.upload(png, extension: 'png');
    // Paths are named by millisecond; make sure the second differs.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await avatars.upload(png, extension: 'png');

    expect(second, isNot(first));
    expect((await auth.loadProfile()).avatarPath, second);
    expect(await storedFiles(uid), [second.split('/').last]);
  });

  test('remove clears the profile and deletes the file', () async {
    final uid = await signInFresh();
    await avatars.upload(png, extension: 'png');

    await avatars.remove();

    expect((await auth.loadProfile()).avatarPath, isNull);
    expect(await storedFiles(uid), isEmpty);
  });

  test('another user cannot get a URL for someone else\'s photo', () async {
    await signInFresh();
    final path = await avatars.upload(png, extension: 'png');
    await auth.deleteAccount();

    // A fresh repository: the first one cached that path's URL.
    final other = AvatarRepositoryImpl(ApiClient.instance);
    await signInFresh();
    await expectLater(other.signedUrl(path), throwsA(isA<AppFailure>()));
  });

  test('deleting the account deletes the photo', () async {
    final uid = await signInFresh();
    await avatars.upload(png, extension: 'png');

    await auth.deleteAccount();

    // Read with the service role: nobody signed in can see the folder now.
    final admin = await _serviceRoleList(uid);
    expect(admin, isEmpty);
  });
}

/// Lists [uid]'s avatar folder as the service role, bypassing RLS, via the
/// local database container -- the only way to check a deleted user's
/// folder is really empty rather than merely invisible.
Future<List<String>> _serviceRoleList(String uid) async {
  final result = await Process.run('docker', [
    'exec',
    'supabase_db_birthday_app',
    'psql',
    '-U',
    'postgres',
    '-tAc',
    "select name from storage.objects where bucket_id = 'avatars' "
        "and name like '$uid/%'",
  ]);
  return (result.stdout as String)
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
}
