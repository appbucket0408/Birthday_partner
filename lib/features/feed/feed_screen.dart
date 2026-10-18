import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../core/profile_avatar.dart';
import '../../core/wish_photo.dart';
import '../../models/feed_entry.dart';
import '../../models/profile.dart';
import '../../repositories/wish_repository.dart';
import '../../router/active_tab.dart';
import '../../router/home_shell.dart';
import '../../router/session_cubit.dart';
import '../../router/session_state.dart';
import 'feed_cubit.dart';
import 'feed_state.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FeedCubit(context.read<WishRepository>())..load(),
      child: RefreshWhenShown(
        tab: HomeShell.feedTab,
        onShown: (c) => c.read<FeedCubit>().refresh(),
        child: const FeedView(),
      ),
    );
  }
}

/// Split out from [FeedScreen] so a widget test can drive it with its own
/// [FeedCubit], same as `CalendarView`.
class FeedView extends StatelessWidget {
  const FeedView({super.key, this.now = DateTime.now});

  /// For each post's "3h" / "Yesterday".
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.feedTitle)),
      body: BlocConsumer<FeedCubit, FeedState>(
        listenWhen: (previous, next) =>
            next is FeedLoaded && next.error != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((state as FeedLoaded).error!)),
          );
        },
        builder: (context, state) => switch (state) {
          FeedLoading() => const Center(child: CircularProgressIndicator()),
          FeedError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('feed_retry'),
                    onPressed: () => context.read<FeedCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          FeedEmpty() => RefreshIndicator(
              onRefresh: () => context.read<FeedCubit>().refresh(),
              child: const _Empty(),
            ),
          FeedLoaded() => RefreshIndicator(
              onRefresh: () => context.read<FeedCubit>().refresh(),
              child: _List(state: state, now: now()),
            ),
        },
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.state, required this.now});

  final FeedLoaded state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FeedCubit>();
    final me = context.select<SessionCubit, Profile?>(
      (cubit) => switch (cubit.state) {
        SessionReady(:final profile) => profile,
        _ => null,
      },
    );
    final entries = state.entries;
    return ListView.builder(
      key: const Key('feed_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.lg,
      ),
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == entries.length) return _Footer(state: state);
        // Ask for the next page a few posts before the end, so scrolling
        // rarely reaches the spinner. The cubit ignores repeats.
        if (i >= entries.length - 3 && state.hasMore && !state.moreFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => cubit.loadMore());
        }
        return _Post(entry: entries[i], me: me, now: now);
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final FeedLoaded state;

  @override
  Widget build(BuildContext context) {
    if (state.moreFailed) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text(
              AppStrings.feedLoadMoreFailed,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton(
              key: const Key('feed_load_more_retry'),
              onPressed: () => context.read<FeedCubit>().loadMore(),
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      );
    }
    if (state.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }
}

/// One wish as a post card. The person who was wished is the point of it,
/// so their name is bold and in colour, and tapping the header opens them.
/// A photo leads with a short caption under it; a text-only wish is set as
/// a coloured note, the same palette the wish walls use, so it reads as a
/// post rather than a stray line.
class _Post extends StatelessWidget {
  const _Post({required this.entry, required this.me, required this.now});

  final FeedEntry entry;
  final Profile? me;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wish = entry.wish;
    final mine = me != null && wish.authorProfileId == me!.id;
    final author = wish.authorName ?? AppStrings.feedAuthorUnknown;
    final subject = entry.subjectName ?? AppStrings.feedSubjectUnknown;
    final isCake = wish.kind == 'cake';
    final path = wish.photoPath;
    final radius = BorderRadius.circular(AppSpacing.md);

    final header = InkWell(
      onTap: entry.subjectName == null
          ? null
          : () => context.push('/person/${wish.subjectPersonId}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm + 4,
          AppSpacing.sm + 4,
          AppSpacing.sm,
          AppSpacing.sm + 4,
        ),
        child: Row(
          children: [
            if (mine)
              ProfileAvatar(
                name: me!.displayName,
                path: me!.avatarPath,
                radius: 20,
              )
            else
              InitialAvatar(name: author, radius: 20),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: author,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: isCake
                              ? ' ${AppStrings.feedSentCakeTo} '
                              : ' ${AppStrings.feedWished} ',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        TextSpan(
                          text: subject,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateLabels.ago(wish.createdAt, now),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (entry.subjectName != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );

    final Widget content;
    if (path != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: ClipRRect(
              borderRadius: radius,
              child: LayoutBuilder(
                // Tall photos are cut at 4:5, so one post never fills the
                // whole screen.
                builder: (context, constraints) => ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: constraints.maxWidth * 1.25),
                  child: WishPhoto(path: path, fit: BoxFit.fitWidth),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 4,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              wish.body,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
          ),
        ],
      );
    } else {
      final (background, foreground) = switch (wish.id % 3) {
        0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
        1 => (scheme.secondaryContainer, scheme.onSecondaryContainer),
        _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      };
      content = Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 132),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCake) ...[
                Icon(Icons.cake_outlined, size: 40, color: foreground),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                isCake ? AppStrings.feedCakeBody : wish.body,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      key: Key('feed_post_${wish.id}'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md - 4,
      ),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.lg - 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, content],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Scrollable so pull-to-refresh works on the empty screen too.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              key: const Key('feed_empty'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cake_outlined, size: 56, color: scheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppStrings.feedEmptyTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    AppStrings.feedEmptyBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    key: const Key('feed_add_people'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 48),
                    ),
                    onPressed: () => context.go('/import'),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text(AppStrings.timelineAddPeople),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    key: const Key('feed_see_birthdays'),
                    onPressed: () => context.go('/timeline'),
                    child: const Text(AppStrings.feedSeeBirthdays),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
