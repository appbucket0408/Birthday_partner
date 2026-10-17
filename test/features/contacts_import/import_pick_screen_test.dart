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
// Has a person row (someone else imported them) but never joined: NOT on
// Birthday, whatever the lookup found.
const _importedOnly =
    DeviceContact(name: 'Cid Imported', phoneE164: '+919999000012');

void main() {
  Future<ImportCubit> pump(
    WidgetTester tester, {
    Set<int> alreadyCelebrating = const {},
  }) async {
    final fake = _FakeContacts(
      const [_onApp, _offApp, _importedOnly],
      const [
        ResolvedContact(
          phone: '+919999000010',
          personId: 1,
          displayName: 'Ann',
          isMember: true,
        ),
        ResolvedContact(
          phone: '+919999000012',
          personId: 3,
          displayName: 'Cid',
          isMember: false,
        ),
      ],
    );
    final cubit = ImportCubit(
      fake,
      currentUserPhone: () => null,
      alreadyCelebrating: () async => alreadyCelebrating,
    );
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

  FilledButton addButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('add_selected')));

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  testWidgets('nothing is selected on first render', (tester) async {
    await pump(tester);

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes, hasLength(3));
    expect(boxes.every((c) => c.value == false), isTrue);
  });

  testWidgets('the button says what it will do, and counts the selection',
      (tester) async {
    await pump(tester);
    expect(addButton(tester).onPressed, isNull);
    expect(find.text(AppStrings.importSelectPrompt), findsOneWidget);

    await tester.tap(find.byKey(Key('contact_${_onApp.phoneE164}')));
    await tester.pump();
    expect(addButton(tester).onPressed, isNotNull);
    expect(find.text(AppStrings.importAddOne), findsOneWidget);

    await tester.tap(find.byKey(Key('contact_${_offApp.phoneE164}')));
    await tester.pump();
    expect(
      find.text(AppStrings.importAddManyTemplate.replaceFirst('%s', '2')),
      findsOneWidget,
    );
  });

  testWidgets(
      'only members are "On Birthday"; an imported-only number is not',
      (tester) async {
    await pump(tester);

    final onAppHeader = find.byKey(const Key('import_section_on_app'));
    final offAppHeader = find.byKey(const Key('import_section_not_on_app'));
    Finder row(DeviceContact c) => find.byKey(Key('contact_${c.phoneE164}'));

    expect(top(tester, onAppHeader), lessThan(top(tester, row(_onApp))));
    expect(top(tester, row(_onApp)), lessThan(top(tester, offAppHeader)));
    expect(top(tester, offAppHeader), lessThan(top(tester, row(_offApp))));
    expect(top(tester, offAppHeader), lessThan(top(tester, row(_importedOnly))));
  });

  testWidgets('someone already celebrated is marked, not offered again',
      (tester) async {
    await pump(tester, alreadyCelebrating: {1});

    expect(find.byKey(Key('already_${_onApp.phoneE164}')), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('Select all picks every addable contact in that section',
      (tester) async {
    final cubit = await pump(tester);

    await tester.tap(find.byKey(const Key('import_select_all_not_on_app')));
    await tester.pump();

    expect(
      (cubit.state as ImportPicking).selected,
      {_offApp.phoneE164, _importedOnly.phoneE164},
    );
    expect(find.text(AppStrings.importClearAll), findsOneWidget);
  });

  testWidgets('numbers are shown readably', (tester) async {
    await pump(tester);
    expect(find.text('+91 99990 00010'), findsOneWidget);
  });

  testWidgets('search narrows the list by name', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(const Key('import_search')), 'bob');
    await tester.pump();

    expect(find.text('Bob Off App'), findsOneWidget);
    expect(find.text('Ann On App'), findsNothing);
  });

  testWidgets('tapping a row toggles that contact\'s phone', (tester) async {
    final cubit = await pump(tester);

    await tester.tap(find.byKey(Key('contact_${_offApp.phoneE164}')));
    await tester.pump();

    expect((cubit.state as ImportPicking).selected, {_offApp.phoneE164});
  });
}
