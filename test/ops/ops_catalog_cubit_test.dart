import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/ops/catalog/ops_catalog_cubit.dart';
import 'package:birthday_app/ops/catalog/ops_catalog_state.dart';
import 'package:birthday_app/repositories/ops_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product(int id, {required String name, bool isActive = true}) =>
    Product(
      id: id,
      serviceAreaId: 1,
      name: name,
      flavour: null,
      size: null,
      priceMinor: 50000,
      imageUrl: null,
      isActive: isActive,
    );

class _FakeOps implements OpsRepository {
  _FakeOps({
    this.areas = const [],
    this.products = const [],
    this.areasError,
    this.gate,
  });

  List<ServiceArea> areas;
  List<Product> products;
  Object? areasError;

  /// Gates createProduct so two calls can genuinely overlap.
  Completer<void>? gate;

  int areaCalls = 0;
  int productCalls = 0;
  int createCalls = 0;
  int setActiveCalls = 0;
  int? lastSetActiveId;
  bool? lastSetActiveValue;

  @override
  Future<List<ServiceArea>> allServiceAreas() async {
    areaCalls++;
    if (areasError != null) throw areasError!;
    return areas;
  }

  @override
  Future<List<Product>> allProductsIn(int serviceAreaId) async {
    productCalls++;
    return products;
  }

  @override
  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  }) async {
    createCalls++;
    if (gate != null) await gate!.future;
    final created = _product(99, name: name);
    products = [...products, created];
    return created;
  }

  @override
  Future<Product> setProductActive(
    int productId, {
    required bool isActive,
  }) async {
    setActiveCalls++;
    lastSetActiveId = productId;
    lastSetActiveValue = isActive;
    return _product(productId, name: 'x', isActive: isActive);
  }

  @override
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  }) async =>
      throw UnimplementedError('not used by OpsCatalogCubit');

  @override
  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  }) async =>
      throw UnimplementedError('not used by OpsCatalogCubit');

  @override
  Future<DeliverySlot> setSlotCapacity(
    int slotId, {
    required int capacity,
  }) async =>
      throw UnimplementedError('not used by OpsCatalogCubit');
}

void main() {
  final areas = [
    const ServiceArea(id: 1, name: 'Gurugram'),
    const ServiceArea(id: 2, name: 'Jaipur'),
  ];

  test('1. load() preselects the first area and loads its products', () async {
    final ops = _FakeOps(
      areas: areas,
      products: [_product(10, name: 'Truffle')],
    );
    final cubit = OpsCatalogCubit(ops);

    await cubit.load();

    final state = cubit.state as OpsCatalogLoaded;
    expect(state.areas, hasLength(2));
    expect(state.selectedAreaId, 1);
    expect(state.products, hasLength(1));
  });

  test('2. selectArea swaps products without refetching the areas', () async {
    final ops = _FakeOps(areas: areas, products: [_product(10, name: 'A')]);
    final cubit = OpsCatalogCubit(ops);

    await cubit.load();
    await cubit.selectArea(2);

    expect(ops.areaCalls, 1, reason: 'areas must not be refetched');
    expect(ops.productCalls, 2);
  });

  test('3. an INACTIVE product is present in the loaded state', () async {
    final ops = _FakeOps(
      areas: areas,
      products: [
        _product(10, name: 'Active One'),
        _product(11, name: 'Retired One', isActive: false),
      ],
    );
    final cubit = OpsCatalogCubit(ops);

    await cubit.load();

    final state = cubit.state as OpsCatalogLoaded;
    // The whole reason OpsRepository exists rather than reusing
    // GiftRepository.productsIn, which filters is_active = true.
    expect(
      state.products.where((p) => !p.isActive),
      hasLength(1),
      reason: 'staff must see the row the console exists to reactivate',
    );
  });

  test('4. a bad price is refused BEFORE any write reaches the database',
      () async {
    for (final bad in ['0', '-5', 'abc', '8.499', '']) {
      final ops = _FakeOps(areas: areas);
      final cubit = OpsCatalogCubit(ops);
      await cubit.load();

      await cubit.addProduct(name: 'Cake', priceText: bad);

      expect(cubit.state, isA<OpsCatalogError>(), reason: 'price "$bad"');
      expect(
        (cubit.state as OpsCatalogError).message,
        AppStrings.opsPriceInvalid,
      );
      // The assertion that matters: products_price_positive would answer
      // with a bare 23514, the same generic CHECK code three slot
      // constraints use, so the console could not say which rule was hit.
      expect(ops.createCalls, 0, reason: 'nothing may reach the database');
    }
  });

  test('5. an empty name is refused and does not write', () async {
    final ops = _FakeOps(areas: areas);
    final cubit = OpsCatalogCubit(ops);
    await cubit.load();

    await cubit.addProduct(name: '   ', priceText: '849');

    expect(
      (cubit.state as OpsCatalogError).message,
      AppStrings.opsNameRequired,
    );
    expect(ops.createCalls, 0);
  });

  test('6. failures surface their own message, then the generic one',
      () async {
    final withAppFailure = _FakeOps(
      areas: areas,
      areasError: const ServerFailure('permission denied'),
    );
    final a = OpsCatalogCubit(withAppFailure);
    await a.load();
    expect((a.state as OpsCatalogError).message, 'permission denied');
    expect((a.state as OpsCatalogError).message, isNot(contains('Instance of')));

    final withPlainError = _FakeOps(areas: areas, areasError: StateError('x'));
    final b = OpsCatalogCubit(withPlainError);
    await b.load();
    // The exact string: isA<OpsCatalogError>() alone would pass for both
    // branches and could not tell '$e' from the generic message.
    expect(
      (b.state as OpsCatalogError).message,
      AppStrings.somethingWentWrong,
    );
  });

  test('7. a second addProduct while the first is in flight is ignored',
      () async {
    final gate = Completer<void>();
    final ops = _FakeOps(areas: areas, gate: gate);
    final cubit = OpsCatalogCubit(ops);
    await cubit.load();

    final first = cubit.addProduct(name: 'Cake', priceText: '849');
    final second = cubit.addProduct(name: 'Cake', priceText: '849');
    gate.complete();
    await Future.wait([first, second]);

    expect(ops.createCalls, 1);
  });
}
