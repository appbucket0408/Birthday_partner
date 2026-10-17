import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/celebrates_you_tag.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../models/person.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../router/session_cubit.dart';
import '../../router/session_state.dart';
import 'connections_cubit.dart';
import 'connections_state.dart';

enum ConnectionsTab { iCelebrate, celebrateMe }
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key, required this.initialTab});

  final ConnectionsTab initialTab;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => ConnectionsCubit(
        c.read<GraphRepository>(),
        c.read<ProfileRepository>(),
      )..load(),
      child: ConnectionsView(initialTab: initialTab),
    );
  }
}

/// Split out so a widget test can drive it with its own cubit.
class ConnectionsView extends StatefulWidget {
  const ConnectionsView({super.key, required this.initialTab});

  final ConnectionsTab initialTab;

  @override
  State<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends State<ConnectionsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = context.select<SessionCubit?, String?>(
      (c) => switch (c?.state) {
        SessionReady(:final profile) => '@${profile.handle}',
        _ => null,
      },
    );

    return BlocConsumer<ConnectionsCubit, ConnectionsState>(
      listenWhen: (_, next) => next is ConnectionsLoaded && next.error != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((state as ConnectionsLoaded).error!)),
      ),
      builder: (context, state) {
        final loaded = state is ConnectionsLoaded ? state : null;
        String tabLabel(String name, int? count) =>
            count == null ? name : '$name · $count';

        return DefaultTabController(
          length: 2,
          initialIndex: widget.initialTab.index,
          child: Scaffold(
            appBar: AppBar(
              title: Text(handle ?? AppStrings.profileTitle),
              leading: IconButton(
                key: const Key('connections_back_button'),
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.go('/profile'),
              ),
              bottom: TabBar(
                tabs: [
                  Tab(
                    key: const Key('tab_i_celebrate'),
                    text: tabLabel(
                      AppStrings.profileCelebrating,
                      loaded?.iCelebrate.length,
                    ),
                  ),
                  Tab(
                    key: const Key('tab_celebrate_me'),
                    text: tabLabel(
                      AppStrings.profileCelebrates,
                      loaded?.celebrateMe.length,
                    ),
                  ),
                ],
              ),
            ),
            body: switch (state) {
              ConnectionsLoading() =>
                const Center(child: CircularProgressIndicator()),
              ConnectionsError() => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(state.message),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () =>
                            context.read<ConnectionsCubit>().load(),
                        child: const Text(AppStrings.retry),
                      ),
                    ],
                  ),
                ),
              ConnectionsLoaded() => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: _SearchField(controller: _search),
                    ),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _search,
                        builder: (context, query, _) => TabBarView(
                          children: [
                            _ICelebrateList(state: state, query: query.text),
                            _CelebrateMeList(state: state, query: query.text),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            },
          ),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('connections_search'),
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: AppStrings.connectionsSearch,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(context)
                      .deleteButtonTooltip,
                  onPressed: controller.clear,
                ),
        ),
        filled: true,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

bool _matches(Person p, String query) =>
    p.displayName.toLowerCase().contains(query.trim().toLowerCase());

int _byName(Person a, Person b) =>
    a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

class _ICelebrateList extends StatelessWidget {
  const _ICelebrateList({required this.state, required this.query});

  final ConnectionsLoaded state;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (state.iCelebrate.isEmpty) {
      return _Empty(
        icon: Icons.cake_outlined,
        message: AppStrings.profileCelebratingEmpty,
        action: FilledButton.icon(
          key: const Key('connections_add_people'),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text(AppStrings.timelineAddPeople),
          onPressed: () => context.go('/import'),
        ),
      );
    }
    final people = [
      for (final c in state.iCelebrate)
        if (_matches(c.person, query)) c.person,
    ]..sort(_byName);
    if (people.isEmpty) return _NoMatches(query: query);

    return ListView(
      key: const Key('list_i_celebrate'),
      children: [
        for (final p in people)
          _PersonRow(
            person: p,
            celebratesYou: state.celebratesMe(p.id),
            trailing: _CelebratingButton(
              person: p,
              busy: state.pending.contains(p.id),
              onStop: () =>
                  context.read<ConnectionsCubit>().stopCelebrating(p.id),
            ),
          ),
      ],
    );
  }
}

