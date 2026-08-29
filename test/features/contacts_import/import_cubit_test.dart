import 'package:birthday_app/features/contacts_import/import_cubit.dart';
import 'package:birthday_app/features/contacts_import/import_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeContacts implements ContactsRepository {
  _FakeContacts({
    this.permissionGranted = true,
    this.contacts = const [],
    this.resolved = const [],
    this.summary = ImportSummary.empty,
    this.reportProgress = true,
  });

  final bool permissionGranted;
  final List<DeviceContact> contacts;
  final List<ResolvedContact> resolved;
  final ImportSummary summary;
  final bool reportProgress;

  int requestPermissionCalls = 0;
  int readDeviceContactsCalls = 0;
  List<DeviceContact>? lastCommitted;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls++;
    return permissionGranted;
  }

  @override
  Future<List<DeviceContact>> readDeviceContacts({
    String isoCode = 'IN',
  }) async {
    readDeviceContactsCalls++;
    return contacts;
  }

  @override
  Future<List<ResolvedContact>> resolve(List<String> phonesE164) async =>
      resolved;

  @override
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize = 500,
    void Function(int done, int total)? onProgress,
  }) async {
    lastCommitted = contacts;
    if (reportProgress) onProgress?.call(contacts.length, contacts.length);
    return summary;
  }
}

const _c1 = DeviceContact(name: 'Ann', phoneE164: '+919999000001');
const _c2 = DeviceContact(name: 'Bob', phoneE164: '+919999000002');
const _c3 = DeviceContact(name: 'Cy', phoneE164: '+919999000003');
const _c4 = DeviceContact(name: 'Di', phoneE164: '+919999000004');
const _c5 = DeviceContact(name: 'Ed', phoneE164: '+919999000005');

void main() {
  // 1. Permission denied short-circuits to ImportPermissionDenied and never
  //    reads contacts.
  late _FakeContacts deniedFake;
  blocTest<ImportCubit, ImportState>(
    'a denied permission short-circuits without reading contacts',
    build: () {
      deniedFake = _FakeContacts(permissionGranted: false);
      return ImportCubit(deniedFake);
    },
    act: (c) => c.start(),
    expect: () => [
      isA<ImportRequestingPermission>(),
      isA<ImportPermissionDenied>(),
    ],
    verify: (_) => expect(deniedFake.readDeviceContactsCalls, 0),
  );

  // 2. A granted permission loads contacts and lands on ImportPicking with
  //    nothing selected -- opt in, never opt out, for a screen that mints
  //    rows.
  const resolvedAnn = ResolvedContact(
    phone: '+919999000001',
    personId: 7,
    displayName: 'Ann',
    hasBirthday: true,
  );
  blocTest<ImportCubit, ImportState>(
    'a granted permission loads contacts and lands on Picking unselected',
    build: () => ImportCubit(
      _FakeContacts(contacts: const [_c1, _c2], resolved: const [resolvedAnn]),
    ),
    act: (c) => c.start(),
    expect: () => [
      isA<ImportRequestingPermission>(),
      isA<ImportLoadingContacts>(),
      isA<ImportPicking>()
          .having((s) => s.contacts, 'contacts', [_c1, _c2])
          .having((s) => s.resolved, 'resolved', [resolvedAnn])
          .having((s) => s.selected, 'selected', isEmpty),
    ],
  );

  // 3. toggle() adds and removes a phone from the selection.
  blocTest<ImportCubit, ImportState>(
    'toggle adds then removes a phone from the selection',
    build: () => ImportCubit(_FakeContacts(contacts: const [_c1, _c2])),
    act: (c) async {
      await c.start();
      c.toggle(_c1.phoneE164);
      c.toggle(_c1.phoneE164);
    },
    skip: 3, // ImportRequestingPermission, ImportLoadingContacts, Picking({})
    expect: () => [
      isA<ImportPicking>().having((s) => s.selected, 'selected', {
        _c1.phoneE164,
      }),
      isA<ImportPicking>().having((s) => s.selected, 'selected', isEmpty),
    ],
  );

  // 4. commit() sends ONLY the selected contacts, not the whole address
  //    book. This is the "create on select" decision from the parent spec
  //    §3: a person row must not be minted for a non-consenting contact.
  //    Built with 5 device contacts, select 2, commit, and assert the fake
  //    recorded exactly 2.
  test('commit sends only the picked contacts, not the whole address book',
      () async {
    final fake = _FakeContacts(
      contacts: const [_c1, _c2, _c3, _c4, _c5],
    );
    final cubit = ImportCubit(fake);
    await cubit.start();
    cubit.toggle(_c2.phoneE164);
    cubit.toggle(_c4.phoneE164);
    await cubit.commit();

    expect(fake.lastCommitted, hasLength(2));
    expect(
      fake.lastCommitted!.map((c) => c.phoneE164).toSet(),
      {_c2.phoneE164, _c4.phoneE164},
    );
  });

  // 5. commit() emits ImportCommitting with the progress the repository
  //    reports, then ImportDone carrying the summary.
  blocTest<ImportCubit, ImportState>(
    'commit reports the repository\'s progress then ImportDone',
    build: () => ImportCubit(
      _FakeContacts(
        contacts: const [_c1, _c2],
        summary: const ImportSummary(
          added: 2,
          skipped: 0,
          failed: 0,
          duplicates: 0,
          results: [
            ImportOutcome(
              phone: '+919999000001',
              personId: 1,
              status: ImportStatus.added,
            ),
            ImportOutcome(
              phone: '+919999000002',
              personId: 2,
              status: ImportStatus.added,
            ),
          ],
        ),
      ),
    ),
    act: (c) async {
      await c.start();
      c.toggle(_c1.phoneE164);
      c.toggle(_c2.phoneE164);
      await c.commit();
    },
    skip: 5, // RequestingPermission, LoadingContacts, Picking x3 (empty + 2 toggles)
    expect: () => [
      isA<ImportCommitting>()
          .having((s) => s.done, 'done', 2)
          .having((s) => s.total, 'total', 2),
      isA<ImportDone>().having((s) => s.summary.added, 'added', 2),
    ],
  );

  // A repository that never calls onProgress (e.g. a batch too small to
  // chunk) must still land on ImportDone -- ImportCommitting is a courtesy
  // from the repository, not something commit() waits to see.
  blocTest<ImportCubit, ImportState>(
    'commit still reaches ImportDone if the repository reports no progress',
    build: () => ImportCubit(
      _FakeContacts(contacts: const [_c1], reportProgress: false),
    ),
    act: (c) async {
      await c.start();
      c.toggle(_c1.phoneE164);
      await c.commit();
    },
    skip: 3, // RequestingPermission, LoadingContacts, Picking({}) from start
    expect: () => [
      isA<ImportPicking>(), // toggle
      isA<ImportDone>(),
    ],
  );

  // 6. setBirthday attaches a birthday to a selected contact before commit.
  test('setBirthday attaches a birthday to the committed contact', () async {
    const birthday = Birthday(month: 4, day: 15);
    final fake = _FakeContacts(contacts: const [_c1]);
    final cubit = ImportCubit(fake);
    await cubit.start();
    cubit.toggle(_c1.phoneE164);
    cubit.setBirthday(_c1.phoneE164, birthday);
    await cubit.commit();

    expect(fake.lastCommitted, hasLength(1));
    expect(fake.lastCommitted!.single.birthday, birthday);
  });
}
