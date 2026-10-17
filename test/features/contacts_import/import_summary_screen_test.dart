import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/contacts_import/import_cubit.dart';
import 'package:birthday_app/features/contacts_import/import_summary_screen.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hands back a fixed summary from the commit, so the screen can be shown
/// in the ImportDone state through the real cubit.
class _FakeContacts implements ContactsRepository {
  _FakeContacts(this.summary);

  final ImportSummary summary;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<DeviceContact>> readDeviceContacts({
    String isoCode = 'IN',
  }) async =>
      const [DeviceContact(name: 'Ann', phoneE164: '+919999000010')];

  @override
  Future<List<ResolvedContact>> resolve(List<String> phonesE164) async =>
      const [];

  @override
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize = 500,
    void Function(int done, int total)? onProgress,
  }) async =>
      summary;
}

ImportSummary _summary({
  int added = 0,
  int skipped = 0,
  int failed = 0,
  int duplicates = 0,
}) =>
    ImportSummary(
      added: added,
      skipped: skipped,
      failed: failed,
      duplicates: duplicates,
      results: const [],
    );

Future<void> _pump(WidgetTester tester, ImportSummary summary) async {
  final cubit = ImportCubit(_FakeContacts(summary), currentUserPhone: () => null);
  await cubit.start();
  cubit.toggle('+919999000010');
  await cubit.commit();
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: const ImportSummaryScreen(),
      ),
    ),
  );
}

Finder _title(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.key == const Key('summary_title') && w.data == text,
    );

void main() {
  testWidgets('a success says how many, and hides the zero lines',
      (tester) async {
    await _pump(tester, _summary(added: 3));

    expect(
      _title(AppStrings.importAddedManyTemplate.replaceFirst('%s', '3')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.importAddedBody), findsOneWidget);
    expect(find.textContaining('already in your list'), findsNothing);
    expect(find.textContaining('skipped'), findsNothing);
  });

  testWidgets('non-zero details are shown', (tester) async {
    await _pump(tester, _summary(added: 1, duplicates: 2, skipped: 1));

    expect(_title(AppStrings.importAddedOne), findsOneWidget);
    expect(
      find.text(AppStrings.importDuplicatesTemplate.replaceFirst('%s', '2')),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.importSkippedTemplate.replaceFirst('%s', '1')),
      findsOneWidget,
    );
  });

  testWidgets('everyone already listed reads as such, not "0 added"',
      (tester) async {
    await _pump(tester, _summary(duplicates: 2));

    expect(_title(AppStrings.importAddedNone), findsOneWidget);
    expect(find.text(AppStrings.importAddedNoneBody), findsOneWidget);
  });

  testWidgets('a failure gets its own headline and a retry', (tester) async {
    await _pump(tester, _summary(failed: 2));

    expect(_title(AppStrings.importAddedFailed), findsOneWidget);
    expect(find.byKey(const Key('summary_retry')), findsOneWidget);
  });

  // The import already happened; back would invite adding everyone again.
  testWidgets('there is no back arrow, only Done', (tester) async {
    await _pump(tester, _summary(added: 1));

    expect(find.byType(BackButton), findsNothing);
    expect(find.byKey(const Key('summary_done')), findsOneWidget);
  });
}
