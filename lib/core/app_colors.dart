import 'package:flutter/material.dart';

/// One seed colour; Material 3 derives the rest. The spec declines golden
/// tests in M1 precisely because this is expected to change, so nothing here
/// is load-bearing beyond being centralised.
abstract final class AppColors {
  static const seed = Color(0xFFE05A47);

  static ColorScheme light() =>
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
  static ColorScheme dark() =>
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
}
