
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/ops/ops_router.dart';
import 'package:birthday_app/ops/signin/signin_cubit.dart';
import 'package:birthday_app/ops/signin/signin_screen.dart';
import 'package:birthday_app/repositories/staff_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

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
      BlocProvider.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router),
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
    expect(find.byType(OpsCatalogPlaceholder), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('a NON-staff caller is refused and stays at sign-in',
      (tester) async {
    final cubit = await pumpConsole(tester, staff: false);

    await cubit.submit(email: 'nobody@example.com', password: 'pw');
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text(AppStrings.opsNotStaff), findsOneWidget);
    expect(find.byType(OpsCatalogPlaceholder), findsNothing);
  });

  testWidgets('an unknown location renders the error page, with a way back',
      (tester) async {
    final cubit = SignInCubit(_FakeStaffAuth(staff: true));
    final router = buildOpsRouter(cubit);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router),
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

    expect(find.byType(OpsCatalogPlaceholder), findsOneWidget);
  });
}
