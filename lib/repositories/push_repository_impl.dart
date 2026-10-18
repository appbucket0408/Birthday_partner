import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/app_colors.dart';
import '../core/app_strings.dart';
import '../core/logger.dart';
import '../core/push_routes.dart';
import '../core/result.dart';
import 'push_repository.dart';

/// The ONLY file in lib/ that imports firebase_messaging, and likewise
/// flutter_local_notifications. Everything else depends on
/// [PushRepository], so the rest of the app is testable without a Firebase
/// binding or a notifications platform channel.
///
/// Deliberately not unit-tested: FirebaseMessaging is a concrete singleton
/// backed by a platform channel, and a test double for it would assert
/// against the double rather than the plugin. This class is covered by the
/// device run in Task 9, the same way ApiClient is. Everything with real
/// logic in it lives in [routeForPayload], which IS tested.
class PushRepositoryImpl implements PushRepository {
  PushRepositoryImpl(
    this._client,
    this._messaging, [
    FlutterLocalNotificationsPlugin? local,
  ]) : _local = local ?? FlutterLocalNotificationsPlugin() {
    // Started here, not on first use: app.dart builds this repository at
    // launch, and the channel must exist before FCM displays a background
    // reminder into it (the manifest's default_notification_channel_id). A
    // channel that does not exist yet makes FCM fall back to its generic
    // "Miscellaneous" one.
    _localReady = _initLocalNotifications();

    // FCM shows nothing for a notification message that arrives while the
    // app is in the foreground -- it only fires onMessage. Without this the
    // reminder is silently dropped, so it is re-shown as a local
    // notification on the same channel.
    _messageSub = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_showForeground(message)),
    );

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
  final FlutterLocalNotificationsPlugin _local;
  final _routes = StreamController<String>.broadcast();
  late final StreamSubscription<String> _refreshSub;
  late final StreamSubscription<RemoteMessage> _openedSub;
  late final StreamSubscription<RemoteMessage> _messageSub;
  late final Future<void> _localReady;

  /// Its id must match `channel_id` in drain_reminders' FCM message and
  /// default_notification_channel_id in AndroidManifest.xml. High
  /// importance is what makes Android show a heads-up banner rather than
  /// filing the reminder silently in the shade.
  static const _channel = AndroidNotificationChannel(
    'birthday_reminders',
    AppStrings.reminderChannelName,
    description: AppStrings.reminderChannelDescription,
    importance: Importance.high,
  );

  /// The drawable FCM also uses (default_notification_icon), named without
  /// its extension the way Android resources are looked up.
  static const _smallIcon = 'ic_stat_candlewish';

  /// Android only: iOS has no Firebase configuration yet, and the plugin's
  /// iOS initialisation needs settings this app does not have.
  Future<void> _initLocalNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
        ),
        // A tap on a foreground reminder goes through the same
        // routeForPayload and the same stream as a tap on an FCM one, so
        // app.dart's single listener handles both.
        onDidReceiveNotificationResponse: (response) {
          final route = routeForLocalPayload(response.payload);
          if (route != null) _routes.add(route);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
    } catch (e, s) {
      // Reminders still arrive in the background without this; only the
      // foreground banner is lost. Not worth failing app startup over.
      Log.error('local notifications setup failed', e, s);
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    // Data-only messages have nothing to show.
    if (notification == null || !Platform.isAndroid) return;
    await _localReady;
    try {
      await _local.show(
        // One notification per message. messageId is unique per send; the
        // mask keeps the hash inside the 32-bit range Android ids require.
        id: (message.messageId ?? '${message.sentTime}').hashCode & 0x7fffffff,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            // Below Android 8 there are no channels, and priority is what
            // decides whether a heads-up banner appears.
            priority: Priority.high,
            icon: _smallIcon,
            color: AppColors.seed,
          ),
        ),
        payload: localPayloadFor(message.data),
      );
    } catch (e, s) {
      Log.error('showing a foreground reminder failed', e, s);
    }
  }

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
    if (message != null) return routeForPayload(message.data);
    // A foreground reminder left in the shade can still be tapped after the
    // app is killed. That launch arrives through the local plugin, not FCM.
    if (!Platform.isAndroid) return null;
    await _localReady;
    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch == null || !launch.didNotificationLaunchApp) return null;
      return routeForLocalPayload(launch.notificationResponse?.payload);
    } catch (e, s) {
      Log.error('reading the local notification launch failed', e, s);
      return null;
    }
  }

  /// Nothing in the app disposes this today -- it lives as long as the app
  /// does -- but leaving the subscriptions unreleasable would make the class
  /// unusable in any test or second instance that ever wanted one.
  Future<void> dispose() async {
    await _refreshSub.cancel();
    await _openedSub.cancel();
    await _messageSub.cancel();
    await _routes.close();
  }
}
