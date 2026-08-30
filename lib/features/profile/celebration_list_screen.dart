import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../models/celebration.dart';
import '../../models/person.dart';

/// One screen serving both of the profile's lists (spec §7.3):
/// `/profile/celebrating`, fed by `GraphRepository.celebrations()` mapped to
/// their people, and `/profile/celebrates`, fed by
/// `ProfileRepository.celebrates()`.
///
/// [navigable] decides whether a row navigates to `/person/:id`. Celebrating
/// rows do -- the viewer celebrates those people by definition, so
/// `private.can_see_person`'s "I celebrate them" branch always grants sight.
///
/// Celebrates rows COULD too: a Celebrates row is someone who celebrates
/// *you*, and `private.can_see_person`'s "they celebrate me" branch grants
/// the viewer sight of every one of them, so every row here would load its
/// person page successfully. Navigation is withheld anyway -- this is a
/// product choice, not a privacy boundary. A Celebrates row is a different
/// relationship from a Celebrating row (someone who added you, not someone
/// you added), and this list is about who celebrates you, not a launchpad
/// to their page. There is no per-row signal here that would let this
/// screen vary that choice within the list, so it is fixed for the whole
/// screen by the route that built it.
///
/// [fetchPeople] is not read off context: `GraphRepository` and
/// `ProfileRepository` return different shapes (`celebrations()` embeds a
/// `Person` inside each `Celebration`; `celebrates()` returns `Person`
/// directly), so the two routes each supply their own small mapping instead
/// of this screen knowing about both repositories.
class CelebrationListScreen extends StatefulWidget {
  const CelebrationListScreen({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.fetchPeople,
    this.navigable = false,
  });

  final String title;
  final String emptyMessage;
  final bool navigable;
  final Future<List<Person>> Function() fetchPeople;

  /// Maps celebration edges to the people they point at, substituting each
  /// person's nickname (when the viewer set one) for their address-book
  /// name -- the same substitution `Celebration.label` performs for
  /// `TimelineScreen`, kept in sync here so a nicknamed person reads the
  /// same on the profile as on the timeline for the *same* edge.
  ///
  /// `/profile/celebrates` has no equivalent call: those are incoming
  /// edges, and `my_celebrates()` deliberately never returns the
  /// celebrator's private nickname, so there is nothing to substitute.
  static List<Person> peopleFromCelebrations(
    List<Celebration> celebrations,
  ) =>
      [
        for (final c in celebrations)
          Person(
            id: c.person.id,
            displayName: c.label,
            isClaimed: c.person.isClaimed,
            birthday: c.person.birthday,
          ),
      ];

  @override
  State<CelebrationListScreen> createState() => _CelebrationListScreenState();
}

enum _Status { loading, loaded, error }

class _CelebrationListScreenState extends State<CelebrationListScreen> {
  _Status _status = _Status.loading;
  List<Person> _people = const [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.loading);
    try {
      final people = await widget.fetchPeople();
      if (!mounted) return;
      setState(() {
        _people = people;
        _status = _Status.loaded;
      });
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _errorMessage = f.message;
        _status = _Status.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppStrings.somethingWentWrong;
        _status = _Status.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        // Reached with context.go from the profile screen, which REPLACES
        // the page stack -- same reason '/profile' itself needs an explicit
        // `leading` rather than relying on `automaticallyImplyLeading`.
        leading: IconButton(
          key: const Key('celebration_list_back_button'),
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: switch (_status) {
        _Status.loading => const Center(child: CircularProgressIndicator()),
        _Status.error => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _load,
                  child: const Text(AppStrings.retry),
                ),
              ],
            ),
          ),
        _Status.loaded when _people.isEmpty => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(widget.emptyMessage, textAlign: TextAlign.center),
            ),
          ),
        _Status.loaded => ListView(
            children: [
              for (final person in _people)
                ListTile(
                  key: Key('celebration_list_person_${person.id}'),
                  title: Text(person.displayName),
                  onTap: widget.navigable
                      ? () => context.go('/person/${person.id}')
                      : null,
                ),
            ],
          ),
      },
    );
  }
}
