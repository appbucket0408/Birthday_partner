import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics.dart';
import '../../core/app_links.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/countdown_pill.dart';
import '../../core/date_labels.dart';
import '../../core/photo_picker.dart';
import '../../core/profile_avatar.dart';
import '../../core/wish_card.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/avatar_repository.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../repositories/wish_repository.dart';
import '../../router/active_tab.dart';
import '../../router/home_shell.dart';
import '../../router/session_cubit.dart';
import '../notifications/notification_bell.dart';
import 'profile_cubit.dart';
import 'profile_state.dart';


class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileCubit(
        context.read<ProfileRepository>(),
        context.read<GraphRepository>(),
        context.read<AuthRepository>(),
        context.read<WishRepository>(),
        context.read<AvatarRepository>(),
      )..load(),
      child: RefreshWhenShown(
        tab: HomeShell.profileTab,
        onShown: (c) => c.read<ProfileCubit>().refresh(),
        child: const ProfileView(),
      ),
    );
  }
}
class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    this.share = _systemShare,
    this.now = DateTime.now,
  });

  /// Opens the share sheet for "Invite friends"; injectable because a test
  /// cannot open the real one.
  final Future<void> Function(String text) share;

  /// For the countdown to the user's own birthday.
  final DateTime Function() now;

  static Future<void> _systemShare(String text) =>
      SharePlus.instance.share(ShareParams(text: text));

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileCubit, ProfileState>(
      listenWhen: (_, next) => next is ProfileLoaded && next.error != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((state as ProfileLoaded).error!)),
      ),
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(
            state is ProfileLoaded
                ? '@${state.profile.handle}'
                : AppStrings.profileTitle,
          ),
          actions: [
            const NotificationBell(),
            IconButton(
              key: const Key('settings_button'),
              icon: const Icon(Icons.settings),
              tooltip: AppStrings.settingsTitle,
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
        body: switch (state) {
          ProfileLoading() =>
            const Center(child: CircularProgressIndicator()),
          ProfileError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<ProfileCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          ProfileLoaded() => RefreshIndicator(
              onRefresh: () => context.read<ProfileCubit>().load(),
              child: _buildLoaded(context, state),
            ),
        },
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, ProfileLoaded state) {
    final profile = state.profile;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final birthday = profile.birthday;
    final city = profile.city;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: [
        const SizedBox(height: AppSpacing.md),
        // Avatar and the two relationship counts, Instagram's header shape.
        Row(
          children: [
            _EditablePhoto(state: state),
            Expanded(
              child: _StatTile(
                key: const Key('profile_celebrating_tile'),
                label: AppStrings.profileCelebrating,
                value: state.celebratingCount,
                onTap: () => context.go('/profile/celebrating'),
              ),
            ),
            Expanded(
              child: _StatTile(
                key: const Key('profile_celebrates_tile'),
                label: AppStrings.profileCelebrates,
                value: state.celebratesCount,
                onTap: () => context.go('/profile/celebrates'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          profile.displayName,
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (birthday != null) ...[
              Text(
                '🎂 ${DateLabels.birthday(birthday)}',
                style: theme.textTheme.bodyMedium,
              ),
              CountdownPill(
                key: const Key('profile_countdown'),
                birthday: birthday,
                now: now(),
                compact: true,
              ),
            ],
            if (city != null && city.isNotEmpty)
              Text(
                birthday == null ? city : '· $city',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          key: const Key('profile_wishes_card'),
          margin: EdgeInsets.zero,
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    key: const Key('profile_wishes_received_tile'),
                    label: AppStrings.profileWishesReceived,
                    value: state.wishesReceived,
                    icon: Icons.favorite_outline,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  indent: AppSpacing.md,
                  endIndent: AppSpacing.md,
                  color: scheme.outlineVariant,
                ),
                Expanded(
                  child: _StatTile(
                    key: const Key('profile_wishes_sent_tile'),
                    label: AppStrings.profileWishesSent,
                    value: state.wishesSent,
                    icon: Icons.send_outlined,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Two equal buttons, like Instagram's "Edit profile / Share profile".
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('profile_my_gifts_tile'),
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: const Text(AppStrings.giftListTitle),
                onPressed: () => context.go('/gifts'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('profile_invite_friends'),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text(AppStrings.profileInviteFriends),
                onPressed: () {
                  Analytics.log(
                    AppEvent.inviteSent,
                    {AppParam.source: 'profile'},
                  ).ignore();
                  share(
                    AppStrings.profileInviteMessageTemplate
                        .replaceFirst('%1', profile.handle)
                        .replaceFirst('%2', AppLinks.download),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          state.wall.isEmpty
              ? AppStrings.profileWishWall
              : '${AppStrings.profileWishWall} · ${state.wall.length}',
          key: const Key('profile_wall_title'),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.wall.isEmpty)
          Card(
            key: const Key('profile_wall_empty'),
            margin: EdgeInsets.zero,
            elevation: 0,
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: const Icon(Icons.mail_outline, size: 28),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppStrings.profileWishWallEmptyTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AppStrings.profileWishWallEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          // Two columns, not Instagram's three: these tiles carry text, and
          // at a third of a phone's width a sentence wraps a word per line.
          GridView.count(
            key: const Key('profile_wall'),
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.05,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, w) in state.wall.indexed)
                WishCard(
                  wish: w,
                  index: i,
                  unknownAuthor: AppStrings.profileWishAuthorUnknown,
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// The profile photo; tapping it opens the gallery/camera/remove sheet.
class _EditablePhoto extends StatelessWidget {
  const _EditablePhoto({required this.state});

  final ProfileLoaded state;

  Future<void> _change(BuildContext context) async {
    final cubit = context.read<ProfileCubit>();
    final session = context.read<SessionCubit>();
    final choice = await pickProfilePhoto(
      context,
      canRemove: state.profile.avatarPath != null,
    );
    if (choice == null) return;
    // The Dashboard header reads the session's copy of the profile.
    if (await cubit.changePhoto(choice)) await session.load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: const Key('profile_photo'),
      customBorder: const CircleBorder(),
      onTap: state.savingPhoto ? null : () => _change(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProfileAvatar(
            name: state.profile.displayName,
            path: state.profile.avatarPath,
            radius: 40,
          ),
          if (state.savingPhoto)
            const SizedBox.square(
              dimension: 80,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: scheme.primary,
                child: Icon(Icons.edit, size: 14, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.icon,
  });

  final String label;
  final int value;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                // The number is the strongest text on the page, the way
                // profile counts are everywhere people know them from.
                Text(
                  '$value',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
