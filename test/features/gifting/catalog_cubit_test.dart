import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/gifting/catalog_cubit.dart';
import 'package:birthday_app/features/gifting/catalog_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:birthday_app/repositories/person_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real fakes, not mocks -- same pattern as
/// test/features/person/person_cubit_test.dart's `_FakePerson`/`_FakeWish`.
class _FakeGift implements GiftRepository {
  _FakeGift({
    this.areasToReturn = const [],
    this.serviceAreasError,
    this.productsByArea = const {},
  });

  List<ServiceArea> areasToReturn;
  Object? serviceAreasError;
  Map<int, List<Product>> productsByArea;

  int serviceAreasCalls = 0;
  int productsInCalls = 0;
  final List<int> productsInAreaIds = [];

  /// When set, `serviceAreas()` suspends on this until it is completed --
  /// this is how the reentrancy test forces two `load()` calls to genuinely
  /// overlap rather than merely being called back-to-back and racing to
  /// resolve on their own, per Amendment C.
  Completer<void>? serviceAreasGate;

  @override
  Future<List<ServiceArea>> serviceAreas() async {
    serviceAreasCalls++;
    if (serviceAreasGate != null) await serviceAreasGate!.future;
    if (serviceAreasError != null) throw serviceAreasError!;
    return areasToReturn;
  }

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async {
    productsInCalls++;
    productsInAreaIds.add(serviceAreaId);
    return productsByArea[serviceAreaId] ?? [];
  }

  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async =>
      throw UnimplementedError('not used by CatalogCubit');

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async =>
      throw UnimplementedError('not used by CatalogCubit');

  @override
  Future<List<Gift>> myGifts() async =>
      throw UnimplementedError('not used by CatalogCubit');
}

class _FakePerson implements PersonRepository {
  _FakePerson({this.personToReturn});

  Person? personToReturn;

  int personCalls = 0;

  @override
  Future<Person> person(int personId) async {
    personCalls++;
    return personToReturn!;
  }

  @override
  Future<int> celebratorCount(int personId) async =>
      throw UnimplementedError('not used by CatalogCubit');
}

Person _person(int id, {Birthday? birthday}) => Person(
      id: id,
      displayName: 'Person $id',
      isClaimed: false,
      birthday: birthday,
    );

ServiceArea _area(int id, {String name = 'Area'}) =>
    ServiceArea(id: id, name: name);

Product _product(int id, {int serviceAreaId = 1}) => Product(
      id: id,
      serviceAreaId: serviceAreaId,
      name: 'Cake $id',
      flavour: 'chocolate',
      size: '500g',
      priceMinor: 50000,
      imageUrl: null,
    );

const _birthday = Birthday(month: 6, day: 15);

