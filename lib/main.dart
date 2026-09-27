import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await ApiClient.init();
  runApp(const BirthdayApp());
}
