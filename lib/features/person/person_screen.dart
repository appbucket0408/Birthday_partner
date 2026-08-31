import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
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
      child: PersonView(personId: personId),
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
  const PersonView({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PersonCubit, PersonState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(state is PersonLoaded ? state.person.displayName : ''),
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
          floatingActionButton: state is PersonLoaded && _canComposeFor(state)
              ? FloatingActionButton.extended(
                  key: const Key('wish_write_button'),
                  icon: const Icon(Icons.edit),
                  label: const Text(AppStrings.personWriteWish),
                  onPressed: () => showWishComposeSheet(context),
                )
              : null,
        );
      },
    );
  }

  Widget _buildLoaded(BuildContext context, PersonLoaded state) {
    final person = state.person;
    return ListView(
      children: [
        ListTile(
          key: const Key('person_birthday'),
          title: Text(
            person.birthday == null
                ? AppStrings.personNoBirthday
                : _formatBirthday(person.birthday!.month, person.birthday!.day),
          ),
        ),
        ListTile(
          key: const Key('person_celebrator_count'),
          title: Text(
            state.celebratorCount == 1
                ? AppStrings.personCelebratorCountOne
                : AppStrings.personCelebratorCountTemplate.replaceFirst(
                    '%s',
                    '${state.celebratorCount}',
                  ),
          ),
        ),
        if (_canComposeFor(state))
          // Shown under the SAME condition as the compose FAB -- reusing
          // _canComposeFor rather than restating it, per task-5-brief.md.
          // The RPC (rpc_create_gift, via 45005) refuses without a
          // celebration edge to the recipient, so offering this action when
          // the viewer does not celebrate them would lead to an error the
          // user cannot act on.
          ListTile(
            key: const Key('gift_send_cake_button'),
            leading: const Icon(Icons.cake_outlined),
            title: const Text(AppStrings.giftSendCake),
            onTap: () => context.go('/gift/new/${person.id}'),
          ),
        const Divider(height: 1),
        if (state.wishes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              AppStrings.personWallEmpty,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final wish in state.wishes)
            ListTile(
              key: Key('wish_${wish.id}'),
              title: Text(wish.body),
              subtitle: Text(
                '${wish.authorName ?? AppStrings.wishAuthorUnknown} · '
                '${wish.occasionYear}',
              ),
            ),
        // Leaves room for the FAB so the last wish is not hidden behind it.
        const SizedBox(height: AppSpacing.xl * 2),
      ],
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', // ignore: require_trailing_commas
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatBirthday(int month, int day) => '${_months[month - 1]} $day';
}

/// The compose FAB is shown only when there is something the user could
/// actually do with it, and only when the write would not be pointlessly
/// refused: the person has a birthday to derive an occasion year from
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
