import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
import '../../core/countdown_pill.dart';
import '../../core/date_labels.dart';
import '../../core/initial_avatar.dart';
import '../../core/wish_card.dart';
import '../../core/wish_post_screen.dart';
import '../../models/wish.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/person_repository.dart';
import '../../repositories/wish_repository.dart';
import '../../router/session_cubit.dart';
import '../../router/session_state.dart';
import '../moderation/moderation_menu.dart';
import 'person_cubit.dart';
import 'person_state.dart';
import 'wish_compose_screen.dart';

class PersonScreen extends StatelessWidget {
  const PersonScreen({
    super.key,
    required this.personId,
    this.openWishId,
    DateTime Function()? now,
  }) : _now = now;

  final int personId;

  /// A wish to open once the wall has loaded -- set when a "new wish"
  /// notification is tapped (`/person/<id>?wish=<id>`).
  final int? openWishId;
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
      child: PersonView(personId: personId, openWishId: openWishId, now: _now),
    );
  }
}

class PersonView extends StatelessWidget {
  const PersonView({
    super.key,
    required this.personId,
    this.openWishId,
    DateTime Function()? now,
  }) : _now = now;

  final int personId;
  final int? openWishId;
  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocListener<PersonCubit, PersonState>(
      listenWhen: (_, current) => _errorOf(current) != null,
      listener: (context, state) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorOf(state)!))),
      child: _buildOpenWishListener(context),
    );
  }

  Widget _buildOpenWishListener(BuildContext context) {
    return BlocListener<PersonCubit, PersonState>(
      // Only on the load that FIRST produces the wall, not on every later
      // PersonLoaded (posting a wish re-emits one). A wish that is no longer
      // there -- deleted since the notification went out -- simply leaves
      // the user on their wall, which is where the notification pointed.
      listenWhen: (previous, current) =>
          openWishId != null &&
          previous is! PersonLoaded &&
          current is PersonLoaded,
      listener: (context, state) {
        final loaded = state as PersonLoaded;
        for (final wish in loaded.wishes) {
          if (wish.id == openWishId) {
            _openWish(context, wish);
            return;
          }
        }
      },
      child: _buildScaffold(context),
    );
  }

  Future<void> _openWish(BuildContext context, Wish wish) async {
    final cubit = context.read<PersonCubit>();
    final changed = await WishPostScreen.open(
      context,
      wish: wish,
      unknownAuthor: AppStrings.wishAuthorUnknown,
      canDelete: _canDelete(context, wish),
    );
    if (changed) cubit.refreshWishes();
  }

  // Only the author here; the wall owner deletes from their own profile.
  static bool _canDelete(BuildContext context, Wish wish) {
    final session = context.read<SessionCubit>().state;
    return session is SessionReady &&
        wish.kind == 'message' &&
        wish.authorProfileId == session.profile.id;
  }

  Widget? _menu(BuildContext context, PersonState state) {
    final session = context.read<SessionCubit>().state;
    final meId = session is SessionReady ? session.profile.id : null;
    return switch (state) {
      PersonLoaded(:final person)
          when person.isClaimed && person.profileId != meId =>
        PersonMenuButton(
          personId: person.id,
          name: person.displayName,
          profileId: person.profileId,
          onBlocked: () =>
              context.canPop() ? context.pop() : context.go('/timeline'),
        ),
      PersonPreview(:final preview) => PersonMenuButton(
        personId: preview.id,
        name: preview.displayName,
      ),
      _ => null,
    };
  }

  Widget _buildScaffold(BuildContext context) {
    return BlocBuilder<PersonCubit, PersonState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const Key('person_back_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/timeline'),
            ),
            actions: [?_menu(context, state)],
          ),
          body: switch (state) {
            PersonLoading() => const Center(child: CircularProgressIndicator()),
            PersonError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => context.read<PersonCubit>().load(personId),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            ),
            PersonLoaded() => _buildLoaded(context, state),
            PersonPreview() => _PreviewCard(state: state),
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
          style: AppTextStyles.sectionHeader(context),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        if (state.wishes.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Text(
              AppStrings.personWallEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
                  canDelete: _canDelete(context, wish),
                  onChanged: context.read<PersonCubit>().refreshWishes,
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
              style: theme.textTheme.headlineSmall,
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Text(
                '🎂 ${DateLabels.birthday(birthday)}',
                key: const Key('person_birthday'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              CountdownPill(
                key: const Key('person_countdown'),
                birthday: birthday,
                now: now(),
              ),
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (state.celebratesViewer) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                key: const Key('person_celebrates_you'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary),
                  borderRadius: BorderRadius.circular(AppSpacing.lg),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 16, color: scheme.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      AppStrings.celebratesYou,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (state.celebratesViewer && !state.viewerCelebrates) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const Key('person_celebrate_back'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: state.celebrating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cake_outlined),
                label: const Text(AppStrings.celebrateBack),
                onPressed: state.celebrating
                    ? null
                    : () => context.read<PersonCubit>().celebrateBack(),
              ),
            ],
            // Both actions need the same thing -- see _canComposeFor:
            // rpc_create_gift (45005) and wishes_insert_own both refuse
            // without a celebration edge and a birthday, so offering either
            // otherwise would lead to an error the user cannot act on.
            //
            // A wish is further limited to the birthday itself: it is the
            // day's message, not a note for any day. A cake is not -- it has
            // to be ordered ahead, so it is offered every day.
            //
            // Stacked, full width: side by side, each label wrapped onto two
            // lines on a normal phone.
            if (canAct) ...[
              const SizedBox(height: AppSpacing.lg),
              if (birthday!.isOn(now()))
                FilledButton.icon(
                  key: const Key('wish_write_button'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.edit),
                  label: const Text(AppStrings.personWriteWish),
                  onPressed: () => openWishComposer(context),
                )
              else
                // Says when wishing opens, in the slot the button will take:
                // one compact bar, icon beside the text, the width of the
                // cake button below -- not a disabled button, nothing to tap.
                Container(
                  key: const Key('wish_opens_on_birthday'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.edit_calendar_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          AppStrings.personWishOpensTemplate.replaceFirst(
                            '%s',
                            DateLabels.birthday(birthday),
                          ),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
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

String? _errorOf(PersonState state) => switch (state) {
  PersonLoaded(:final celebrateError) => celebrateError,
  PersonPreview(:final error) => error,
  _ => null,
};

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.state});

  final PersonPreview state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = state.preview;
    final firstName = preview.displayName.trim().split(' ').first;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      key: const Key('person_preview'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            children: [
              // Same ring as the full page's header, so the two read as one.
              Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: InitialAvatar(name: preview.displayName, radius: 48),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                preview.displayName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (preview.handle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '@${preview.handle}',
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // Shows there is a birthday to unlock without giving it away.
              Center(
                child: Container(
                  key: const Key('person_birthday_locked'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎂'),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        AppStrings.personPreviewBirthdayHidden,
                        style: muted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SocialLine(
                icon: Icons.people_outline,
                color: scheme.onSurfaceVariant,
                text: preview.celebratorCount == 1
                    ? AppStrings.personCelebratorCountOne
                    : AppStrings.personCelebratorCountTemplate.replaceFirst(
                        '%s',
                        '${preview.celebratorCount}',
                      ),
              ),
              if (preview.mutualCount > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                _SocialLine(
                  key: const Key('person_mutuals'),
                  icon: Icons.favorite,
                  color: scheme.primary,
                  text: preview.mutualCount == 1
                      ? AppStrings.personPreviewMutualOne
                      : AppStrings.personPreviewMutualTemplate.replaceFirst(
                          '%s',
                          '${preview.mutualCount}',
                        ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                AppStrings.personPreviewUnlockTemplate.replaceFirst(
                  '%s',
                  firstName,
                ),
                style: AppTextStyles.sectionHeader(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      _Benefit(
                        icon: Icons.cake_outlined,
                        title: AppStrings.personPreviewSeeBirthday,
                        hint: AppStrings.personPreviewSeeBirthdayHint,
                      ),
                      _Benefit(
                        icon: Icons.notifications_active_outlined,
                        title: AppStrings.personPreviewReminders,
                        hint: AppStrings.personPreviewRemindersHint,
                      ),
                      _Benefit(
                        icon: Icons.mail_outline,
                        title: AppStrings.personPreviewWishes,
                        hint: AppStrings.personPreviewWishesHint,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Pinned, so the action stays in thumb reach on any screen size.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  key: const Key('person_celebrate'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: state.celebrating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cake_outlined),
                  label: Text(
                    AppStrings.personPreviewCelebrateTemplate.replaceFirst(
                      '%s',
                      firstName,
                    ),
                  ),
                  onPressed: state.celebrating
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          context.read<PersonCubit>().celebrate();
                        },
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppStrings.personPreviewFooter,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SocialLine extends StatelessWidget {
  const _SocialLine({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.hint});

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: scheme.primaryContainer,
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
