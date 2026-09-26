
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/ops/catalog/ops_catalog_screen.dart';
import 'package:birthday_app/ops/ops_router.dart';
import 'package:birthday_app/ops/signin/signin_cubit.dart';
import 'package:birthday_app/ops/signin/signin_screen.dart';
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:birthday_app/models/product.dart';
import 'package:birthday_app/models/service_area.dart';
import 'package:birthday_app/repositories/ops_repository.dart';
import 'package:birthday_app/repositories/staff_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// The router now routes to the REAL OpsCatalogScreen, which reads an
/// OpsRepository off context. Before Task 4 it routed to a placeholder that
/// read nothing, so this provider was not needed -- swapping a placeholder
/// for a real screen changes what the router's own tree must supply.
class _FakeOps implements OpsRepository {
  @override
  Future<List<ServiceArea>> allServiceAreas() async => const [];

  @override
  Future<List<Product>> allProductsIn(int serviceAreaId) async => const [];

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

  @override
  Future<List<DeliverySlot>> slotsBetween(
    int serviceAreaId, {
    required DateTime from,
    required DateTime to,
  }) async =>
      const [];

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

class _FakeStaffAuth implements StaffAuthRepository {
  _FakeStaffAuth({this.staff = true});
  bool staff;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isStaff() async => staff;
}

/// Asserts ARRIVAL through the REAL buildOpsRouter, never an inline test
/// router. M3 Phase 1b shipped a live dead end precisely because the test
/// that "proved" the button worked built its own router with its own route
/// declared inline, so the production router was never exercised.
void main() {
  Future<SignInCubit> pumpConsole(
    WidgetTester tester, {
    required bool staff,
  }) async {
    final cubit = SignInCubit(_FakeStaffAuth(staff: staff));
    final router = buildOpsRouter(cubit);

    await tester.pumpWidget(
      RepositoryProvider<OpsRepository>.value(
        value: _FakeOps(),
        child: BlocProvider.value(
          value: cubit,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('an unauthenticated caller starts at sign-in', (tester) async {
    await pumpConsole(tester, staff: false);

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a signed-in STAFF caller is admitted to the catalog',
      (tester) async {
    final cubit = await pumpConsole(tester, staff: true);

    await cubit.submit(email: 'ops@example.com', password: 'pw');
    await tester.pumpAndSettle();

    // Arrival, not "a button exists": the redirect must actually move them.
    expect(find.byType(OpsCatalogScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('a NON-staff caller is refused and stays at sign-in',
      (tester) async {
    final cubit = await pumpConsole(tester, staff: false);

    await cubit.submit(email: 'nobody@example.com', password: 'pw');
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text(AppStrings.opsNotStaff), findsOneWidget);
    expect(find.byType(OpsCatalogScreen), findsNothing);
  });

  testWidgets('an unknown location renders the error page, with a way back',
      (tester) async {
    final cubit = SignInCubit(_FakeStaffAuth(staff: true));
    final router = buildOpsRouter(cubit);

    await tester.pumpWidget(
      RepositoryProvider<OpsRepository>.value(
        value: _FakeOps(),
        child: BlocProvider.value(
          value: cubit,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await cubit.submit(email: 'ops@example.com', password: 'pw');
    await tester.pumpAndSettle();

    router.go('/does-not-exist');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.opsNotFound), findsOneWidget);

    // The way back must WORK, not merely render -- an unmatched location
    // with an unusable button is still a dead end.
    await tester.tap(find.byKey(const Key('ops_error_home')));
    await tester.pumpAndSettle();

    expect(find.byType(OpsCatalogScreen), findsOneWidget);
  });
}
