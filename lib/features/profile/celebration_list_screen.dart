import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/initial_avatar.dart';
import '../../core/result.dart';
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
/// [celebrateBack] turns the Celebrates list into somewhere to act: each
/// person the viewer does not celebrate yet (per [fetchAlreadyCelebrating])
/// gets a "Celebrate back" button, and those they do show "Celebrating".
/// Both are null on the Celebrating list, which has nothing to offer.
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
    this.fetchAlreadyCelebrating,
    this.celebrateBack,
  });

  final String title;
  final String emptyMessage;
  final bool navigable;
  final Future<List<Person>> Function() fetchPeople;
  final Future<Set<int>> Function()? fetchAlreadyCelebrating;
  final Future<void> Function(int personId)? celebrateBack;

  @override
  State<CelebrationListScreen> createState() => _CelebrationListScreenState();
}

enum _Status { loading, loaded, error }

class _CelebrationListScreenState extends State<CelebrationListScreen> {
  _Status _status = _Status.loading;
  List<Person> _people = const [];
  String _errorMessage = '';

  // Who the viewer already celebrates, and which "Celebrate back" taps are
  // in flight -- per row, so one slow request does not lock the others.
  Set<int> _celebrating = const {};
  final Set<int> _pending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.loading);
    try {
      final people = await widget.fetchPeople();
      final celebrating =
          await widget.fetchAlreadyCelebrating?.call() ?? const <int>{};
      if (!mounted) return;
      setState(() {
        _people = people;
        _celebrating = celebrating;
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

  Future<void> _celebrateBack(Person person) async {
    final action = widget.celebrateBack;
    if (action == null || !_pending.add(person.id)) return;
    setState(() {});
    try {
      await action(person.id);
      if (!mounted) return;
      setState(() => _celebrating = {..._celebrating, person.id});
    } on AppFailure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(f.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.somethingWentWrong)),
      );
    } finally {
      _pending.remove(person.id);
      if (mounted) setState(() {});
    }
  }

  Widget? _trailing(Person person) {
    if (widget.celebrateBack == null) return null;
    if (_celebrating.contains(person.id)) {
      return Row(
        key: Key('celebrating_${person.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          const Text(AppStrings.celebratingAlready),
        ],
      );
    }
    final busy = _pending.contains(person.id);
    return FilledButton.tonal(
      key: Key('celebrate_back_${person.id}'),
      onPressed: busy ? null : () => _celebrateBack(person),
      child: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text(AppStrings.celebrateBack),
    );
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
                leading: InitialAvatar(name: person.displayName),
                title: Text(person.displayName),
                trailing: _trailing(person),
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