class _CelebrateMeList extends StatelessWidget {
  const _CelebrateMeList({required this.state, required this.query});

  final ConnectionsLoaded state;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (state.celebrateMe.isEmpty) {
      return const _Empty(
        icon: Icons.favorite_border,
        message: AppStrings.profileCelebratesEmpty,
        hint: AppStrings.connectionsCelebratesEmptyHint,
      );
    }
    // People you can act on (not celebrated back yet) first, then by name.
    final people = [
      for (final p in state.celebrateMe)
        if (_matches(p, query)) p,
    ]..sort((a, b) {
        final back = (state.celebrates(a.id) ? 1 : 0) -
            (state.celebrates(b.id) ? 1 : 0);
        return back != 0 ? back : _byName(a, b);
      });
    if (people.isEmpty) return _NoMatches(query: query);

    return ListView(
      key: const Key('list_celebrate_me'),
      children: [
        for (final p in people)
          _PersonRow(
            person: p,
            celebratesYou: false,
            trailing: state.celebrates(p.id)
                ? _CelebratingButton(
                    person: p,
                    busy: state.pending.contains(p.id),
                    onStop: () => context
                        .read<ConnectionsCubit>()
                        .stopCelebrating(p.id),
                  )
                : _RowButton.filled(
                    key: Key('celebrate_back_${p.id}'),
                    label: AppStrings.celebrateBack,
                    busy: state.pending.contains(p.id),
                    onPressed: () =>
                        context.read<ConnectionsCubit>().celebrateBack(p.id),
                  ),
          ),
      ],
    );
  }
}

/// "🎂 18 March", or "Waiting to join" for someone not on the app.
String _birthdayLine(Person p) {
  final birthday = p.birthday;
  return birthday == null
      ? AppStrings.timelineWaitingToJoin
      : '🎂 ${DateLabels.birthday(birthday)}';
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.celebratesYou,
    required this.trailing,
  });
  final Person person;
  final bool celebratesYou;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('connection_${person.id}'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: InitialAvatar(name: person.displayName, radius: 24),
      title: Text(
        person.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      isThreeLine: celebratesYou,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _birthdayLine(person),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (celebratesYou)
            CelebratesYouTag(key: Key('celebrates_you_${person.id}')),
        ],
      ),
      trailing: trailing,
      onTap: () => context.go('/person/${person.id}'),
    );
  }
}

/// The outlined "Celebrating" button: tapping it asks before stopping, the
/// way Instagram's "Following" asks before unfollowing.
class _CelebratingButton extends StatelessWidget {
  const _CelebratingButton({
    required this.person,
    required this.busy,
    required this.onStop,
  });

  final Person person;
  final bool busy;
  final VoidCallback onStop;

  Future<void> _confirm(BuildContext context) async {
    final stop = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InitialAvatar(name: person.displayName, radius: 32),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.connectionsStopTitleTemplate
                    .replaceFirst('%s', person.displayName),
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.connectionsStopBody,
                textAlign: TextAlign.center,
                style: Theme.of(sheet).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('connections_stop_confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(sheet).colorScheme.error,
                  foregroundColor: Theme.of(sheet).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(sheet).pop(true),
                child: const Text(AppStrings.timelineStopCelebrating),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(sheet).pop(false),
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
        ),
        ),
      ),
    );
    if (stop ?? false) onStop();
  }

  @override
  Widget build(BuildContext context) {
    return _RowButton.outlined(
      key: Key('celebrating_${person.id}'),
      label: AppStrings.celebratingAlready,
      busy: busy,
      onPressed: () => _confirm(context),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton.filled({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  }) : _filled = true;

  const _RowButton.outlined({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  }) : _filled = false;

  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool _filled;

  @override
  Widget build(BuildContext context) {
    const size = Size(136, 36);
    final child = busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1),
            ),
          );
    return _filled
        ? FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: size,
              maximumSize: size,
              padding: EdgeInsets.zero,
            ),
            onPressed: busy ? null : onPressed,
            child: child,
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              maximumSize: size,
              padding: EdgeInsets.zero,
            ),
            onPressed: busy ? null : onPressed,
            child: child,
          );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.message,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        AppStrings.connectionsNoMatchesTemplate.replaceFirst('%s', query.trim()),
        textAlign: TextAlign.center,
      ),
    );
  }
}
