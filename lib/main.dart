import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();
  runApp(const BirthdayApp());
}
