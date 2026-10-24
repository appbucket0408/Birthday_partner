import 'package:flutter/widgets.dart';

import 'analytics/analytics_provider.dart';
import 'analytics/analytics_user.dart';
import 'analytics/app_event.dart';
import 'logger.dart';

export 'analytics/analytics_user.dart';
export 'analytics/app_event.dart';

/// The app's single analytics entry point: fans every call out to all providers.
/// A no-op until [init], so tests and the ops console never touch an SDK.
abstract final class Analytics {
  static List<AnalyticsProvider> _providers = const [];

  static bool get enabled => _providers.isNotEmpty;

  static List<NavigatorObserver> get navigatorObservers => [
        for (final p in _providers) ?p.navigatorObserver,
      ];

  /// Call once from main(), after Firebase.initializeApp().
  static Future<void> init(List<AnalyticsProvider> providers) async {
    _providers = List.unmodifiable(providers);
    await _forEach('init', (p) => p.init());
  }

  @visibleForTesting
  static void reset() => _providers = const [];

  static Future<void> identify(AnalyticsUser user) =>
      _forEach('identify', (p) => p.identify(user));

  /// On sign-out, so the next user on the device doesn't inherit the identity.
  static Future<void> clearUser() => _forEach('clearUser', (p) => p.clearUser());

  /// Fire with `.ignore()`: never awaited by a user flow, never throws.
  static Future<void> log(
    AppEvent event, [
    Map<String, Object> params = const {},
  ]) =>
      _forEach(event.eventName, (p) => p.logEvent(event, params));

  /// One provider failing never affects the others or the caller.
  static Future<void> _forEach(
    String label,
    Future<void> Function(AnalyticsProvider) action,
  ) async {
    await Future.wait(
      _providers.map((p) async {
        try {
          await action(p);
        } catch (e, s) {
          Log.error('${p.name} analytics $label failed', e, s);
        }
      }),
    );
  }
}
