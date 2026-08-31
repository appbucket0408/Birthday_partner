import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/gifting/catalog_cubit.dart';
import 'package:birthday_app/features/gifting/catalog_screen.dart';
import 'package:birthday_app/features/gifting/catalog_state.dart';
import 'package:birthday_app/features/gifting/slot_picker_screen.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// A real fake, not a mock -- SlotPickerScreen reads `GiftRepository` off
/// context in its own `initState`, so any test that lets a push to it
/// actually mount needs one in the tree, or that read throws
/// `ProviderNotFoundException`. Returns no slots by default: these tests
/// are about what CatalogScreen hands to SlotPickerScreen, not about the
/// picker's own rendering, which `slot_picker_screen_test.dart` covers.
class _FakeGift implements GiftRepository {
  @override
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  }) async =>
      const [];

  @override
  Future<List<ServiceArea>> serviceAreas() async =>
      throw UnimplementedError('not used by CatalogScreen');

  @override
  Future<List<Product>> productsIn(int serviceAreaId) async =>
      throw UnimplementedError('not used by CatalogScreen');

  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async =>
      throw UnimplementedError('not used by CatalogScreen');

  @override
  Future<List<Gift>> myGifts() async =>
      throw UnimplementedError('not used by CatalogScreen');
}

/// A mocked CatalogCubit -- same pattern as
/// test/features/person/person_screen_test.dart's `_MockPersonCubit`. Lets
/// each test drop straight into the exact state it wants, and lets the
/// retry/dropdown/push tests verify which cubit methods were actually
/// called, not just that a tap didn't crash.
class _MockCatalogCubit extends MockCubit<CatalogState>
    implements CatalogCubit {}

Person _person(int id, {Birthday? birthday, String? displayName}) => Person(
      id: id,
      displayName: displayName ?? 'Person $id',
      isClaimed: false,
      birthday: birthday ?? const Birthday(month: 6, day: 15),
    );

ServiceArea _area(int id, String name) => ServiceArea(id: id, name: name);

Product _product(int id, {int serviceAreaId = 1, String name = 'Cake'}) =>
    Product(
      id: id,
      serviceAreaId: serviceAreaId,
      name: name,
      flavour: 'chocolate',
      size: '500g',
      priceMinor: 50000,
      imageUrl: null,
    );

CatalogLoaded _loaded({
  required List<ServiceArea> areas,
  required int? selectedAreaId,
  required List<Product> products,
  Person? person,
}) =>
    CatalogLoaded(
      person: person ?? _person(1),
      areas: areas,
      selectedAreaId: selectedAreaId,
      products: products,
    );

