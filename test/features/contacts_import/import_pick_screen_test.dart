import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/contacts_import/import_cubit.dart';
import 'package:birthday_app/features/contacts_import/import_pick_screen.dart';
import 'package:birthday_app/features/contacts_import/import_state.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real ImportCubit, not a mock: the screen is exercised through the real
/// toggle()/state machinery, following the pattern in
/// test/features/onboarding/phone_screen_test.dart.
class _FakeContacts implements ContactsRepository {
  _FakeContacts(this.contacts, this.resolved);

  final List<DeviceContact> contacts;
  final List<ResolvedContact> resolved;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<DeviceContact>> readDeviceContacts({
    String isoCode = 'IN',
  }) async =>
      contacts;

  @override
  Future<List<ResolvedContact>> resolve(List<String> phonesE164) async =>
      resolved;

  @override
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize = 500,
    void Function(int done, int total)? onProgress,
  }) async =>
      ImportSummary.empty;
}

const _onApp = DeviceContact(name: 'Ann On App', phoneE164: '+919999000010');
const _offApp = DeviceContact(name: 'Bob Off App', phoneE164: '+919999000011');

void main() {
  Future<ImportCubit> pump(WidgetTester tester) async {
    final fake = _FakeContacts(
      const [_onApp, _offApp],
      const [
        ResolvedContact(
          phone: '+919999000010',
          personId: 1,
          displayName: 'Ann',
        ),
      ],
    );
    final cubit = ImportCubit(fake);
    await cubit.start();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<ImportCubit>.value(
          value: cubit,
          child: const ImportPickScreen(),
        ),
      ),
    );
    return cubit;
  }

  // 1. Nothing is selected on first render.
  testWidgets('nothing is selected on first render', (tester) async {
    await pump(tester);

    final checkboxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(checkboxes, hasLength(2));
    expect(checkboxes.every((c) => c.value == false), isTrue);
  });

  // 2. The Add button is disabled with an empty selection and enabled after
  //    a tap.
  testWidgets('the Add button is disabled empty, enabled after a tap', (
    tester,
  ) async {
    await pump(tester);

    FilledButton addButton() =>
        tester.widget<FilledButton>(find.byKey(const Key('add_selected')));

    expect(addButton().onPressed, isNull);

    await tester.tap(find.byKey(Key('contact_${_onApp.phoneE164}')));
    await tester.pump();

    expect(addButton().onPressed, isNotNull);
  });

  // 3. A contact present in the resolved set shows the importOnApp badge
  //    and one absent from it does not.
  testWidgets(
    'a resolved contact shows the on-app badge, an unresolved one does not',
    (tester) async {
      await pump(tester);

      final onAppTile = find.byKey(Key('contact_${_onApp.phoneE164}'));
      final offAppTile = find.byKey(Key('contact_${_offApp.phoneE164}'));

      expect(
        find.descendant(
          of: onAppTile,
          matching: find.text(AppStrings.importOnApp),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: offAppTile,
          matching: find.text(AppStrings.importOnApp),
        ),
        findsNothing,
      );
    },
  );

  // 4. Tapping a row calls toggle() with that contact's phone.
  testWidgets('tapping a row toggles that contact\'s phone', (tester) async {
    final cubit = await pump(tester);

    await tester.tap(find.byKey(Key('contact_${_offApp.phoneE164}')));
    await tester.pump();

    final state = cubit.state;
    expect(state, isA<ImportPicking>());
    expect(
      (state as ImportPicking).selected,
      {_offApp.phoneE164},
    );

    // Tapping the same row again calls toggle() a second time, removing it
    // -- confirming the row is wired to toggle() and not to a one-way
    // "select" action.
    await tester.tap(find.byKey(Key('contact_${_offApp.phoneE164}')));
    await tester.pump();
    expect((cubit.state as ImportPicking).selected, isEmpty);
  });
}
