import 'package:birthday_app/features/contacts_import/import_cubit.dart';
import 'package:birthday_app/features/contacts_import/import_state.dart';
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
    this.readDeviceContactsError,
  });

  final bool permissionGranted;
  final List<DeviceContact> contacts;
  final List<ResolvedContact> resolved;
  final ImportSummary summary;
  final bool reportProgress;
  final Object? readDeviceContactsError;

  int requestPermissionCalls = 0;
  int readDeviceContactsCalls = 0;
  int addCelebrationsCalls = 0;
  String? lastIsoCode;
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
    lastIsoCode = isoCode;
    if (readDeviceContactsError != null) throw readDeviceContactsError!;
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
    addCelebrationsCalls++;
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
    isMember: true,
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

  // I1: start() had no error handling at all -- a failure of
  // readDeviceContacts (or requestPermission/resolve) left the cubit stuck
  // in ImportLoadingContacts forever, which the disclosure screen renders
  // as a permanently-disabled spinner with no error and no retry. It must
  // instead land on ImportFailed, same as commit()'s existing catch-all.
  blocTest<ImportCubit, ImportState>(
    'a throwing readDeviceContacts lands on ImportFailed, not stuck loading',
    build: () => ImportCubit(
      _FakeContacts(readDeviceContactsError: Exception('device error')),
    ),
    act: (c) => c.start(),
    expect: () => [
      isA<ImportRequestingPermission>(),
      isA<ImportLoadingContacts>(),
      isA<ImportFailed>(),
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

  // A second commit() fired before the first resolves (a fast double-tap on
  // add_selected / fill_continue / summary_retry) must not run two
  // concurrent addCelebrations calls -- the cubit, not any of its three
  // trigger buttons, is the source of truth for what is in flight. Mirrors
  // PhoneCubit.submitCode (Task 7) and ProfileSetupCubit.submit (Task 8).
  test('a second commit call while committing is ignored', () async {
    final fake = _FakeContacts(contacts: const [_c1]);
    final cubit = ImportCubit(fake);
    await cubit.start();
    cubit.toggle(_c1.phoneE164);

    final first = cubit.commit();
    final second = cubit.commit();
    await Future.wait([first, second]);

    expect(fake.addCelebrationsCalls, 1);
  });

  // 6. Only a person sets their own birthday: what is committed is the
  //    contact's name and number, nothing else.
  test('commit sends only the name and number of the picked contact',
      () async {
    final fake = _FakeContacts(contacts: const [_c1]);
    final cubit = ImportCubit(fake);
    await cubit.start();
    cubit.toggle(_c1.phoneE164);
    await cubit.commit();

    final sent = fake.lastCommitted!.single;
    expect(sent.name, _c1.name);
    expect(sent.phoneE164, _c1.phoneE164);
  });

  // The region derivation: the signed-in user's own verified phone (minus
  // its leading '+', as Supabase stores it) decides the isoCode passed to
  // readDeviceContacts. currentUserPhone is injected so none of these
  // touch the Supabase singleton.
  group('region derivation from the signed-in user\'s own phone', () {
    Future<String?> isoCodeFor(String? phone) async {
      final fake = _FakeContacts();
      final cubit = ImportCubit(fake, currentUserPhone: () => phone);
      await cubit.start();
      return fake.lastIsoCode;
    }

    test('a +91 number derives IN', () async {
      // Supabase stores the phone without the leading '+'.
      expect(await isoCodeFor('919999000001'), 'IN');
    });

    test('a +1 number derives US', () async {
      expect(await isoCodeFor('12025550123'), 'US');
    });

    test('an unparseable phone falls back to IN', () async {
      expect(await isoCodeFor('not-a-phone'), 'IN');
    });

    test('no signed-in phone falls back to IN', () async {
      expect(await isoCodeFor(null), 'IN');
    });
  });
}
