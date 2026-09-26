import '../../models/product.dart';
import '../../models/service_area.dart';

sealed class OpsCatalogState {
  const OpsCatalogState();
}

class OpsCatalogLoading extends OpsCatalogState {
  const OpsCatalogLoading();
}

/// [products] carries INACTIVE rows as well as active ones. That is the
/// point of this screen: staff cannot reactivate a product they cannot see,
/// and `GiftRepository.productsIn` filters them out.
///
/// [selectedAreaId] is null exactly when [areas] is empty — a deployment
/// with no service area configured is a normal state, not an error, so
/// [products] is simply empty alongside it.
class OpsCatalogLoaded extends OpsCatalogState {
  const OpsCatalogLoaded({
    required this.areas,
    required this.selectedAreaId,
    required this.products,
  });

  final List<ServiceArea> areas;
  final int? selectedAreaId;
  final List<Product> products;

  OpsCatalogLoaded copyWith({
    List<ServiceArea>? areas,
    int? selectedAreaId,
    List<Product>? products,
  }) =>
      OpsCatalogLoaded(
        areas: areas ?? this.areas,
        selectedAreaId: selectedAreaId ?? this.selectedAreaId,
        products: products ?? this.products,
      );
}

class OpsCatalogError extends OpsCatalogState {
  const OpsCatalogError(this.message, {this.sessionExpired = false});
  final String message;

  /// True when the failure was an [AuthFailure]: the session is gone, not
  /// merely a request that failed. The screen routes back to sign-in on
  /// this, because rendering the driver's own "JWT expired" inline with a
  /// Retry button gives the user no way out -- every retry fails the same.
  final bool sessionExpired;
}
