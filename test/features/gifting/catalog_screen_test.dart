import 'dart:async';

import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/gifting/catalog_cubit.dart';
import 'package:birthday_app/features/gifting/catalog_screen.dart';
import 'package:birthday_app/features/gifting/catalog_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/person.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// A mocked CatalogCubit -- same pattern as
/// test/features/person/person_screen_test.dart's `_MockPersonCubit`. Lets
/// each test drop straight into the exact state it wants, and lets the
/// retry/dropdown/push tests verify which cubit methods were actually
/// called, not just that a tap didn't crash.
class _MockCatalogCubit extends MockCubit<CatalogState>
    implements CatalogCubit {}

Person _person(int id, {Birthday? birthday}) => Person(
      id: id,
      displayName: 'Person $id',
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
}) =>
    CatalogLoaded(
      person: _person(1),
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
  /// need `context.go` to actually resolve anywhere.
  Future<void> pumpView(WidgetTester tester, CatalogState state) async {
    whenListen(cubit, const Stream<CatalogState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CatalogCubit>.value(
          value: cubit,
          child: const CatalogView(personId: 1),
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

  // 4. Tapping a product pushes the slot picker, carrying the product
  // forward. Asserting on the CATALOG after the push would silently pass
  // for the wrong reason (or find nothing at all): Navigator marks a
  // covered route offstage, and find.text/find.byType default to
  // skipOffstage: true, so the pushed route is what must be asserted on.
  testWidgets('tapping a product pushes the slot picker with the product',
      (tester) async {
    final product = _product(1, name: 'Chocolate Truffle');
    await pumpView(
      tester,
      _loaded(
        areas: [_area(1, 'Downtown')],
        selectedAreaId: 1,
        products: [product],
      ),
    );

    expect(find.textContaining('coming in a later task'), findsNothing);

    await tester.tap(find.text('Chocolate Truffle').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Delivery windows for Chocolate Truffle'),
      findsOneWidget,
    );
  });
}
