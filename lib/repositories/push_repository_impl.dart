import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/logger.dart';
import '../core/push_routes.dart';
import '../core/result.dart';
import 'push_repository.dart';

/// The ONLY file in lib/ that imports firebase_messaging. Everything else
/// depends on [PushRepository], so the rest of the app is testable without
/// a Firebase binding.
///
/// Deliberately not unit-tested: FirebaseMessaging is a concrete singleton
/// backed by a platform channel, and a test double for it would assert
/// against the double rather than the plugin. This class is covered by the
/// device run in Task 9, the same way ApiClient is. Everything with real
/// logic in it lives in [routeForPayload], which IS tested.
class PushRepositoryImpl implements PushRepository {
  PushRepositoryImpl(this._client, this._messaging) {
    // Re-register internally rather than exposing a refresh stream for
    // someone else to wire up. A token rotated by the OS leaves the user
    // unreachable while the stale row still satisfies
    // next_reminder_batch's `exists` check -- so reminders are claimed and
    // burned against a dead token, which is worse than not being
    // registered at all.
    _refreshSub = _messaging.onTokenRefresh.listen((_) {
      registerThisDevice().catchError((Object e, StackTrace s) {
        Log.error('re-register after token refresh failed', e, s);
      });
    });

    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = routeForPayload(message.data);
      if (route != null) _routes.add(route);
    });
  }

  final SupabaseClient _client;
  final FirebaseMessaging _messaging;
  final _routes = StreamController<String>.broadcast();
  late final StreamSubscription<String> _refreshSub;
  late final StreamSubscription<RemoteMessage> _openedSub;

  @override
  Future<PushPermission> currentPermission() async {
    final s = await _messaging.getNotificationSettings();
    return switch (s.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        PushPermission.granted,
      // deniedPermanently is the state Android 13 puts the app in after a
      // SECOND refusal. Treating it as anything but denied would have the
      // cubit call requestPermission() forever against an OS that will
      // never show a prompt again.
      AuthorizationStatus.denied ||
      AuthorizationStatus.deniedPermanently =>
        PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.notDetermined,
    };
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> registerThisDevice() async {
    final token = await _messaging.getToken();
    if (token == null) {
      throw const PermissionFailure('This device has no push token.');
    }
    try {
      await _client.rpc(
        ApiParams.rpcRegisterDeviceToken,
        params: {
          ApiParams.pToken: token,
          ApiParams.pPlatform: Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> deleteThisDeviceToken() async {
    final token = await _messaging.getToken();
    if (token == null) return;
    try {
      await _client
          .from(ApiParams.deviceTokens)
          .delete()
          .eq(ApiParams.token, token);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Stream<String> get notificationRoutes => _routes.stream;

  @override
  Future<String?> initialRoute() async {
    final message = await _messaging.getInitialMessage();
    if (message == null) return null;
    return routeForPayload(message.data);
  }

  /// Nothing in the app disposes this today -- it lives as long as the app
  /// does -- but leaving the subscriptions unreleasable would make the class
  /// unusable in any test or second instance that ever wanted one.
  Future<void> dispose() async {
    await _refreshSub.cancel();
    await _openedSub.cancel();
    await _routes.close();
  }
}
