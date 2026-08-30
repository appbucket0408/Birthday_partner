import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
import '../../models/birthday.dart';
import '../../models/celebration.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/graph_repository_impl.dart';
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
      null => AppStrings.timelineNoBirthdayYet,
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
/// `DateTime.now()` itself.
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({
    super.key,
    GraphRepository? repository,
    DateTime Function()? now,
  })  : _repository = repository,
        _now = now;

  final GraphRepository? _repository;
  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TimelineCubit(
        _repository ?? GraphRepositoryImpl(ApiClient.instance),
        now: _now,
      )..load(),
      child: const _TimelineView(),
    );
  }
}

/// The whole screen's layout lives on this one class, inline in [build] --
/// there is nothing here reused elsewhere or complex enough on its own to
/// earn a separate widget. The sole exception is [_SectionHeaderDelegate]
/// below: `SliverPersistentHeader` requires a delegate object, so that much
/// indirection is Flutter's API, not a style choice.
class _TimelineView extends StatelessWidget {
  const _TimelineView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.timelineTitle),
        actions: [
          IconButton(
            key: const Key('profile_button'),
            icon: const Icon(Icons.person),
            tooltip: AppStrings.profileTitle,
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            key: const Key('settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: AppStrings.settingsTitle,
            onPressed: () => context.go('/settings'),
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
          TimelineEmpty() => Center(
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
          TimelineLoaded() => _buildLoaded(context, state),
        },
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, TimelineLoaded state) {
    final cubit = context.read<TimelineCubit>();
    return CustomScrollView(
      slivers: [
        for (final group in _sectionOrder)
          if (state.groups[group] case final rows? when rows.isNotEmpty) ...[
            SliverPersistentHeader(
              delegate: _SectionHeaderDelegate(_headerFor(group)),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final celebration = rows[index];
                  return ListTile(
                    key: Key('celebration_${celebration.id}'),
                    title: Text(celebration.label),
                    onTap: () =>
                        context.go('/person/${celebration.person.id}'),
                    trailing: PopupMenuButton<VoidCallback>(
                      key: Key('menu_${celebration.id}'),
                      onSelected: (action) => action(),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: () =>
                              _pickBirthday(context, cubit, celebration),
                          child: const Text(AppStrings.timelineEditBirthday),
                        ),
                        PopupMenuItem(
                          value: () =>
                              _editNickname(context, cubit, celebration),
                          child: const Text(AppStrings.timelineEditNickname),
                        ),
                        PopupMenuItem(
                          value: () => cubit.stopCelebrating(celebration.id),
                          child:
                              const Text(AppStrings.timelineStopCelebrating),
                        ),
                      ],
                    ),
                  );
                },
                childCount: rows.length,
              ),
            ),
          ],
      ],
    );
  }

  Future<void> _pickBirthday(
    BuildContext context,
    TimelineCubit cubit,
    Celebration celebration,
  ) async {
    final existing = celebration.person.birthday;
    final seed = existing == null
        ? DateTime(2000, 1, 1)
        : DateTime(existing.year ?? 2000, existing.month, existing.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await cubit.editBirthday(
      celebration.person.id,
      Birthday(month: picked.month, day: picked.day, year: picked.year),
    );
  }

  Future<void> _editNickname(
    BuildContext context,
    TimelineCubit cubit,
    Celebration celebration,
  ) async {
    final controller = TextEditingController(text: celebration.nickname ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.timelineEditNickname),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text(AppStrings.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final trimmed = result.trim();
    await cubit.editNickname(celebration.id, trimmed.isEmpty ? null : trimmed);
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
