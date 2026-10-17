import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../core/app_links.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
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
class _TimelineView extends StatefulWidget {
  const _TimelineView({required this.share});

  final Future<void> Function(String text) share;

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  // The add button shows its label until the user scrolls down the list, so
  // it never sits over a name for long, and comes back on the way up.
  bool _fabExtended = true;

  bool _onScroll(UserScrollNotification n) {
    final extended = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabExtended,
    };
    if (extended != _fabExtended) setState(() => _fabExtended = extended);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Profile and Settings used to be AppBar actions here. Profile is now a
      // bottom-bar tab, and Settings moved onto it.
      appBar: AppBar(title: const Text(AppStrings.timelineTitle)),
      // Adding people is this screen's primary action, so it is always on
      // screen -- not only in the empty state, which a user who already
      // celebrates anyone never sees again.
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('dashboard_add_people'),
        onPressed: () => context.go('/import'),
        isExtended: _fabExtended,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text(AppStrings.timelineAddPeople),
        tooltip: AppStrings.timelineAddPeople,
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: BlocConsumer<TimelineCubit, TimelineState>(
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
                            FilledButton(
                              key: const Key('timeline_import_cta'),
                              onPressed: () => context.go('/import'),
                              child: const Text(AppStrings.timelineImportCta),
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
      ),
    );
  }

  /// Addressed by first name -- it reads as a message from a friend, not a
  /// notification from an app.
  static String _inviteMessage(String name) {
    final first = name.trim().split(RegExp(r'\s+')).first;
    return AppStrings.inviteMessageTemplate
        .replaceFirst('%1', first)
        .replaceFirst('%2', AppLinks.download);
  }

  /// "18 March", "18 March · Celebrates you", or null when there is
  /// neither -- someone not on the app cannot celebrate anyone yet.
  static Widget? _subtitle(Birthday? birthday, {required bool celebratesYou}) {
    final parts = [
      if (birthday != null) DateLabels.birthday(birthday),
      if (celebratesYou) AppStrings.celebratesYou,
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }

  Widget _buildLoaded(BuildContext context, TimelineLoaded state) {
    final cubit = context.read<TimelineCubit>();
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _MeHeader()),
        for (final group in _sectionOrder)
          if (state.groups[group] case final rows? when rows.isNotEmpty) ...[
            SliverPersistentHeader(
              delegate: _SectionHeaderDelegate(_headerFor(group)),
            ),
            // Only people not on the app have no birthday (only a person sets
            // their own), so this section is "waiting to join" -- said here,
            // where its rows would otherwise look like missing data.
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
                  return ListTile(
                    key: Key('celebration_${celebration.id}'),
                    leading: InitialAvatar(name: celebration.person.displayName),
                    title: Text(celebration.person.displayName),
                    subtitle: _subtitle(
                      birthday,
                      celebratesYou: state.celebratesMe
                          .contains(celebration.person.id),
                    ),
                    onTap: () =>
                        context.go('/person/${celebration.person.id}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!celebration.person.isClaimed)
                          TextButton.icon(
                            key: Key('invite_${celebration.id}'),
                            onPressed: () => widget.share(
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
        // Room under the last row for the floating add button, so it never
        // covers that row's menu.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

/// The signed-in user's own card at the top of the Dashboard: avatar, name,
/// handle, birthday and city. Read from the session, which already holds the
/// profile -- the router only shows this screen once the session is
/// [SessionReady], so no second fetch is needed.
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