void main() {
  late _MockCatalogCubit cubit;

  setUp(() {
    cubit = _MockCatalogCubit();
    // Unstubbed calls to a Future<void>-returning mock method return null,
    // not a Future -- stub both so a verified call doesn't also throw a
    // type error, same reason otp_screen_test.dart stubs PhoneCubit's
    // methods in its own setUp.
    when(() => cubit.load(any())).thenAnswer((_) async {});
    when(() => cubit.selectArea(any())).thenAnswer((_) async {});
  });

  /// Pumps [CatalogView] alone (no router) -- used by the tests that don't
  /// need `context.go` to actually resolve anywhere. Wrapped in a
  /// [RepositoryProvider]<[GiftRepository]> because a push to
  /// [SlotPickerScreen] reads one off context in its own `initState` --
  /// needed here, not just by the dedicated push tests, since any test that
  /// happens to trigger a push would otherwise throw
  /// `ProviderNotFoundException` on a completely unrelated assertion.
  Future<void> pumpView(WidgetTester tester, CatalogState state) async {
    whenListen(cubit, const Stream<CatalogState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<GiftRepository>.value(
          value: _FakeGift(),
          child: BlocProvider<CatalogCubit>.value(
            value: cubit,
            child: const CatalogView(personId: 1),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // 1. The back affordance actually reaches '/person/:personId' -- not just
  // "a button exists with a non-null onPressed". CatalogView is reached via
  // context.go in production, so this needs a real GoRouter with two
  // routes, not a bare MaterialApp: build a router already sitting on
  // '/gift/new/1' with the mocked cubit at that route, and a second,
  // independently-markable route at '/person/:personId' to prove the tap
  // actually landed there.
  testWidgets(
      'the back affordance actually navigates to /person/:personId, not '
      'merely a wired-looking button', (tester) async {
    // A CatalogLoaded state, not CatalogLoading: CatalogLoading renders an
    // indeterminate CircularProgressIndicator, which animates forever and
    // makes pumpAndSettle() below time out -- unrelated to the back
    // affordance this test targets. The back button itself is built
    // unconditionally in CatalogView's AppBar regardless of body state.
    whenListen(
      cubit,
      const Stream<CatalogState>.empty(),
      initialState: _loaded(areas: const [], selectedAreaId: null, products: const []),
    );
    final router = GoRouter(
      initialLocation: '/gift/new/1',
      routes: [
        GoRoute(
          path: '/gift/new/:personId',
          builder: (_, state) => BlocProvider<CatalogCubit>.value(
            value: cubit,
            child: CatalogView(
              personId: int.parse(state.pathParameters['personId']!),
            ),
          ),
        ),
        GoRoute(
          path: '/person/:personId',
          builder: (_, state) => Scaffold(
            key: const Key('person_destination'),
            body: Text('person ${state.pathParameters['personId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person_destination')), findsNothing);

    await tester.tap(find.byKey(const Key('catalog_back_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person_destination')), findsOneWidget);
  });

  // 2. The area DropdownButton re-syncs when the cubit re-emits a different
  // selectedAreaId -- the screen's main interaction. Built as a two-state
  // stream (not a manual selectArea() call) so this proves the WIDGET
  // reflects an externally-driven state change, independent of whether
  // selectArea() itself works.
  //
  // Asserted on the DropdownButton widget's own `value` property, not on
  // `find.text('Suburb')`/`find.text('Downtown')`: DropdownButton keeps
  // every item's widget mounted at once (an internal IndexedStack picks
  // which one paints), so BOTH area names are present in the tree
  // regardless of which is selected -- a text-count assertion here would
  // pass unconditionally and prove nothing.
  testWidgets(
      'the area dropdown re-syncs its displayed value when the cubit '
      'emits a new selectedAreaId', (tester) async {
    final before = _loaded(
      areas: [_area(1, 'Downtown'), _area(2, 'Suburb')],
      selectedAreaId: 1,
      products: const [],
    );
    final after = _loaded(
      areas: [_area(1, 'Downtown'), _area(2, 'Suburb')],
      selectedAreaId: 2,
      products: const [],
    );
    // A StreamController under this test's own control, not Stream.value():
    // a single-shot Stream.value() delivers its event as a microtask that
    // fires during pumpWidget() itself (before the "before" assertion below
    // ever runs), so the widget would already be showing `after` at the
    // first check -- proving nothing about a re-sync actually happening
    // later, only that some value round-trips at all.
    final controller = StreamController<CatalogState>();
    addTearDown(controller.close);
    whenListen(cubit, controller.stream, initialState: before);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CatalogCubit>.value(
          value: cubit,
          child: const CatalogView(personId: 1),
        ),
      ),
    );
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('gift_area_dropdown')),
          )
          .value,
      1,
    );

    controller.add(after);
    await tester.pump(); // delivers `after` from the stream
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('gift_area_dropdown')),
          )
          .value,
      2,
    );
  });

  // 3. The CatalogError retry button actually calls load() again -- not
  // just "a button exists".
  testWidgets('the CatalogError retry button calls load() again',
      (tester) async {
    await pumpView(tester, const CatalogError('boom'));

    await tester.tap(find.widgetWithText(FilledButton, AppStrings.retry));
    await tester.pump();

    verify(() => cubit.load(1)).called(1);
  });

  // 4. Tapping a product pushes the real SlotPickerScreen (Amendment A1 --
  // the Task 5 placeholder is gone), carrying the product, the personId,
  // AND the recipient's non-nullable birthday forward (Amendment A2).
  // Asserting on the CATALOG after the push would silently pass for the
  // wrong reason (or find nothing at all): Navigator marks a covered route
  // offstage, and find.text/find.byType default to skipOffstage: true, so
  // the pushed route's own widget is what must be asserted on -- not text
  // rendered from it, which could pass even if the wrong Birthday travelled.
  testWidgets(
      'tapping a product pushes SlotPickerScreen carrying the product, '
      "personId, the recipient's birthday and the recipient's displayName "
      '(fix round 1, item 1)', (tester) async {
    final product = _product(1, name: 'Chocolate Truffle');
    const birthday = Birthday(month: 3, day: 20);
    await pumpView(
      tester,
      _loaded(
        areas: [_area(1, 'Downtown')],
        selectedAreaId: 1,
        products: [product],
        person: _person(1, birthday: birthday, displayName: 'Priya Sharma'),
      ),
    );

    expect(find.byType(SlotPickerScreen), findsNothing);

    await tester.tap(find.text('Chocolate Truffle').first);
    await tester.pumpAndSettle();

    final picker = tester.widget<SlotPickerScreen>(
      find.byType(SlotPickerScreen),
    );
    expect(picker.personId, 1);
    expect(picker.product, same(product));
    expect(picker.birthday, birthday);
    // fix round 1, item 1: CatalogLoaded already carries the whole Person,
    // so its displayName threads straight into the picker rather than
    // DraftScreen later falling back to an id-based label.
    expect(picker.recipientName, 'Priya Sharma');
  });

  // 5 (Amendment A2). CatalogLoaded's birthday-present invariant is
  // asserted, not merely assumed, at the push site: if a CatalogLoaded ever
  // carried a person with no birthday -- which CatalogCubit.load itself
  // never allows into this state, but nothing at the type level forbids --
  // the push must fail loudly (an AssertionError) rather than silently
  // sending a picker forward with no birthday.
  testWidgets(
      'tapping a product with a null-birthday person violates the '
      'CatalogLoaded invariant', (tester) async {
    final product = _product(1, name: 'Chocolate Truffle');
    // Built directly, not via `_person()`: that helper's `birthday ?? const
    // Birthday(...)` default makes a genuinely null birthday unreachable
    // through it.
    const personWithNoBirthday = Person(
      id: 1,
      displayName: 'Person 1',
      isClaimed: false,
    );
    await pumpView(
      tester,
      _loaded(
        areas: [_area(1, 'Downtown')],
        selectedAreaId: 1,
        products: [product],
        person: personWithNoBirthday,
      ),
    );

    await tester.tap(find.text('Chocolate Truffle').first);
    await tester.pump();

    expect(tester.takeException(), isA<AssertionError>());
  });
}
