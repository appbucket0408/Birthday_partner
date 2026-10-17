import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../repositories/graph_repository.dart';
import '../../repositories/person_repository.dart';
import '../../repositories/wish_repository.dart';
import 'person_state.dart';

/// The person page (spec §7.1) and the compose sheet it hosts (§7.2).
///
/// Mixes in [ReentrancyGuard] rather than hand-rolling a bool or a state
/// check -- Phase 2b grew five of those in three shapes before this mixin
/// existed. A state check is not equivalent: [PersonLoaded.posting] is
/// itself emitted from inside [postWish], after the guard has already
/// claimed its key, which is exactly the ordering that keeps a double-tap
/// from landing in the gap before the flag would otherwise be set.
class PersonCubit extends Cubit<PersonState> with ReentrancyGuard {
  /// [now] is injectable for the same reason `TimelineCubit` takes it: a
  /// test that derives an occasion year off the real clock passes today and
  /// fails on the next run past a birthday.
  ///
  /// [_graph] is consumed for exactly one thing: `celebrations()` returns
  /// the signed-in user's own celebration edges (filtered server-side on
  /// `celebrator_profile_id = auth.uid()`), and membership of that list is
  /// the only client-visible way to know the viewer celebrates the loaded
  /// person, as opposed to merely being visible to them via one of
  /// `private.can_see_person`'s other two branches. `GraphRepository` is
  /// already registered in `app.dart`, so this is not a new dependency on
  /// this screen, only a new consumer of an existing one.
  PersonCubit(
    this._people,
    this._wishes,
    this._graph, {
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(const PersonLoading());

  final PersonRepository _people;
  final WishRepository _wishes;
  final GraphRepository _graph;
  final DateTime Function() _now;

  Future<void> load(int personId) => guard('load', () async {
        emit(const PersonLoading());
        try {
          final person = await _people.person(personId);
          final count = await _people.celebratorCount(personId);
          final wishes = await _wishes.wishesFor(personId);
          final celebrations = await _graph.celebrations();
          final viewerCelebrates =
              celebrations.any((c) => c.person.id == personId);
          final celebratesViewer = await _celebratesViewer(personId);
          emit(
            PersonLoaded(
              person: person,
              celebratorCount: count,
              wishes: wishes,
              viewerCelebrates: viewerCelebrates,
              celebratesViewer: celebratesViewer,
            ),
          );
        } on AppFailure catch (f) {
          emit(PersonError(f.message));
        } catch (_) {
          emit(const PersonError(AppStrings.somethingWentWrong));
        }
      });

  /// Posts a wish on the currently loaded person's wall, then reloads it so
  /// the new wish appears.
  ///
  /// The occasion year is derived from the person's own birthday via
  /// [Birthday.occasionYear] -- never taken as a parameter and never read
  /// off the current year -- so a December birthday wished in January
  /// attaches to last December, not next. The user is never asked.
  ///
  /// A person with no birthday, or a viewer who does not celebrate them,
  /// cannot reach this method through the screen -- the compose FAB is
  /// hidden in both cases -- so the branch below is defensive, not a real
  /// path. `wishes_insert_own` still enforces the celebration edge
  /// server-side regardless (the race where the viewer un-celebrates
  /// mid-compose), so a rejection here is a real, reachable outcome even
  /// though the FAB itself is gated; either way, a failure here must not
  /// discard the already-rendered wall -- it surfaces transiently via
  /// [PersonLoaded.postError], the same shape `TimelineLoaded.error` uses,
  /// not by replacing the state with [PersonError].
  ///
  /// The write and the post-success reload are two SEPARATE try/catch
  /// blocks, not one. A failure of the write is the only thing that sets
  /// [PersonLoaded.postError] -- a failure of the reload that follows a
  /// successful write must not, because the wish was genuinely posted by
  /// then; reporting it as failed would invite a retry that double-posts
  /// it. That reload failure instead falls back to the wall already held in
  /// [current], stale but correct, with no error shown at all.
  /// Only a label: failing to learn it must not fail the page, so a lookup
  /// error reads as "no".
  Future<bool> _celebratesViewer(int personId) async {
    try {
      return (await _graph.celebratesMe()).contains(personId);
    } catch (_) {
      return false;
    }
  }

  Future<void> postWish(String body) => guard('post', () async {
        final current = state;
        if (current is! PersonLoaded) return;
        final birthday = current.person.birthday;
        if (birthday == null) {
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: current.wishes,
              viewerCelebrates: current.viewerCelebrates,
            celebratesViewer: current.celebratesViewer,
              postError: AppStrings.somethingWentWrong,
            ),
          );
          return;
        }
        // Wishes open on the birthday only. The page hides the button on
        // other days; this is the same rule for a sheet left open past
        // midnight.
        if (!birthday.isOn(_now())) {
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: current.wishes,
              viewerCelebrates: current.viewerCelebrates,
              celebratesViewer: current.celebratesViewer,
              postError: AppStrings.personWishOnBirthday,
            ),
          );
          return;
        }
        emit(
          PersonLoaded(
            person: current.person,
            celebratorCount: current.celebratorCount,
            wishes: current.wishes,
            viewerCelebrates: current.viewerCelebrates,
            celebratesViewer: current.celebratesViewer,
            posting: true,
          ),
        );
        try {
          final occasionYear = birthday.occasionYear(_now());
          await _wishes.post(
            personId: current.person.id,
            body: body,
            occasionYear: occasionYear,
          );
        } on AppFailure catch (f) {
          // 23505 is wishes_one_message_per_year: the viewer already wished
          // this person for this occasion year. Not a fault -- say so.
          final alreadyWished = f is ServerFailure && f.code == '23505';
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: current.wishes,
              viewerCelebrates: current.viewerCelebrates,
            celebratesViewer: current.celebratesViewer,
              postError:
                  alreadyWished ? AppStrings.wishAlreadyThisYear : f.message,
            ),
          );
          return;
        } catch (_) {
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: current.wishes,
              viewerCelebrates: current.viewerCelebrates,
            celebratesViewer: current.celebratesViewer,
              postError: AppStrings.somethingWentWrong,
            ),
          );
          return;
        }

        // The write above already succeeded -- the wish exists. A failure
        // from here on is a stale wall, not a false failure: reporting
        // postError here would tell the user their wish was not posted when
        // it was, and a reasonable retry would double-post it (there is no
        // idempotency key on the write). So a failed reload falls back to
        // the wall this cubit already has, with no postError at all.
        try {
          final wishes = await _wishes.wishesFor(current.person.id);
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: wishes,
              viewerCelebrates: current.viewerCelebrates,
            celebratesViewer: current.celebratesViewer,
            ),
          );
        } catch (_) {
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: current.wishes,
              viewerCelebrates: current.viewerCelebrates,
            celebratesViewer: current.celebratesViewer,
            ),
          );
        }
      });
}