void main() {
  // 1. load() emits CatalogLoading then CatalogLoaded with the areas, the
  //    first area preselected, and that area's products.
  blocTest<CatalogCubit, CatalogState>(
    'load() emits CatalogLoading then CatalogLoaded with areas, the first '
    "area preselected, and that area's products",
    build: () => CatalogCubit(
      _FakeGift(
        areasToReturn: [_area(1, name: 'Downtown'), _area(2, name: 'Suburb')],
        productsByArea: {
          1: [_product(1), _product(2)],
        },
      ),
      _FakePerson(personToReturn: _person(1, birthday: _birthday)),
    ),
    act: (c) => c.load(1),
    expect: () => [
      isA<CatalogLoading>(),
      isA<CatalogLoaded>()
          .having((s) => s.person.id, 'person.id', 1)
          .having((s) => s.areas.map((a) => a.id).toList(), 'area ids', [1, 2])
          .having((s) => s.selectedAreaId, 'selectedAreaId', 1)
          .having(
            (s) => s.products.map((p) => p.id).toList(),
            'product ids',
            [1, 2],
          ),
    ],
  );

  // 2. selectArea() swaps the products without refetching the areas --
  //    assert the fake recorded ONE serviceAreas() call and TWO productsIn()
  //    calls.
  test(
      'selectArea() swaps the products without refetching the areas', () async {
    final gift = _FakeGift(
      areasToReturn: [_area(1), _area(2)],
      productsByArea: {
        1: [_product(1)],
        2: [_product(2), _product(3, serviceAreaId: 2)],
      },
    );
    final cubit = CatalogCubit(
      gift,
      _FakePerson(personToReturn: _person(1, birthday: _birthday)),
    );
    await cubit.load(1);

    await cubit.selectArea(2);

    final state = cubit.state;
    expect(state, isA<CatalogLoaded>());
    final loaded = state as CatalogLoaded;
    expect(loaded.selectedAreaId, 2);
    expect(loaded.products.map((p) => p.id).toList(), [2, 3]);
    expect(gift.serviceAreasCalls, 1);
    expect(gift.productsInCalls, 2);
  });

  // 3. An empty area list still loads (CatalogLoaded with no areas), not an
  //    error screen. A pilot with no service area configured is a normal
  //    state.
  blocTest<CatalogCubit, CatalogState>(
    'an empty area list still loads as CatalogLoaded, not an error',
    build: () => CatalogCubit(
      _FakeGift(),
      _FakePerson(personToReturn: _person(1, birthday: _birthday)),
    ),
    act: (c) => c.load(1),
    expect: () => [
      isA<CatalogLoading>(),
      isA<CatalogLoaded>()
          .having((s) => s.areas, 'areas', isEmpty)
          .having((s) => s.selectedAreaId, 'selectedAreaId', isNull)
          .having((s) => s.products, 'products', isEmpty),
    ],
  );

  // 4. A failing serviceAreas() surfaces as CatalogError with a human
  //    message. A non-AppFailure falls back to AppStrings.somethingWentWrong
  //    -- that is the discriminating assertion; an "Instance of" check alone
  //    would pass merely because AppFailure.toString() exists.
  test(
      'a failing serviceAreas() surfaces as CatalogError with the '
      "ServerFailure's own message, never 'Instance of'", () async {
    final gift = _FakeGift(
      serviceAreasError: const ServerFailure('boom from the server'),
    );
    final cubit = CatalogCubit(
      gift,
      _FakePerson(personToReturn: _person(1, birthday: _birthday)),
    );

    await cubit.load(1);

    final state = cubit.state;
    expect(state, isA<CatalogError>());
    final message = (state as CatalogError).message;
    expect(message, 'boom from the server');
    expect(message, isNot(contains('Instance of')));
  });

  test(
      'a non-AppFailure error from serviceAreas() falls back to the '
      'generic message', () async {
    final gift = _FakeGift(serviceAreasError: StateError('unexpected'));
    final cubit = CatalogCubit(
      gift,
      _FakePerson(personToReturn: _person(1, birthday: _birthday)),
    );

    await cubit.load(1);

    final state = cubit.state;
    expect(state, isA<CatalogError>());
    expect((state as CatalogError).message, AppStrings.somethingWentWrong);
  });

  // 5. A second load() while the first is in flight is ignored
  //    (ReentrancyGuard). Built so the two calls genuinely OVERLAP: the fake
  //    suspends serviceAreas() on a Completer, both load() calls are fired
  //    without awaiting the first, and only then is the gate completed. A
  //    test that awaited the first load() before calling the second would
  //    prove nothing -- the guard releases its key in a `finally` as soon as
  //    the first call finishes, so a second, later call always goes through
  //    regardless of whether the guard exists at all.
  test('a second load() while the first is in flight is ignored', () async {
    final gate = Completer<void>();
    final gift = _FakeGift(areasToReturn: [_area(1)])
      ..serviceAreasGate = gate;
    final cubit = CatalogCubit(
      gift,
      _FakePerson(personToReturn: _person(1, birthday: _birthday)),
    );

    final first = cubit.load(1);
    final second = cubit.load(1);
    gate.complete();
    await Future.wait([first, second]);

    expect(gift.serviceAreasCalls, 1);
  });

  // 6 (Amendment A). The route is reachable cold (a deep link, or any
  // context.go straight to '/gift/new/:personId'), bypassing the person
  // page's own gate entirely -- so a null birthday must be refused by the
  // cubit itself, up front, before any catalog fetch. The discriminating
  // assertion is productsIn() never being called: it proves the refusal
  // happens BEFORE fetching, not merely instead of showing the result.
  test(
      'a null-birthday person yields CatalogError before any catalog fetch',
      () async {
    final gift = _FakeGift(areasToReturn: [_area(1)]);
    final cubit = CatalogCubit(
      gift,
      _FakePerson(personToReturn: _person(1)), // no birthday
    );

    await cubit.load(1);

    final state = cubit.state;
    expect(state, isA<CatalogError>());
    expect((state as CatalogError).message, AppStrings.giftNeedsBirthday);
    expect(gift.serviceAreasCalls, 0);
    expect(gift.productsInCalls, 0);
  });
}
