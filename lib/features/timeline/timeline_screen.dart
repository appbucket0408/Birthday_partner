import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../core/app_links.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
import '../../core/celebrates_you_tag.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../core/profile_avatar.dart';
import '../../models/birthday.dart';
import '../../models/profile.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/graph_repository_impl.dart';
import '../../repositories/push_repository.dart';
import '../../router/session_cubit.dart';
import '../../router/session_state.dart';
import '../push/push_cubit.dart';
import 'timeline_cubit.dart';
import 'timeline_state.dart';

/// Section order: the four [TimelineGroup] values by how soon, then the
/// `null` "no birthday yet" bucket last -- it is not a countdown, so it does
/// not compete with the rows that are.
const _sectionOrder = <TimelineGroup?>[
  TimelineGroup.today,
  TimelineGroup.thisWeek,
  TimelineGroup.thisMonth,
  TimelineGroup.later,
  null,
];

String _headerFor(TimelineGroup? group) => switch (group) {
      TimelineGroup.today => AppStrings.timelineToday,
      TimelineGroup.thisWeek => AppStrings.timelineThisWeek,
      TimelineGroup.thisMonth => AppStrings.timelineThisMonth,
      TimelineGroup.later => AppStrings.timelineLater,
      null => AppStrings.timelineWaitingToJoin,
    };

/// The Celebrating timeline (spec §6.3): the first screen with a real payoff
/// for someone who has added even one contact.
///
/// [repository] and [now] are constructor-injected rather than read off
/// context: GraphRepository has no RepositoryProvider anywhere in this app
/// (Task 10's import screens construct their repository directly for the
/// same reason), and `now` has no production wiring at all -- it exists
/// purely so a test can hand this screen a fixed clock instead of the real
/// one, same reason [TimelineCubit] takes it directly rather than reading
/// `DateTime.now()` itself. [share] is injectable for the same reason: a test
/// cannot open the system share sheet, but can check what would be shared.
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({
    super.key,
    GraphRepository? repository,
    DateTime Function()? now,
    Future<void> Function(String text)? share,
  })  : _repository = repository,
        _now = now,
        _share = share;

  final GraphRepository? _repository;
  final DateTime Function()? _now;
  final Future<void> Function(String text)? _share;

  static Future<void> _systemShare(String text) =>
      SharePlus.instance.share(ShareParams(text: text));

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => TimelineCubit(
            _repository ?? GraphRepositoryImpl(ApiClient.instance),
            now: _now,
          )..load(),
        ),
        // Permission is asked HERE, on arrival at the timeline, and not at
        // launch: Android 13+ treats POST_NOTIFICATIONS as a runtime
        // permission, and prompting on the first cold frame -- before the
        // user knows what the app is -- is the reliable way to be denied
        // permanently. A denial renders nothing: the app works and
        // reminders simply do not arrive.
        // lazy: false is load-bearing. BlocProvider defaults to lazy, and
        // nothing in _TimelineView ever READS PushCubit -- a denial renders
        // nothing by design -- so with the default the cubit is never
        // constructed and enable() never runs. The whole feature would be
        // dead while every test stayed green.
        BlocProvider(
          lazy: false,
          create: (c) => PushCubit(c.read<PushRepository>())..enable(),
        ),
      ],
      child: _TimelineView(share: _share ?? _systemShare),
    );
  }
}

