import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/report_reason.dart';
import '../models/wish.dart';
import '../repositories/moderation_repository.dart';
import 'app_spacing.dart';
import 'app_strings.dart';
import 'initial_avatar.dart';
import 'result.dart';

/// What a report/block flow ended in, so the screen that opened it knows to
/// reload: the post (or everything by that person) is gone from its view.
enum ModerationOutcome { reported, blocked }

/// The "..." menu on someone else's post: report the post, or block its
/// author. Returns null when the user backs out at any step.
Future<ModerationOutcome?> showWishModeration(
  BuildContext context, {
  required Wish wish,
  required String authorName,
}) async {
  final choice = await _pickAction(
    context,
    reportLabel: AppStrings.reportPost,
    blockLabel: AppStrings.blockUserTemplate.replaceFirst('%s', authorName),
  );
  if (choice == null || !context.mounted) return null;

  final repo = context.read<ModerationRepository>();
  return switch (choice) {
    _Action.report => _report(
        context,
        send: (reason) => repo.reportWish(wish.id, reason),
        done: AppStrings.reportedPost,
      ),
    _Action.block => _block(
        context,
        name: authorName,
        send: () => repo.block(wish.authorProfileId),
      ),
  };
}

/// The overflow menu on a member's person page: report them, or block them.
Future<ModerationOutcome?> showPersonModeration(
  BuildContext context, {
  required String profileId,
  required String name,
}) async {
  final choice = await _pickAction(
    context,
    reportLabel: AppStrings.reportUserTemplate.replaceFirst('%s', name),
    blockLabel: AppStrings.blockUserTemplate.replaceFirst('%s', name),
  );
  if (choice == null || !context.mounted) return null;

  final repo = context.read<ModerationRepository>();
  return switch (choice) {
    _Action.report => _report(
        context,
        send: (reason) => repo.reportUser(profileId, reason),
        done: AppStrings.reportedUser,
      ),
    _Action.block => _block(
        context,
        name: name,
        send: () => repo.block(profileId),
      ),
  };
}

enum _Action { report, block }

Future<_Action?> _pickAction(
  BuildContext context, {
  required String reportLabel,
  required String blockLabel,
}) {
  return showModalBottomSheet<_Action>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final error = Theme.of(sheet).colorScheme.error;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('moderation_report'),
              leading: Icon(Icons.flag_outlined, color: error),
              title: Text(reportLabel, style: TextStyle(color: error)),
              onTap: () => Navigator.of(sheet).pop(_Action.report),
            ),
            ListTile(
              key: const Key('moderation_block'),
              leading: Icon(Icons.block, color: error),
              title: Text(blockLabel, style: TextStyle(color: error)),
              onTap: () => Navigator.of(sheet).pop(_Action.block),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    },
  );
}

Future<ModerationOutcome?> _report(
  BuildContext context, {
  required Future<void> Function(ReportReason) send,
  required String done,
}) async {
  final reason = await showModalBottomSheet<ReportReason>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                AppStrings.reportWhyTitle,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (final r in ReportReason.values)
              ListTile(
                key: Key('report_reason_${r.wire}'),
                title: Text(r.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheet).pop(r),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    ),
  );
  if (reason == null || !context.mounted) return null;

  final ok = await _run(context, () => send(reason), done);
  return ok ? ModerationOutcome.reported : null;
}

Future<ModerationOutcome?> _block(
  BuildContext context, {
  required String name,
  required Future<void> Function() send,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InitialAvatar(name: name, radius: 32),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.blockTitleTemplate.replaceFirst('%s', name),
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.blockBody,
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('moderation_block_confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(sheet).colorScheme.error,
                  foregroundColor: Theme.of(sheet).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(sheet).pop(true),
                child: const Text(AppStrings.blockConfirm),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(sheet).pop(false),
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  final ok = await _run(
    context,
    send,
    AppStrings.blockedTemplate.replaceFirst('%s', name),
  );
  return ok ? ModerationOutcome.blocked : null;
}

/// Runs the write and says how it went in a snackbar. The messenger is
/// captured before the await: by the time a block lands, the screen that
/// asked may already be closing.
Future<bool> _run(
  BuildContext context,
  Future<void> Function() send,
  String done,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await send();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on AppFailure catch (f) {
    messenger.showSnackBar(SnackBar(content: Text(f.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.somethingWentWrong)),
    );
  }
  return false;
}
