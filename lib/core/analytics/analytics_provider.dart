import 'package:flutter/widgets.dart';

import 'analytics_user.dart';
import 'app_event.dart';

/// One analytics SDK behind [Analytics]. May throw; the facade isolates failures.
abstract interface class AnalyticsProvider {
  String get name;

  /// Screen tracking, for providers that do it.
  NavigatorObserver? get navigatorObserver;

  Future<void> init();

  Future<void> identify(AnalyticsUser user);

  Future<void> clearUser();

  Future<void> logEvent(AppEvent event, Map<String, Object> params);
}
