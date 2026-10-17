import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/contacts_import/import_cubit.dart';
import 'package:birthday_app/features/contacts_import/import_pick_screen.dart';
import 'package:birthday_app/features/contacts_import/import_state.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

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

  // 3. Contacts are split by whether they are already on the app, each
  //    section saying what adding them will (and will not) give you.
  testWidgets(
    'contacts on the app and not on it are in separate, explained sections',
    (tester) async {
      await pump(tester);

      final onAppHeader = find.byKey(const Key('import_section_on_app'));
      final offAppHeader = find.byKey(const Key('import_section_not_on_app'));
      expect(
        find.descendant(
          of: onAppHeader,
          matching: find.text(AppStrings.importOnAppHint),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: offAppHeader,
          matching: find.text(AppStrings.importNotOnAppHint),
        ),
        findsOneWidget,
      );

      double top(Finder f) => tester.getTopLeft(f).dy;
      final onAppTile = find.byKey(Key('contact_${_onApp.phoneE164}'));
      final offAppTile = find.byKey(Key('contact_${_offApp.phoneE164}'));
      // On-app first, each contact under its own section's header.
      expect(top(onAppHeader), lessThan(top(onAppTile)));
      expect(top(onAppTile), lessThan(top(offAppHeader)));
      expect(top(offAppHeader), lessThan(top(offAppTile)));
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
