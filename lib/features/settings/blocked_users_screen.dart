import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/initial_avatar.dart';
import '../../repositories/moderation_repository.dart';
import 'blocked_users_cubit.dart';
import 'blocked_users_state.dart';

class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          BlockedUsersCubit(context.read<ModerationRepository>())..load(),
      child: const BlockedUsersView(),
    );
  }
}

/// Split out so a widget test can drive it with its own cubit.
class BlockedUsersView extends StatelessWidget {
  const BlockedUsersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.blockedTitle)),
      body: BlocConsumer<BlockedUsersCubit, BlockedUsersState>(
        listenWhen: (_, next) => next is BlockedUsersLoaded && next.error != null,
        listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((state as BlockedUsersLoaded).error!)),
        ),
        builder: (context, state) => switch (state) {
          BlockedUsersLoading() =>
            const Center(child: CircularProgressIndicator()),
          BlockedUsersError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<BlockedUsersCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          BlockedUsersLoaded(users: []) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  AppStrings.blockedEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          BlockedUsersLoaded() => ListView(
              key: const Key('blocked_list'),
              children: [
                for (final user in state.users)
                  ListTile(
                    key: Key('blocked_${user.profileId}'),
                    leading: InitialAvatar(name: user.displayName, radius: 20),
                    title: Text(user.displayName),
                    trailing: OutlinedButton(
                      key: Key('unblock_${user.profileId}'),
                      onPressed: state.unblocking.contains(user.profileId)
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await context
                                  .read<BlockedUsersCubit>()
                                  .unblock(user.profileId);
                              if (ok) {
                                messenger.showSnackBar(SnackBar(
                                  content: Text(AppStrings.unblockedTemplate
                                      .replaceFirst('%s', user.displayName)),
                                ));
                              }
                            },
                      child: const Text(AppStrings.unblock),
                    ),
                  ),
              ],
            ),
        },
      ),
    );
  }
}
