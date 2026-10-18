import 'package:flutter/material.dart';

import '../models/wish.dart';
import 'app_spacing.dart';
import 'moderation_sheet.dart';
import 'wish_photo.dart';
import 'wish_post_screen.dart';

class WishCard extends StatelessWidget {
  const WishCard({
    super.key,
    required this.wish,
    required this.index,
    required this.unknownAuthor,
    this.canModerate = false,
    this.onModerated,
  });

  final Wish wish;

  /// Position in the grid; picks the card's colour.
  final int index;

  /// Shown when the author is outside the viewer's graph, worded for the
  /// screen it is on.
  final String unknownAuthor;

  /// Offer report/block on the opened post. The caller decides: false for
  /// the viewer's own wish.
  final bool canModerate;

  /// Called after the post was reported or its author blocked, so the wall
  /// can reload without it.
  final ValueChanged<ModerationOutcome>? onModerated;

  Future<void> _open(BuildContext context) async {
    final outcome = await WishPostScreen.open(
      context,
      wish: wish,
      unknownAuthor: unknownAuthor,
      canModerate: canModerate,
    );
    if (outcome != null) onModerated?.call(outcome);
  }

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
          onTap: () => _open(context),
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

    // Tappable too, not only photo posts: the opened post is where the
    // whole text is readable and where report/block lives.
    return Material(
      key: Key('wish_${wish.id}'),
      color: background,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md - AppSpacing.xs),
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
        ),
      ),
    );
  }
}
