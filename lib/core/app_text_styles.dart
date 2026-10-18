import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static TextTheme of(BuildContext context) => Theme.of(context).textTheme;

  static TextStyle sectionHeader(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: Theme.of(context).colorScheme.onSurface,
          );
}
