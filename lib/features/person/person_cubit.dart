import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
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
  PersonCubit(this._people, this._wishes, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const PersonLoading());

  final PersonRepository _people;
  final WishRepository _wishes;
  final DateTime Function() _now;

  Future<void> load(int personId) => guard('load', () async {
        emit(const PersonLoading());
        try {
          final person = await _people.person(personId);
          final count = await _people.celebratorCount(personId);
          final wishes = await _wishes.wishesFor(personId);
          emit(
            PersonLoaded(
              person: person,
              celebratorCount: count,
              wishes: wishes,
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
  /// A person with no birthday cannot reach this method through the screen
  /// -- the compose FAB is hidden whenever `person.birthday` is null -- so
  /// the branch below is defensive, not a real path. It emits the generic
  /// failure rather than inventing a year nobody has.
  Future<void> postWish(String body) => guard('post', () async {
        final current = state;
        if (current is! PersonLoaded) return;
        final birthday = current.person.birthday;
        if (birthday == null) {
          emit(const PersonError(AppStrings.somethingWentWrong));
          return;
        }
        emit(
          PersonLoaded(
            person: current.person,
            celebratorCount: current.celebratorCount,
            wishes: current.wishes,
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
          final wishes = await _wishes.wishesFor(current.person.id);
          emit(
            PersonLoaded(
              person: current.person,
              celebratorCount: current.celebratorCount,
              wishes: wishes,
            ),
          );
        } on AppFailure catch (f) {
          emit(PersonError(f.message));
        } catch (_) {
          emit(const PersonError(AppStrings.somethingWentWrong));
        }
      });
}
