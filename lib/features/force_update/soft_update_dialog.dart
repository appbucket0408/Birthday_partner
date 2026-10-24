import 'package:flutter/material.dart';

import '../../core/app_strings.dart';

/// The optional-update prompt. Completes true for "Update", false for
/// "Later" -- and false for a tap outside, which reads as "not now" too.
Future<bool> showSoftUpdateDialog(BuildContext context) async {
  final update = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.celebration_outlined),
      title: const Text(AppStrings.softUpdateTitle),
      content: const Text(AppStrings.softUpdateBody),
      actions: [
        TextButton(
          key: const Key('soft_update_later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.softUpdateLater),
        ),
        FilledButton(
          key: const Key('soft_update_button'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AppStrings.softUpdateAction),
        ),
      ],
    ),
  );
  return update ?? false;
}
