import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../core/wish_card.dart';
import '../../models/birthday.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/person_repository.dart';
import '../../repositories/wish_repository.dart';
import 'person_cubit.dart';
import 'person_state.dart';
import 'wish_compose_sheet.dart';

/// The person page (spec §7.1): name, birthday, celebrator count and the
/// wish wall, reached by tapping a timeline row.
///
/// [PersonRepository], [WishRepository] and [GraphRepository] are all read
/// off context -- all three are registered in `app.dart` -- never
/// constructed here. `TimelineScreen`'s own `?? GraphRepositoryImpl(...)`
/// fallback predates `GraphRepository`'s `RepositoryProvider` (added in
/// Task 8's Step 3b) and is left as-is; migrating it is a Phase 2b refactor,
/// out of scope here.
class PersonScreen extends StatelessWidget {
  const PersonScreen({
    super.key,
    required this.personId,
    DateTime Function()? now,
  }) : _now = now;

  final int personId;
  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PersonCubit(
        context.read<PersonRepository>(),
        context.read<WishRepository>(),
        context.read<GraphRepository>(),
        now: _now,
      )..load(personId),
      child: PersonView(personId: personId, now: _now),
    );
  }
}

/// The screen's actual content, split out from [PersonScreen] (not
/// underscore-private, unlike `_TimelineView`/`_SettingsView`) so a widget
/// test can drive it with a mocked [PersonCubit] via `BlocProvider.value`,
/// without needing a live [PersonRepository]/[WishRepository] session --
/// the same reason `OtpScreen` expects an already-provided `PhoneCubit`
/// rather than building its own.
class PersonView extends StatelessWidget {
  const PersonView({
    super.key,
    required this.personId,
    DateTime Function()? now,
  }) : _now = now;

  final int personId;
  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PersonCubit, PersonState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            // '/person/:personId' is reached with context.go, which REPLACES
            // the page stack -- Navigator.canPop() is false here and
            // automaticallyImplyLeading finds nothing to pop, so no back
            // arrow renders without this. This trap has now bitten this
            // project three times: '/import', '/settings', and this screen.
            leading: IconButton(
              key: const Key('person_back_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => context.go('/timeline'),
            ),
          ),
          body: switch (state) {
            PersonLoading() =>
              const Center(child: CircularProgressIndicator()),
            PersonError() => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () =>
                          context.read<PersonCubit>().load(personId),
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                ),
              ),
            PersonLoaded() => _buildLoaded(context, state),
          },
        );
      },
    );
  }

  Widget _buildLoaded(BuildContext context, PersonLoaded state) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _Header(state: state, now: _now ?? DateTime.now),
        const SizedBox(height: AppSpacing.lg),
        Text(
          state.wishes.isEmpty
              ? AppStrings.personWishesTitle
              : '${AppStrings.personWishesTitle} · ${state.wishes.length}',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.wishes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              AppStrings.personWallEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.05,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, wish) in state.wishes.indexed)
                WishCard(
                  wish: wish,
                  index: i,
                  unknownAuthor: AppStrings.wishAuthorUnknown,
                ),
            ],
          ),
      ],
    );
  }
}

/// The person at a glance: avatar, name, birthday with a countdown, how many
/// people celebrate them, and the two things you can do for them.
class _Header extends StatelessWidget {
  const _Header({required this.state, required this.now});

  final PersonLoaded state;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final person = state.person;
    final birthday = person.birthday;
    final canAct = _canComposeFor(state);

    return Card(
      key: const Key('person_header'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // A ring in the theme's primary colour: the avatar and the card
            // share a tint, and without it the avatar dissolves into it.
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.primary, width: 2),
              ),
              child: InitialAvatar(name: person.displayName, radius: 40),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              person.displayName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (birthday == null) ...[
              Text(
                AppStrings.personNoBirthday,
                key: const Key('person_birthday'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.personNoBirthdayHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ] else ...[
              Text(
                '🎂 ${DateLabels.birthday(birthday)}',
                key: const Key('person_birthday'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              _CountdownPill(birthday: birthday, now: now()),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              key: const Key('person_celebrator_count'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  state.celebratorCount == 1
                      ? AppStrings.personCelebratorCountOne
                      : AppStrings.personCelebratorCountTemplate.replaceFirst(
                          '%s',
                          '${state.celebratorCount}',
                        ),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            // Both actions appear under the same condition -- see
            // _canComposeFor. rpc_create_gift (45005) and wishes_insert_own
            // both refuse without a celebration edge and a birthday, so
            // offering either otherwise would lead to an error the user
            // cannot act on.
            // Stacked, full width: side by side, each label wrapped onto two
            // lines on a normal phone.
            if (canAct) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const Key('wish_write_button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.edit),
                label: const Text(AppStrings.personWriteWish),
                onPressed: () => showWishComposeSheet(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonalIcon(
                key: const Key('gift_send_cake_button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.cake_outlined),
                label: const Text(AppStrings.giftSendCake),
                onPressed: () => context.go('/gift/new/${person.id}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How far off the birthday is, as a pill: "in 10 days", "Tomorrow", or --
/// on the day -- a bold "🎉 Birthday today!" in the primary colour, since
/// that is the moment the page exists for. Counted with the same
/// next-occurrence rule (Feb 29 included) as the Dashboard's grouping.
class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.birthday, required this.now});

  final Birthday birthday;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime(now.year, now.month, now.day);
    final days = birthday.nextOccurrence(now).difference(today).inDays;
    final (label, background, foreground) = switch (days) {
      0 => (AppStrings.personToday, scheme.primary, scheme.onPrimary),
      1 => (
          AppStrings.personTomorrow,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      _ => (
          AppStrings.personInDaysTemplate.replaceFirst('%s', '$days'),
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
    };
    return Container(
      key: const Key('person_countdown'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: days == 0 ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

/// The wish and cake buttons are shown only when there is something the user
/// could actually do with them, and only when the write would not be
/// pointlessly refused: the person has a birthday to derive an occasion year from
/// ([PersonCubit.postWish]), AND [PersonLoaded.viewerCelebrates] -- the
/// signal that the viewer's own `celebrations()` list contains this person,
/// which is the only client-visible stand-in for `wishes_insert_own`'s RLS
/// requirement (`private.can_see_person`'s three branches are otherwise
/// indistinguishable from here). Hidden, not disabled -- there is nothing on
/// this screen a user could do to enable it, so a disabled button would only
/// invite hunting for a reason that isn't shown anywhere.
///
/// The write is still enforced server-side regardless of this check, for
/// the race where the viewer un-celebrates mid-compose -- see
/// [PersonCubit.postWish]'s `postError` handling.
bool _canComposeFor(PersonLoaded state) =>
    state.person.birthday != null && state.viewerCelebrates;
