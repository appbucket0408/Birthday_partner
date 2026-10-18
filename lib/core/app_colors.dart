import 'package:flutter/material.dart';

/// The palette is taken from the app icon -- coral flame, apricot and honey
/// glow, warm cream -- rather than left to Material's seed derivation, whose
/// secondary and tertiary roles came out as muddy pinks and olives. Every
/// role a screen reads is pinned here; anything else still derives from the
/// seed.
abstract final class AppColors {
  static const seed = Color(0xFFD4473A);

  static ColorScheme light() =>
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light)
          .copyWith(
        primary: seed,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFFFE2DA),
        onPrimaryContainer: const Color(0xFF5C1A12),
        secondary: const Color(0xFFB0602A),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFFFE6D1),
        onSecondaryContainer: const Color(0xFF5A2E0E),
        tertiary: const Color(0xFF8F6400),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFFFEDC2),
        onTertiaryContainer: const Color(0xFF4A3300),
        error: const Color(0xFFB3261E),
        onError: Colors.white,
        surface: const Color(0xFFFFFAF6),
        onSurface: const Color(0xFF2B201D),
        onSurfaceVariant: const Color(0xFF6E5F59),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFFF3EC),
        surfaceContainer: const Color(0xFFFCEDE5),
        surfaceContainerHigh: const Color(0xFFF7E6DD),
        surfaceContainerHighest: const Color(0xFFF1DFD5),
        outline: const Color(0xFFA8968E),
        outlineVariant: const Color(0xFFEBDCD4),
        surfaceTint: Colors.transparent,
      );

  static ColorScheme dark() =>
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)
          .copyWith(
        primary: const Color(0xFFFF8E7A),
        onPrimary: const Color(0xFF5C1309),
        primaryContainer: const Color(0xFF6E281D),
        onPrimaryContainer: const Color(0xFFFFDAD2),
        secondary: const Color(0xFFFFB27A),
        onSecondary: const Color(0xFF4E2600),
        secondaryContainer: const Color(0xFF603617),
        onSecondaryContainer: const Color(0xFFFFDCC2),
        tertiary: const Color(0xFFFFD27A),
        onTertiary: const Color(0xFF3F2E00),
        tertiaryContainer: const Color(0xFF574000),
        onTertiaryContainer: const Color(0xFFFFEFC9),
        surface: const Color(0xFF1A1412),
        onSurface: const Color(0xFFF2E6E1),
        onSurfaceVariant: const Color(0xFFCDBDB6),
        surfaceContainerLowest: const Color(0xFF140F0D),
        surfaceContainerLow: const Color(0xFF221B19),
        surfaceContainer: const Color(0xFF271F1C),
        surfaceContainerHigh: const Color(0xFF312926),
        surfaceContainerHighest: const Color(0xFF3C3330),
        outline: const Color(0xFF978880),
        outlineVariant: const Color(0xFF433834),
        surfaceTint: Colors.transparent,
      );

  /// Background tints for people without a photo, one per name so a list
  /// of initials does not read as one repeated circle. Light, dark pairs of
  /// (background, foreground); all drawn from the same warm family.
  static const avatarLight = [
    (Color(0xFFFFE2DA), Color(0xFF8A2A1E)),
    (Color(0xFFFFE6D1), Color(0xFF7A3E12)),
    (Color(0xFFFFEDC2), Color(0xFF6B4A00)),
    (Color(0xFFF6E0E8), Color(0xFF7A2E4A)),
    (Color(0xFFE6EBDD), Color(0xFF3F5226)),
    (Color(0xFFE2E7F0), Color(0xFF34476B)),
  ];
  static const avatarDark = [
    (Color(0xFF6E281D), Color(0xFFFFDAD2)),
    (Color(0xFF603617), Color(0xFFFFDCC2)),
    (Color(0xFF574000), Color(0xFFFFEFC9)),
    (Color(0xFF5E2A3D), Color(0xFFFFD9E6)),
    (Color(0xFF34421F), Color(0xFFDCE8C8)),
    (Color(0xFF2C3A55), Color(0xFFD8E2F5)),
  ];
}
