import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/contacts_import/import_cubit.dart';
import 'package:birthday_app/features/contacts_import/import_disclosure_screen.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeContacts implements ContactsRepository {
  _FakeContacts({this.granted = true});

  final bool granted;
  int permissionCalls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return granted;
  }

  @override
  Future<List<DeviceContact>> readDeviceContacts({
    String isoCode = 'IN',
  }) async =>
      const [];

  @override
  Future<List<ResolvedContact>> resolve(List<String> phonesE164) async =>
      const [];

  @override
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize = 500,
    void Function(int done, int total)? onProgress,
  }) async =>
      ImportSummary.empty;
}

Future<_FakeContacts> _pump(WidgetTester tester, {bool granted = true}) async {
  final fake = _FakeContacts(granted: granted);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => ImportCubit(fake, currentUserPhone: () => null),
        child: const ImportDisclosureView(),
      ),
    ),
  );
  return fake;
}

void main() {
  testWidgets('states what is read and why, plus the three promises',
      (tester) async {
    await _pump(tester);

    // Play's prominent disclosure: on this screen, before the prompt.
    expect(find.text(AppStrings.importDisclosureBody), findsOneWidget);
    for (final t in [
      AppStrings.importTrustStaysTitle,
      AppStrings.importTrustSharedTitle,
      AppStrings.importTrustChooseTitle,
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.byKey(const Key('import_close')), findsOneWidget);
  });

  // The permission API must not be touched until Continue is pressed.
  testWidgets('nothing asks for permission until Continue', (tester) async {
    final fake = await _pump(tester);
    expect(fake.permissionCalls, 0);

    await tester.tap(find.byKey(const Key('import_continue')));
    await tester.pump();
    expect(fake.permissionCalls, 1);
  });

  testWidgets('a denied permission shows the explanation in an error box',
      (tester) async {
    await _pump(tester, granted: false);

    await tester.tap(find.byKey(const Key('import_continue')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('import_error')),
        matching: find.text(AppStrings.importPermissionDenied),
      ),
      findsOneWidget,
    );
  });
}
