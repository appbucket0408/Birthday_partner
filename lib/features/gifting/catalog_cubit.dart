import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/product.dart';
import '../../repositories/gift_repository.dart';
import '../../repositories/person_repository.dart';
import 'catalog_state.dart';

/// The catalog screen (spec §7): service area, then the active products in
/// it.
///
/// '/gift/new/:personId' is a real, path-parameter route -- reachable cold,
/// with nothing but a person id, via a deep link or any `context.go`. The
/// recipient's birthday cannot be handed down from the person page the way
/// the compose FAB does, because there is no guarantee the person page ran
/// at all. So this cubit loads the person itself, alongside the service
/// areas, rather than trusting a birthday was already resolved upstream --
/// [PersonRepository] is already registered in `app.dart` (`PersonCubit`
/// consumes it the same way), so this is not a new dependency in the tree,
/// only a new consumer of an existing one.
class CatalogCubit extends Cubit<CatalogState> with ReentrancyGuard {
  /// Whole-branch review §8 fold-in: this cubit once took an injectable
  /// `now` clock on the theory that Tasks 6/7 would need it here for
  /// `Birthday.nextOccurrence`. They didn't -- the slot picker and the
  /// draft screen each take their own clock independently -- so the
  /// parameter and its backing field sat unread behind
  /// `// ignore: unused_field` from the day this cubit was written. Removed
  /// rather than kept "for later": nothing in this codebase currently reads
  /// it, and reintroducing it if a future task genuinely needs it is cheap.
  CatalogCubit(this._gifts, this._people) : super(const CatalogLoading());

  final GiftRepository _gifts;
  final PersonRepository _people;

  /// Loads the recipient and the service areas together, then the first
  /// area's products.
  ///
  /// A null [Person.birthday] is refused up front, before any catalog
  /// fetch -- reused as [CatalogError] rather than a fourth state branch, so
  /// Task 6/7 keep consuming the same three-branch state machine. This is
  /// not defensive-only the way `PersonCubit.postWish`'s birthday check is:
  /// the person page's "Send a cake" action is gated on the same condition
  /// as its compose FAB, but this route is reachable directly, bypassing
  /// that gate entirely, so this refusal is a real, reachable path.
  Future<void> load(int personId) => guard('load', () async {
        emit(const CatalogLoading());
        try {
          final person = await _people.person(personId);
          if (person.birthday == null) {
            emit(const CatalogError(AppStrings.giftNeedsBirthday));
            return;
          }
          final areas = await _gifts.serviceAreas();
          final selectedAreaId = areas.isEmpty ? null : areas.first.id;
          final products = selectedAreaId == null
              ? const <Product>[]
              : await _gifts.productsIn(selectedAreaId);
          emit(
            CatalogLoaded(
              person: person,
              areas: areas,
              selectedAreaId: selectedAreaId,
              products: products,
            ),
          );
        } on AppFailure catch (f) {
          emit(CatalogError(f.message));
        } catch (_) {
          emit(const CatalogError(AppStrings.somethingWentWrong));
        }
      });

  /// Swaps the product list for [areaId] without refetching the areas or
  /// the person -- both are already held in the current [CatalogLoaded].
  Future<void> selectArea(int areaId) => guard('selectArea', () async {
        final current = state;
        if (current is! CatalogLoaded) return;
        try {
          final products = await _gifts.productsIn(areaId);
          emit(
            CatalogLoaded(
              person: current.person,
              areas: current.areas,
              selectedAreaId: areaId,
              products: products,
            ),
          );
        } on AppFailure catch (f) {
          emit(CatalogError(f.message));
        } catch (_) {
          emit(const CatalogError(AppStrings.somethingWentWrong));
        }
      });
}
