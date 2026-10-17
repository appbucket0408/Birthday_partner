import 'package:flutter/material.dart';

import '../models/wish.dart';
import 'app_spacing.dart';

/// One wish as a coloured card: the message, and who sent it underneath.
/// Used by every wish grid (your profile, and another person's page) so they
/// always look the same. Cards cycle through the theme's three container
/// colours so a grid of them reads as separate notes rather than one block.
class WishCard extends StatelessWidget {
  const WishCard({
    super.key,
    required this.wish,
    required this.index,
    required this.unknownAuthor,
  });

  final Wish wish;

  /// Position in the grid; picks the card's colour.
  final int index;

  /// Shown when the author is outside the viewer's graph, worded for the
  /// screen it is on.
  final String unknownAuthor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (index % 3) {
      0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      1 => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };

    return Container(
      key: Key('wish_${wish.id}'),
      padding: const EdgeInsets.all(AppSpacing.md - AppSpacing.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              wish.body,
              overflow: TextOverflow.fade,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            wish.authorName ?? unknownAuthor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
