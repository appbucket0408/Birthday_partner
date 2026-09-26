import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/ops/slots/ops_slots_cubit.dart';
import 'package:birthday_app/ops/slots/ops_slots_screen.dart';
import 'package:birthday_app/repositories/ops_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOps implements OpsRepository {
  _FakeOps(this.slots);
  List<DeliverySlot> slots;
  int setCapacityCalls = 0;
  int createCalls = 0;
  int? lastCreateCapacity;
  DateTime? lastCreateDate;
  String? lastCreateStart;

  @override
  Future<List<ServiceArea>> allServiceAreas() async =>
      [const ServiceArea(id: 1, name: 'Gurugram')];

  @override
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  }) async =>
      slots;

  @override
  Future<DeliverySlot> setSlotCapacity(
    int slotId, {
    required int capacity,
  }) async {
    setCapacityCalls++;
    return slots.first;
  }

  @override
  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  }) async {
    createCalls++;
    lastCreateCapacity = capacity;
    lastCreateDate = slotDate;
    lastCreateStart = windowStart;
    return slots.first;
  }

  @override
  Future<List<Product>> allProductsIn(int serviceAreaId) async =>
      throw UnimplementedError();

  @override
  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Product> setProductActive(
    int productId, {
    required bool isActive,
  }) async =>
      throw UnimplementedError();
}

void main() {
  final day = DateTime(2026, 10, 1);

  Future<OpsSlotsCubit> pumpView(WidgetTester tester, _FakeOps ops) async {
    final cubit = OpsSlotsCubit(ops);
    await cubit.load(from: DateTime(2026, 9, 30), to: DateTime(2026, 10, 5));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: cubit, child: const OpsSlotsView()),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('a slot shows both its capacity and what is reserved',
      (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 5,
        reserved: 3,
      ),
    ]);
    await pumpView(tester, ops);

    expect(find.textContaining('5'), findsWidgets);
    expect(
      find.textContaining(
        AppStrings.opsReservedTemplate.replaceFirst('%s', '3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'lowering capacity below reserved is refused with the REAL count, and '
      'never reaches the repository', (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        // capacity 3, reserved 3: one tap of minus tries 2, below reserved.
        capacity: 3,
        reserved: 3,
      ),
    ]);
    await pumpView(tester, ops);

    await tester.tap(find.byKey(const Key('ops_slot_minus_10')));
    await tester.pumpAndSettle();

    // The message must carry the real reserved count, not a fixed string --
    // otherwise it cannot tell the operator what they are up against.
    expect(
      find.text(
        AppStrings.opsCapacityBelowReservedTemplate.replaceFirst('%s', '3'),
      ),
      findsOneWidget,
    );
    expect(ops.setCapacityCalls, 0,
        reason: 'the refusal must happen before the write');
  });

  testWidgets('raising capacity does reach the repository', (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 3,
        reserved: 3,
      ),
    ]);
    await pumpView(tester, ops);

    await tester.tap(find.byKey(const Key('ops_slot_plus_10')));
    await tester.pumpAndSettle();

    // Without this, a guard that refused EVERY capacity change would pass
    // the test above while making the screen useless.
    expect(ops.setCapacityCalls, 1);
  });

  testWidgets(
      'the screen can CREATE a slot -- the reason this phase exists',
      (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 5,
        reserved: 0,
      ),
    ]);
    await pumpView(tester, ops);

    await tester.enterText(find.byKey(const Key('ops_new_date')), '2026-10-01');
    await tester.enterText(find.byKey(const Key('ops_new_start')), '14:00');
    await tester.enterText(find.byKey(const Key('ops_new_end')), '17:00');
    await tester.enterText(find.byKey(const Key('ops_new_capacity')), '8');
    await tester.tap(find.byKey(const Key('ops_add_slot')));
    await tester.pumpAndSettle();

    // M3 Phase 1a closed with the seed unable to complete a gift because
    // its only product and its only slot sat in different service areas.
    // A console that cannot create a slot cannot fix that, which was this
    // screen's entire justification.
    expect(ops.createCalls, 1);
    expect(ops.lastCreateStart, '14:00');
    expect(ops.lastCreateCapacity, 8);
  });

  testWidgets('the screen can switch service area', (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 5,
        reserved: 0,
      ),
    ]);
    await pumpView(tester, ops);

    // Asserting .value, never find.text: a DropdownButton keeps every item
    // mounted in an IndexedStack and they are not Offstage-wrapped.
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byKey(const Key('ops_slots_area_dropdown')),
    );
    expect(dropdown.value, 1);
  });

  testWidgets('an inverted window is refused before any write',
      (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 5,
        reserved: 0,
      ),
    ]);
    await pumpView(tester, ops);

    await tester.enterText(find.byKey(const Key('ops_new_date')), '2026-10-01');
    await tester.enterText(find.byKey(const Key('ops_new_start')), '17:00');
    await tester.enterText(find.byKey(const Key('ops_new_end')), '14:00');
    await tester.enterText(find.byKey(const Key('ops_new_capacity')), '8');
    await tester.tap(find.byKey(const Key('ops_add_slot')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.opsWindowOrder), findsOneWidget);
    expect(ops.createCalls, 0);
  });

  testWidgets('a typed date is what gets created, not the range start',
      (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 5,
        reserved: 0,
      ),
    ]);
    await pumpView(tester, ops);

    await tester.enterText(find.byKey(const Key('ops_new_date')), '2026-11-20');
    await tester.enterText(find.byKey(const Key('ops_new_start')), '14:00');
    await tester.enterText(find.byKey(const Key('ops_new_end')), '17:00');
    await tester.enterText(find.byKey(const Key('ops_new_capacity')), '8');
    await tester.tap(find.byKey(const Key('ops_add_slot')));
    await tester.pumpAndSettle();

    // Without a date field the form could only ever create slots on the
    // range's first day, which is barely more useful than not having one.
    expect(ops.lastCreateDate, DateTime(2026, 11, 20));
  });

  testWidgets('a malformed date is refused before any write', (tester) async {
    final ops = _FakeOps([
      DeliverySlot(
        id: 10,
        serviceAreaId: 1,
        slotDate: day,
        windowStart: '10:00:00',
        windowEnd: '13:00:00',
        capacity: 5,
        reserved: 0,
      ),
    ]);
    await pumpView(tester, ops);

    await tester.enterText(find.byKey(const Key('ops_new_date')), '20-11-2026');
    await tester.enterText(find.byKey(const Key('ops_new_start')), '14:00');
    await tester.enterText(find.byKey(const Key('ops_new_end')), '17:00');
    await tester.enterText(find.byKey(const Key('ops_new_capacity')), '8');
    await tester.tap(find.byKey(const Key('ops_add_slot')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.opsDateInvalid), findsOneWidget);
    expect(ops.createCalls, 0);
  });
}
