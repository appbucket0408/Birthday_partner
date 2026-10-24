import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../models/report_reason.dart';
import '../../models/wish.dart';
import '../../repositories/moderation_repository.dart';
import '../../router/session_cubit.dart';
import '../../router/session_state.dart';

enum _Action { report, block, delete }

/// The ⋮ on a wish: report and block for others' wishes, delete when allowed.
class WishMenuButton extends StatelessWidget {
  const WishMenuButton({
    super.key,
    required this.wish,
    required this.canDelete,
    this.onDeleted,
    this.onBlocked,
  });

  final Wish wish;
  final bool canDelete;
  final VoidCallback? onDeleted;
  final ValueChanged<String>? onBlocked;

  @override
  Widget build(BuildContext context) {
    final meId = context.select<SessionCubit, String?>(
      (c) => switch (c.state) {
        SessionReady(:final profile) => profile.id,
        _ => null,
      },
    );
    final mine = wish.authorProfileId == meId;
    final name = wish.authorName ?? AppStrings.blockSomeone;
    final actions = [
      if (!mine) _Action.report,
      if (!mine) _Action.block,
      if (canDelete) _Action.delete,
    ];
    if (actions.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<_Action>(
      key: Key('wish_menu_${wish.id}'),
      tooltip: AppStrings.moreOptions,
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem(
            key: Key('wish_menu_${a.name}'),
            value: a,
            child: Text(switch (a) {
              _Action.report => AppStrings.reportWish,
              _Action.block => AppStrings.blockNamed.replaceFirst('%1', name),
              _Action.delete => AppStrings.wishDelete,
            }),
          ),
      ],
      onSelected: (a) async {
        final repo = context.read<ModerationRepository>();
        switch (a) {
          case _Action.report:
            final reason = await pickReportReason(context);
            if (reason == null || !context.mounted) return;
            await runReport(context, () => repo.reportWish(wish.id, reason));
          case _Action.block:
            if (!await confirmBlock(context, name) || !context.mounted) return;
            final ok = await runModeration(
              context,
              () => repo.block(wish.authorProfileId),
              done: AppStrings.blockDone.replaceFirst('%1', name),
              failed: AppStrings.blockFailed,
            );
            if (ok) onBlocked?.call(wish.authorProfileId);
          case _Action.delete:
            if (!await _confirmDelete(context) || !context.mounted) return;
            final ok = await runModeration(
              context,
              () => repo.deleteWish(wish.id),
              done: AppStrings.wishDeleted,
              failed: AppStrings.wishDeleteFailed,
            );
            if (ok) onDeleted?.call();
        }
      },
    );
  }
}

/// The ⋮ on a person's page. Block needs [profileId]; a preview has none.
class PersonMenuButton extends StatelessWidget {
  const PersonMenuButton({
    super.key,
    required this.personId,
    required this.name,
    this.profileId,
    this.onBlocked,
  });

  final int personId;
  final String name;
  final String? profileId;
  final VoidCallback? onBlocked;

  @override
  Widget build(BuildContext context) {
    final blockable = profileId;
    return PopupMenuButton<_Action>(
      key: const Key('person_menu'),
      tooltip: AppStrings.moreOptions,
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => [
        const PopupMenuItem(
          key: Key('person_menu_report'),
          value: _Action.report,
          child: Text(AppStrings.reportPerson),
        ),
        if (blockable != null)
          PopupMenuItem(
            key: const Key('person_menu_block'),
            value: _Action.block,
            child: Text(AppStrings.blockNamed.replaceFirst('%1', name)),
          ),
      ],
      onSelected: (a) async {
        final repo = context.read<ModerationRepository>();
        if (a == _Action.report) {
          final reason = await pickReportReason(context);
          if (reason == null || !context.mounted) return;
          await runReport(context, () => repo.reportPerson(personId, reason));
        } else if (blockable != null) {
          if (!await confirmBlock(context, name) || !context.mounted) return;
          final ok = await runModeration(
            context,
            () => repo.block(blockable),
            done: AppStrings.blockDone.replaceFirst('%1', name),
            failed: AppStrings.blockFailed,
          );
          if (ok) onBlocked?.call();
        }
      },
    );
  }
}

Future<ReportReason?> pickReportReason(BuildContext context) =>
    showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  AppStrings.reportTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final r in ReportReason.values)
                ListTile(
                  key: Key('report_reason_${r.value}'),
                  title: Text(r.label),
                  onTap: () => Navigator.of(sheetContext).pop(r),
                ),
            ],
          ),
        ),
      ),
    );

Future<bool> confirmBlock(BuildContext context, String name) => _confirm(
  context,
  title: AppStrings.blockTitle.replaceFirst('%1', name),
  body: AppStrings.blockBody,
  confirm: AppStrings.blockAction,
  confirmKey: const Key('block_confirm_button'),
);

Future<bool> _confirmDelete(BuildContext context) => _confirm(
  context,
  title: AppStrings.wishDeleteTitle,
  body: AppStrings.wishDeleteBody,
  confirm: AppStrings.wishDeleteConfirm,
  confirmKey: const Key('wish_delete_confirm_button'),
);

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required Key confirmKey,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: confirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirm),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

Future<void> runReport(BuildContext context, Future<void> Function() send) =>
    runModeration(
      context,
      send,
      done: AppStrings.reportSent,
      failed: AppStrings.reportFailed,
      failedFor: (f) => f is ServerFailure && f.code == '45009'
          ? AppStrings.reportDailyLimit
          : null,
    );

/// Runs [action] and reports the outcome in a snackbar; true on success.
Future<bool> runModeration(
  BuildContext context,
  Future<void> Function() action, {
  required String done,
  required String failed,
  String? Function(AppFailure)? failedFor,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  String message;
  var ok = false;
  try {
    await action();
    message = done;
    ok = true;
  } on AppFailure catch (f) {
    message = failedFor?.call(f) ?? failed;
  } catch (_) {
    message = failed;
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
  return ok;
}
