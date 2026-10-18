import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../models/app_notification.dart';
import '../../repositories/notification_repository.dart';
import '../push/notifications_off_banner.dart';
import 'notification_badge_cubit.dart';
import 'notifications_cubit.dart';
import 'notifications_state.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) =>
          NotificationsCubit(c.read<NotificationRepository>())..load(),
      child: const NotificationsView(),
    );
  }
}

/// Split out from [NotificationsScreen] so a widget test can drive it with
/// its own cubit, same as FeedView.
class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key, this.now = DateTime.now});

  /// For each row's "3h" / "Yesterday".
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.notificationsTitle)),
      body: BlocConsumer<NotificationsCubit, NotificationsState>(
        // Opening the list marks everything seen (NotificationsCubit.load),
        // so the bell clears as soon as the first page is on screen.
        listenWhen: (previous, current) =>
            previous is NotificationsLoading &&
            (current is NotificationsLoaded || current is NotificationsEmpty),
        listener: (context, _) {
          try {
            context.read<NotificationBadgeCubit>().clear();
          } on ProviderNotFoundException {
            // Pumped on its own in a widget test; nothing to clear.
          }
        },
        builder: (context, state) => switch (state) {
          NotificationsLoading() =>
            const Center(child: CircularProgressIndicator()),
          NotificationsError() => _Message(
              message: state.message,
              action: FilledButton(
                key: const Key('notifications_retry'),
                onPressed: () => context.read<NotificationsCubit>().load(),
                child: const Text(AppStrings.retry),
              ),
            ),
          NotificationsEmpty() => const _Empty(),
          NotificationsLoaded() => _List(state: state, now: now()),
        },
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.state, required this.now});

  final NotificationsLoaded state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NotificationsCubit>();
    final items = state.items;
    return ListView.builder(
      key: const Key('notifications_list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      // The banner, then the rows, then a footer.
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return const NotificationsOffBanner();
        if (i == items.length + 1) return _Footer(state: state);
        final index = i - 1;
        // Ask for the next page a few rows before the end, as the feed does.
        if (index >= items.length - 3 && state.hasMore && !state.moreFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => cubit.loadMore());
        }
        return _Row(item: items[index], now: now);
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.now});

  final AppNotification item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final route = item.route;
    final unseen = !item.seen;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        key: Key('notification_${item.id}'),
        // New since the last visit: tinted, with a dot.
        color: unseen
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: unseen
                ? scheme.primary.withValues(alpha: 0.2)
                : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: route == null ? null : () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md - 2),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InitialAvatar(name: item.displayName, radius: 22),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.kind == AppNotificationKind.wish
                              ? Icons.chat_bubble
                              : Icons.cake,
                          size: 14,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: unseen ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateLabels.ago(item.createdAt, now),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (unseen)
                  Container(
                    key: Key('notification_unseen_${item.id}'),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final NotificationsLoaded state;

  @override
  Widget build(BuildContext context) {
    if (state.moreFailed) {
      return Center(
        child: TextButton(
          key: const Key('notifications_load_more_retry'),
          onPressed: () => context.read<NotificationsCubit>().loadMore(),
          child: const Text(AppStrings.retry),
        ),
      );
    }
    if (state.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: AppSpacing.md);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const NotificationsOffBanner(),
        const SizedBox(height: AppSpacing.xl),
        Center(
          key: const Key('notifications_empty'),
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none,
              size: 40,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          AppStrings.notificationsEmptyTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppStrings.notificationsEmptyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.action});

  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              action,
            ],
          ),
        ),
      );
}
