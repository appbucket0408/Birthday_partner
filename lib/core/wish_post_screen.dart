import 'package:flutter/material.dart';

import '../models/wish.dart';
import 'app_spacing.dart';
import 'app_strings.dart';
import 'date_labels.dart';
import 'initial_avatar.dart';
import 'wish_photo.dart';


class WishPostScreen extends StatelessWidget {
  const WishPostScreen({
    super.key,
    required this.wish,
    required this.unknownAuthor,
  });

  final Wish wish;
  final String unknownAuthor;

  static Future<void> open(
    BuildContext context, {
    required Wish wish,
    required String unknownAuthor,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              WishPostScreen(wish: wish, unknownAuthor: unknownAuthor),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = wish.authorName ?? unknownAuthor;
    final path = wish.photoPath;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.wishPostTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          key: Key('wish_post_${wish.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 4,
              ),
              child: Row(
                children: [
                  InitialAvatar(name: author, radius: 18),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          DateLabels.posted(wish.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (path != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                ),
                child: WishPhoto(path: path, fit: BoxFit.fitWidth),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: SelectableText(
                wish.body,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
