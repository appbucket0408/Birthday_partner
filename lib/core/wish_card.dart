import 'package:flutter/material.dart';

import '../models/wish.dart';
import 'app_spacing.dart';
import 'wish_photo.dart';
import 'wish_post_screen.dart';

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

    final author = Text(
      wish.authorName ?? unknownAuthor,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelLarge?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    );

    final path = wish.photoPath;
    if (path != null) {
      return Material(
        key: Key('wish_${wish.id}'),
        color: background,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: InkWell(
          onTap: () => WishPostScreen.open(
            context,
            wish: wish,
            unknownAuthor: unknownAuthor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: WishPhoto(path: path)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm + 2,
                  AppSpacing.sm,
                  AppSpacing.sm + 2,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wish.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: foreground),
                    ),
                    author,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
          author,
        ],
      ),
    );
  }
}
