import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/ops/slots/ops_slots_cubit.dart';
import 'package:birthday_app/ops/slots/ops_slots_state.dart';
import 'package:birthday_app/repositories/ops_repository.dart';
import 'package:flutter_test/flutter_test.dart';

DeliverySlot _slot(
  int id, {
  required DateTime date,
  String start = '10:00:00',
  String end = '13:00:00',
  int capacity = 5,
  int reserved = 0,
}) =>
    DeliverySlot(
      id: id,
      serviceAreaId: 1,
      slotDate: date,
      windowStart: start,
      windowEnd: end,
      capacity: capacity,
      reserved: reserved,
    );

class _FakeOps implements OpsRepository {
  _FakeOps({this.slots = const [], this.createError, this.gate});

  List<DeliverySlot> slots;
  Object? createError;
  Completer<void>? gate;

  int createCalls = 0;
  int setCapacityCalls = 0;

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
  Future<DeliverySlot> createSlot({
    required int serviceAreaId,
    required DateTime slotDate,
    required String windowStart,
    required String windowEnd,
    required int capacity,
  }) async {
    createCalls++;
    if (gate != null) await gate!.future;
    if (createError != null) throw createError!;
    return _slot(99, date: slotDate);
  }

  @override
  Future<DeliverySlot> setSlotCapacity(
    int slotId, {
    required int capacity,
  }) async {
    setCapacityCalls++;
    return _slot(slotId, date: DateTime(2026, 10, 1), capacity: capacity);
  }

  @override
  Future<List<Product>> allProductsIn(int serviceAreaId) async =>
      throw UnimplementedError('not used by OpsSlotsCubit');

  @override
  Future<Product> createProduct({
    required int serviceAreaId,
    required String name,
    String? flavour,
    String? size,
    required int priceMinor,
  }) async =>
      throw UnimplementedError('not used by OpsSlotsCubit');

  @override
  Future<Product> setProductActive(
    int productId, {
    required bool isActive,
  }) async =>
      throw UnimplementedError('not used by OpsSlotsCubit');
}

void main() {
  // Fixed dates, never DateTime.now(): Postgres runs UTC and this host runs
  // IST, and M3 Phase 1b shipped a fixture that passed by day and failed by
  // night because the two derived "today" independently.
  final day = DateTime(2026, 10, 1);
  final from = DateTime(2026, 9, 30);
  final to = DateTime(2026, 10, 5);

  Future<OpsSlotsCubit> loaded(_FakeOps ops) async {
    final cubit = OpsSlotsCubit(ops);
    await cubit.load(from: from, to: to);
    return cubit;
  }

  test('1. load() preselects the first area and loads its slots', () async {
    final ops = _FakeOps(slots: [_slot(10, date: day)]);
    final cubit = await loaded(ops);

    final state = cubit.state as OpsSlotsLoaded;
    expect(state.selectedAreaId, 1);
    expect(state.slots, hasLength(1));
  });

  test('2. an inverted or empty window is refused before any write', () async {
    for (final pair in [
      ('13:00', '13:00'),
      ('13:00', '10:00'),
    ]) {
      final ops = _FakeOps();
      final cubit = await loaded(ops);

      await cubit.addSlot(
        slotDate: day,
        windowStart: pair.$1,
        windowEnd: pair.$2,
        capacity: 5,
      );

      expect((cubit.state as OpsSlotsError).message, AppStrings.opsWindowOrder,
          reason: '${pair.$1}-${pair.$2}');
      // delivery_slots_window_ordered would otherwise raise a bare 23514,
      // indistinguishable from three other constraints on this schema.
      expect(ops.createCalls, 0);
    }
  });

  test('3. capacity below `reserved` is refused, naming the real count',
      () async {
    final ops = _FakeOps(slots: [_slot(10, date: day, capacity: 5, reserved: 3)]);
    final cubit = await loaded(ops);

    await cubit.changeCapacity(10, capacity: 2);

    final message = (cubit.state as OpsSlotsError).message;
    expect(message, contains('3'),
        reason: 'the message must carry the real reserved count');
    expect(message, AppStrings.opsCapacityBelowReservedTemplate
        .replaceFirst('%s', '3'));
    expect(ops.setCapacityCalls, 0);
  });

  test('4. a negative capacity is refused before any write', () async {
    final ops = _FakeOps(slots: [_slot(10, date: day, reserved: 0)]);
    final cubit = await loaded(ops);

    await cubit.changeCapacity(10, capacity: -1);

    expect((cubit.state as OpsSlotsError).message,
        AppStrings.opsCapacityNegative);
    expect(ops.setCapacityCalls, 0);
  });

  test('5. capacity EQUAL to reserved is allowed and does write', () async {
    final ops = _FakeOps(slots: [_slot(10, date: day, capacity: 5, reserved: 3)]);
    final cubit = await loaded(ops);

    await cubit.changeCapacity(10, capacity: 3);

    // The constraint is `reserved <= capacity`, so equality is LEGAL. Without
    // this test, a guard written as `<=` instead of `<` would pass every
    // other assertion here while forbidding a perfectly valid edit.
    expect(ops.setCapacityCalls, 1);
    expect(cubit.state, isA<OpsSlotsLoaded>());
  });

  test('6. a 23505 becomes the duplicate-window message, not the generic one',
      () async {
    final ops = _FakeOps(
      createError: const ServerFailure('duplicate key value', code: '23505'),
    );
    final cubit = await loaded(ops);

    await cubit.addSlot(
      slotDate: day,
      windowStart: '10:00',
      windowEnd: '13:00',
      capacity: 5,
    );

    // delivery_slots_unique_window is the ONE constraint here with its own
    // distinguishable code, so it earns its own message.
    expect((cubit.state as OpsSlotsError).message,
        AppStrings.opsDuplicateWindow);
  });

  test('7. other failures surface their own message, then the generic one',
      () async {
    final withServer = _FakeOps(
      createError: const ServerFailure('permission denied', code: '42501'),
    );
    final a = await loaded(withServer);
    await a.addSlot(
        slotDate: day, windowStart: '10:00', windowEnd: '13:00', capacity: 5);
    expect((a.state as OpsSlotsError).message, 'permission denied');

    final withPlain = _FakeOps(createError: StateError('x'));
    final b = await loaded(withPlain);
    await b.addSlot(
        slotDate: day, windowStart: '10:00', windowEnd: '13:00', capacity: 5);
    expect((b.state as OpsSlotsError).message, AppStrings.somethingWentWrong);
  });

  test('9. an AuthFailure is flagged as a dead session, not a normal error',
      () async {
    final ops = _FakeOps(createError: const AuthFailure('JWT expired'));
    final cubit = await loaded(ops);

    await cubit.addSlot(
        slotDate: day, windowStart: '10:00', windowEnd: '13:00', capacity: 5);

    expect((cubit.state as OpsSlotsError).sessionExpired, isTrue);
  });

  test('8. a second addSlot while the first is in flight is ignored',
      () async {
    final gate = Completer<void>();
    final ops = _FakeOps(gate: gate);
    final cubit = await loaded(ops);

    final first = cubit.addSlot(
        slotDate: day, windowStart: '10:00', windowEnd: '13:00', capacity: 5);
    final second = cubit.addSlot(
        slotDate: day, windowStart: '10:00', windowEnd: '13:00', capacity: 5);
    gate.complete();
    await Future.wait([first, second]);

    expect(ops.createCalls, 1);
  });
}
