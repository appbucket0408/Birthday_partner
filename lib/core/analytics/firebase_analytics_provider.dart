import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

import 'analytics_provider.dart';
import 'analytics_user.dart';
import 'app_event.dart';

class FirebaseAnalyticsProvider implements AnalyticsProvider {
  FirebaseAnalyticsProvider({required this.collectionEnabled});

  /// Off in debug so test runs stay out of the dashboards.
  final bool collectionEnabled;

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  @override
  String get name => 'Firebase';

  @override
  late final NavigatorObserver navigatorObserver =
      FirebaseAnalyticsObserver(analytics: _analytics);

  @override
  Future<void> init() =>
      _analytics.setAnalyticsCollectionEnabled(collectionEnabled);

  /// The id only: Google's terms forbid phone, birthday or other PII.
  @override
  Future<void> identify(AnalyticsUser user) async {
    await _analytics.setUserId(id: user.id);
    await FirebaseCrashlytics.instance.setUserIdentifier(user.id);
  }

  @override
  Future<void> clearUser() async {
    await _analytics.setUserId(id: null);
    await FirebaseCrashlytics.instance.setUserIdentifier('');
  }

  @override
  Future<void> logEvent(AppEvent event, Map<String, Object> params) =>
      _analytics.logEvent(name: event.eventName, parameters: params);
}
