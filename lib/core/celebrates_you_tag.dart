import 'package:flutter/material.dart';

import '../core/app_spacing.dart';
import '../core/app_strings.dart';

class CelebratesYouTag extends StatelessWidget {
  const CelebratesYouTag({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, size: 12, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              AppStrings.celebratesYou,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
