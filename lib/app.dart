import 'package:flutter/material.dart';

import 'core/app_colors.dart';
import 'core/app_strings.dart';

class BirthdayApp extends StatelessWidget {
  const BirthdayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      theme: ThemeData(colorScheme: AppColors.light(), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: AppColors.dark(), useMaterial3: true),
      home: const Scaffold(body: Center(child: Text(AppStrings.appName))),
    );
  }
}
