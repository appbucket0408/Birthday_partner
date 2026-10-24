import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'core/analytics.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _initMonitoring();
  await ApiClient.init();
  runApp(const BirthdayApp());
}

Future<void> _initMonitoring() async {
  final crashlytics = FirebaseCrashlytics.instance;
  // Debug runs stay out of the dashboards.
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
  Analytics.enable();
}
