import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
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

/// The screen's actual content, split out from [ProfileScreen] (not
/// underscore-private) so a widget test can drive it with a mocked
/// [ProfileCubit] via `BlocProvider.value`, the same pattern
/// `test/features/person/person_screen_test.dart` uses for `PersonView`.
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

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
    final textTheme = Theme.of(context).textTheme;
    final details = [
      if (profile.birthday case final b?) '🎂 ${DateLabels.birthday(b)}',
      if (profile.city case final c? when c.isNotEmpty) c,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: [
        const SizedBox(height: AppSpacing.md),
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
        Text(profile.displayName, style: textTheme.titleMedium),
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(details, style: textTheme.bodyMedium),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                key: const Key('profile_wishes_received_tile'),
                label: AppStrings.profileWishesReceived,
                value: state.wishesReceived,
              ),
            ),
            Expanded(
              child: _StatTile(
                key: const Key('profile_wishes_sent_tile'),
                label: AppStrings.profileWishesSent,
                value: state.wishesSent,
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('profile_my_gifts_tile'),
          icon: const Icon(Icons.cake_outlined),
          label: const Text(AppStrings.giftListTitle),
          onPressed: () => context.go('/gifts'),
        ),
        const Divider(height: AppSpacing.xl),
        Text(
          state.wall.isEmpty
              ? AppStrings.profileWishWall
              : '${AppStrings.profileWishWall} · ${state.wall.length}',
          key: const Key('profile_wall_title'),
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.wall.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              AppStrings.profileWishWallEmpty,
              key: const Key('profile_wall_empty'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
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
  });

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
