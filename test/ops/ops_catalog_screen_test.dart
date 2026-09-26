import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/ops/catalog/ops_catalog_cubit.dart';
import 'package:birthday_app/ops/catalog/ops_catalog_screen.dart';
import 'package:birthday_app/repositories/ops_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product(int id, {required String name, bool isActive = true}) =>
    Product(
      id: id,
      serviceAreaId: 1,
      name: name,
      flavour: null,
      size: null,
      priceMinor: 84900,
      imageUrl: null,
      isActive: isActive,
    );

class _FakeOps implements OpsRepository {
  _FakeOps(this.products);
  List<Product> products;

  int setActiveCalls = 0;
  int? lastId;
  bool? lastValue;

  @override
  Future<List<ServiceArea>> allServiceAreas() async =>
      [const ServiceArea(id: 1, name: 'Gurugram')];

  @override
  Future<List<Product>> allProductsIn(int serviceAreaId) async => products;

  @override
  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  }) async =>
      _product(99, name: name);

  @override
  Future<Product> setProductActive(
    int productId, {
    required bool isActive,
  }) async {
    setActiveCalls++;
    lastId = productId;
    lastValue = isActive;
    products = [
      for (final p in products)
        if (p.id == productId)
          _product(p.id, name: p.name, isActive: isActive)
        else
          p,
    ];
    return products.firstWhere((p) => p.id == productId);
  }

  @override
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  }) async =>
      throw UnimplementedError();

  @override
  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  }) async =>
      throw UnimplementedError();

  @override
  Future<DeliverySlot> setSlotCapacity(
    int slotId, {
    required int capacity,
  }) async =>
      throw UnimplementedError();
}

void main() {
  Future<OpsCatalogCubit> pumpView(WidgetTester tester, _FakeOps ops) async {
    final cubit = OpsCatalogCubit(ops);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: cubit, child: const OpsCatalogView()),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('an inactive product is rendered, and visibly marked',
      (tester) async {
    final ops = _FakeOps([
      _product(10, name: 'Active One'),
      _product(11, name: 'Retired One', isActive: false),
    ]);
    await pumpView(tester, ops);

    // Present at all -- the console cannot reactivate what it will not show.
    expect(find.byKey(const Key('ops_product_11')), findsOneWidget);
    expect(find.text(AppStrings.opsInactive), findsOneWidget);
    expect(find.text(AppStrings.opsActive), findsOneWidget);
  });

  testWidgets('toggling calls setProductActive with the right id and value',
      (tester) async {
    final ops = _FakeOps([_product(10, name: 'Active One')]);
    await pumpView(tester, ops);

    await tester.tap(find.byKey(const Key('ops_product_toggle_10')));
    await tester.pumpAndSettle();

    // A call count on the fake, not "a switch rendered": the latter passes
    // for a switch wired to nothing.
    expect(ops.setActiveCalls, 1);
    expect(ops.lastId, 10);
    expect(ops.lastValue, isFalse, reason: 'an active product toggles off');
  });

  testWidgets('the area dropdown carries the selected id, not just its text',
      (tester) async {
    final ops = _FakeOps([_product(10, name: 'Active One')]);
    await pumpView(tester, ops);

    // Asserting .value, never find.text: a DropdownButton keeps every item
    // mounted in an IndexedStack and they are not Offstage-wrapped, so a
    // text assertion passes regardless of what is selected.
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byKey(const Key('ops_area_dropdown')),
    );
    expect(dropdown.value, 1);
  });
}
