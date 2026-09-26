import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/reentrancy_guard.dart';
import '../../core/result.dart';
import '../../models/product.dart';
import '../../repositories/ops_repository.dart';
import 'ops_catalog_state.dart';

/// The catalog half of the ops console: service areas, and the products in
/// one of them.
class OpsCatalogCubit extends Cubit<OpsCatalogState> with ReentrancyGuard {
  OpsCatalogCubit(this._ops) : super(const OpsCatalogLoading());

  final OpsRepository _ops;

  /// Kept so a mutation can refresh the product list without refetching the
  /// areas, and so an error state can be recovered from.
  OpsCatalogLoaded? _loaded;

  Future<void> load() => guard('load', () async {
        emit(const OpsCatalogLoading());
        try {
          final areas = await _ops.allServiceAreas();
          final selected = areas.isEmpty ? null : areas.first.id;
          final products =
              selected == null ? <Product>[] : await _ops.allProductsIn(selected);

          _loaded = OpsCatalogLoaded(
            areas: areas,
            selectedAreaId: selected,
            products: products,
          );
          emit(_loaded!);
        } on AppFailure catch (f) {
          emit(OpsCatalogError(f.message));
        } catch (_) {
          emit(const OpsCatalogError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> selectArea(int serviceAreaId) => guard('selectArea', () async {
        final current = _loaded;
        if (current == null) return;
        try {
          // Areas are NOT refetched: they did not change, and a second round
          // trip would make the dropdown flicker for nothing.
          final products = await _ops.allProductsIn(serviceAreaId);
          _loaded = current.copyWith(
            selectedAreaId: serviceAreaId,
            products: products,
          );
          emit(_loaded!);
        } on AppFailure catch (f) {
          emit(OpsCatalogError(f.message));
        } catch (_) {
          emit(const OpsCatalogError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> addProduct({
    required String name,
    String? flavour,
    String? size,
    required String priceText,
  }) =>
      guard('addProduct', () async {
        final current = _loaded;
        final areaId = current?.selectedAreaId;
        if (current == null || areaId == null) return;

        // Validated BEFORE the write, both of them. On this schema
        // products_price_positive raises 23514 -- Postgres's generic
        // CHECK-violation code, shared with delivery_slots' window-order,
        // not-oversold and capacity constraints -- so a failure that reached
        // the database could not be told apart from three unrelated rules.
        if (name.trim().isEmpty) {
          emit(const OpsCatalogError(AppStrings.opsNameRequired));
          return;
        }
        final priceMinor = Product.parsePriceMinor(priceText);
        if (priceMinor == null) {
          emit(const OpsCatalogError(AppStrings.opsPriceInvalid));
          return;
        }

        try {
          await _ops.createProduct(
            serviceAreaId: areaId,
            name: name.trim(),
            flavour: (flavour?.trim().isEmpty ?? true) ? null : flavour!.trim(),
            size: (size?.trim().isEmpty ?? true) ? null : size!.trim(),
            priceMinor: priceMinor,
          );
          final products = await _ops.allProductsIn(areaId);
          _loaded = current.copyWith(products: products);
          emit(_loaded!);
        } on AppFailure catch (f) {
          emit(OpsCatalogError(f.message));
        } catch (_) {
          emit(const OpsCatalogError(AppStrings.somethingWentWrong));
        }
      });

  Future<void> toggleActive(int productId, {required bool isActive}) =>
      guard('toggleActive:$productId', () async {
        final current = _loaded;
        final areaId = current?.selectedAreaId;
        if (current == null || areaId == null) return;
        try {
          await _ops.setProductActive(productId, isActive: isActive);
          final products = await _ops.allProductsIn(areaId);
          _loaded = current.copyWith(products: products);
          emit(_loaded!);
        } on AppFailure catch (f) {
          emit(OpsCatalogError(f.message));
        } catch (_) {
          emit(const OpsCatalogError(AppStrings.somethingWentWrong));
        }
      });
}