/// The whole screen's layout lives on this one class, inline in [build] --
/// there is nothing here reused elsewhere or complex enough on its own to
/// earn a separate widget. The sole exception is [_SectionHeaderDelegate]
/// below: `SliverPersistentHeader` requires a delegate object, so that much
/// indirection is Flutter's API, not a style choice.
class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.share});

  final Future<void> Function(String text) share;

  static void _addPeople(BuildContext context) {
    HapticFeedback.lightImpact();
    context.go('/import');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.timelineTitle),
        // Always in reach, but quiet: an icon in the same place and weight
        // as the Profile tab's settings icon, so the headers read as one
        // app. The labelled entry point is the row at the top of the list.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: IconButton.filledTonal(
              key: const Key('dashboard_add_people'),
              tooltip: AppStrings.timelineAddPeople,
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () => _addPeople(context),
            ),
          ),
        ],
      ),
      body: BlocConsumer<TimelineCubit, TimelineState>(
        listenWhen: (previous, next) =>
            next is TimelineLoaded && next.error != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((state as TimelineLoaded).error!)),
          );
        },
        builder: (context, state) => switch (state) {
          TimelineLoading() =>
            const Center(child: CircularProgressIndicator()),
          TimelineError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<TimelineCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
          TimelineEmpty() => Column(
              children: [
                const _MeHeader(),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppStrings.timelineEmptyTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            AppStrings.timelineEmptyBody,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.icon(
                            key: const Key('timeline_import_cta'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(200, 48),
                            ),
                            onPressed: () => _addPeople(context),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text(AppStrings.timelineAddPeople),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          TimelineLoaded() => _buildLoaded(context, state),
        },
      ),
    );
  }

  static String _inviteMessage(String name) {
    final first = name.trim().split(RegExp(r'\s+')).first;
    return AppStrings.inviteMessageTemplate
        .replaceFirst('%1', first)
        .replaceFirst('%2', AppLinks.download);
  }

  static Widget? _subtitle(
    int personId,
    Birthday? birthday, {
    required bool celebratesYou,
  }) {
    if (birthday == null && !celebratesYou) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (birthday != null) Text(DateLabels.birthday(birthday)),
        if (celebratesYou) CelebratesYouTag(key: Key('celebrates_you_$personId')),
      ],
    );
  }

  Widget _buildLoaded(BuildContext context, TimelineLoaded state) {
    final cubit = context.read<TimelineCubit>();
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _MeHeader()),
        SliverToBoxAdapter(
          child: _AddPeopleRow(onTap: () => _addPeople(context)),
        ),
        for (final group in _sectionOrder)
          if (state.groups[group] case final rows? when rows.isNotEmpty) ...[
            SliverPersistentHeader(
              delegate: _SectionHeaderDelegate(_headerFor(group)),
            ),
            if (group == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    AppStrings.timelineWaitingToJoinHint,
                    key: const Key('timeline_waiting_hint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final celebration = rows[index];
                  final birthday = celebration.person.birthday;
                  final celebratesYou =
                      state.celebratesMe.contains(celebration.person.id);
                  return ListTile(
                    key: Key('celebration_${celebration.id}'),
                    leading: InitialAvatar(name: celebration.person.displayName),
                    title: Text(celebration.person.displayName),
                    isThreeLine: birthday != null && celebratesYou,
                    subtitle: _subtitle(
                      celebration.person.id,
                      birthday,
                      celebratesYou: celebratesYou,
                    ),
                    onTap: () =>
                        context.go('/person/${celebration.person.id}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!celebration.person.isClaimed)
                          TextButton.icon(
                            key: Key('invite_${celebration.id}'),
                            onPressed: () => share(
                              _inviteMessage(celebration.person.displayName),
                            ),
                            icon: const Icon(Icons.send, size: 18),
                            label: const Text(AppStrings.timelineInvite),
                          ),
                        PopupMenuButton<VoidCallback>(
                          key: Key('menu_${celebration.id}'),
                          onSelected: (action) => action(),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: () =>
                                  cubit.stopCelebrating(celebration.id),
                              child: const Text(
                                AppStrings.timelineStopCelebrating,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                childCount: rows.length,
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }
}
class _MeHeader extends StatelessWidget {
  const _MeHeader();

  @override
  Widget build(BuildContext context) {
    final profile = context.select<SessionCubit, Profile?>(
      (cubit) => switch (cubit.state) {
        SessionReady(:final profile) => profile,
        _ => null,
      },
    );
    if (profile == null) return const SizedBox.shrink();

    final details = [
      '@${profile.handle}',
      if (profile.birthday case final b?) '🎂 ${DateLabels.birthday(b)}',
      if (profile.city case final c? when c.isNotEmpty) c,
    ].join(' · ');

    return Card(
      key: const Key('dashboard_me_header'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ProfileAvatar(
              name: profile.displayName,
              path: profile.avatarPath,
              radius: 26,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    details,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The labelled way in to adding people: a slim row at the top of the list,
/// saying what it does -- the header icon alone would leave a new user
/// guessing. Scrolls away with the list rather than floating over it.
class _AddPeopleRow extends StatelessWidget {
  const _AddPeopleRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      key: const Key('dashboard_add_people_row'),
      onTap: onTap,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: const Icon(Icons.person_add_alt_1, size: 20),
      ),
      title: Text(
        AppStrings.timelineAddPeople,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        AppStrings.timelineAddPeopleHint,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate(this.title);

  final String title;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Text(title, style: AppTextStyles.sectionHeader(context)),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) =>
      oldDelegate.title != title;
}
