import '../../models/person.dart';
import '../../models/product.dart';
import '../../models/service_area.dart';

/// The catalog screen (spec §7): service areas, then the active products in
/// whichever one is selected.
sealed class CatalogState {
  const CatalogState();
}

class CatalogLoading extends CatalogState {
  const CatalogLoading();
}

/// [person] is carried here, not just used to gate `load()`, so the screen
/// can title itself and so Task 6/7 can read `person.birthday` forward into
/// the slot picker and the draft -- neither of those is a route, so the
/// person and its birthday cannot be re-fetched there; they can only be
/// carried from here.
///
/// [selectedAreaId] is null exactly when [areas] is empty -- a pilot with no
/// service area configured yet is a normal state, not an error, so
/// [products] is simply empty alongside it rather than the screen having
/// nothing to select.
class CatalogLoaded extends CatalogState {
  const CatalogLoaded({
    required this.person,
    required this.areas,
    required this.selectedAreaId,
    required this.products,
  });

  final Person person;
  final List<ServiceArea> areas;
  final int? selectedAreaId;
  final List<Product> products;
}

/// Reused for every failure this cubit can hit, including the up-front
/// refusal when the recipient has no birthday -- Task 6/7 consume this
/// three-branch state machine as briefed, so a null-birthday refusal must
/// not grow a fourth branch of its own.
class CatalogError extends CatalogState {
  const CatalogError(this.message);
  final String message;
}
