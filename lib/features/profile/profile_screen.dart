import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/birthday_stat.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/profile_repository.dart';
import 'profile_cubit.dart';
import 'profile_state.dart';

/// The profile page (spec §7.3): the signed-in user's own standing in the
/// loop -- the three header counts and the per-year track record below.
///
/// [ProfileRepository], [GraphRepository] and [AuthRepository] are all read
/// off context (all three are registered in `app.dart`), never constructed
/// here.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileCubit(
        context.read<ProfileRepository>(),
        context.read<GraphRepository>(),
        context.read<AuthRepository>(),
        now: _now,
      )..load(),
      child: const ProfileView(),
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
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.profileTitle),
          // '/profile' is reached with context.go, which REPLACES the page
          // stack -- Navigator.canPop() is false here and
          // automaticallyImplyLeading finds nothing to pop, so no back
          // arrow renders without this. Same trap as '/import', '/settings'
          // and '/person/:personId'.
          leading: IconButton(
            key: const Key('profile_back_button'),
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => context.go('/timeline'),
          ),
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
          ProfileLoaded() => _buildLoaded(context, state),
        },
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, ProfileLoaded state) {
    return ListView(
      children: [
        Row(
          children: [
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
            Expanded(
              // Not tappable: M1 has no per-wish list to send this to.
              child: _StatTile(
                key: const Key('profile_wishes_received_tile'),
                label: AppStrings.profileWishesReceived,
                value: state.wishesReceived,
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            AppStrings.profileTrackRecord,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (state.stats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              AppStrings.profileTrackRecordEmpty,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final stat in state.stats) _TrackRecordRow(stat: stat),
        const SizedBox(height: AppSpacing.lg),
      ],
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TrackRecordRow extends StatelessWidget {
  const _TrackRecordRow({required this.stat});

  final BirthdayStat stat;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('profile_stat_${stat.year}'),
      title: Text('${stat.year}'),
      subtitle: Text(
        '${stat.wishesSent} ${AppStrings.profileStatSent} · '
        '${stat.wishesReceived} ${AppStrings.profileStatReceived} · '
        '${stat.birthdaysCelebrated} ${AppStrings.profileStatCelebrated}',
      ),
    );
  }
}
