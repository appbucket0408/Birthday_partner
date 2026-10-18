import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A round avatar showing the first letter of [name]: for other people, who
/// have no visible photo, and as `ProfileAvatar`'s fallback for your own.
///
/// The tint is picked from the name, so the same person always gets the
/// same colour and a list of people is not one repeated circle.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.radius = 20});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final trimmed = name.trim();
    // Summed code units rather than hashCode: stable across runs.
    final seed = trimmed.codeUnits.fold(0, (a, b) => a + b);
    final palette = dark ? AppColors.avatarDark : AppColors.avatarLight;
    final (background, foreground) = palette[seed % palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundColor: foreground,
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w700),
      ),
    );
  }
}
