import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/initial_avatar.dart';
import '../../repositories/moderation_repository.dart';
import 'blocked_people_cubit.dart';

class BlockedPeopleScreen extends StatelessWidget {
  const BlockedPeopleScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BlockedPeopleScreen()));

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          BlockedPeopleCubit(context.read<ModerationRepository>())..load(),
      child: const BlockedPeopleView(),
    );
  }
}

class BlockedPeopleView extends StatelessWidget {
  const BlockedPeopleView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.blockedTitle)),
      body: BlocConsumer<BlockedPeopleCubit, BlockedPeopleState>(
        listenWhen: (_, next) =>
            next is BlockedPeopleLoaded && next.error != null,
        listener: (context, state) =>
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text((state as BlockedPeopleLoaded).error!)),
            ),
        builder: (context, state) => switch (state) {
          BlockedPeopleLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
          BlockedPeopleError(:final message) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => context.read<BlockedPeopleCubit>().load(),
                  child: const Text(AppStrings.retry),
                ),
              ],
            ),
          ),
          BlockedPeopleLoaded(:final people) when people.isEmpty => Center(
            child: Text(
              AppStrings.blockedEmpty,
              key: const Key('blocked_empty'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          BlockedPeopleLoaded(:final people) => ListView(
            children: [
              for (final p in people)
                ListTile(
                  key: Key('blocked_${p.profileId}'),
                  leading: InitialAvatar(name: p.displayName, radius: 20),
                  title: Text(p.displayName),
                  trailing: OutlinedButton(
                    key: Key('unblock_${p.profileId}'),
                    onPressed: () =>
                        context.read<BlockedPeopleCubit>().unblock(p.profileId),
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
