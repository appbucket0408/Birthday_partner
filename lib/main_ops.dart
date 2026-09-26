import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'ops/ops_app.dart';

/// The ops console's entry point, built for web:
///   fvm flutter build web -t lib/main_ops.dart
///
/// Separate from lib/main.dart so the console and the consumer app share
/// models and repositories without sharing a router, a session, or the
/// contacts and phone-OTP surface that has no meaning for staff.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();
  runApp(const OpsApp());
}
