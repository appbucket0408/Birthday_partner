@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:birthday_app/repositories/graph_repository.dart';
import 'package:birthday_app/repositories/graph_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/graph_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late GraphRepository graph;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    graph = GraphRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number, per the task-11 phone pool assignment.
  const primary = '+919999000004';

  // A member who sets their own birthday needs a person who has genuinely
  // claimed a profile, and claiming only ever happens for a real,
  // OTP-verified account's OWN person row -- there is no service-role
  // shortcut for it in the client surface this repository exposes. That requires a second real
  // identity distinct from `primary`, which the task-11 brief's phone table
  // does not allocate (it gives this suite exactly one number). This is a
  // gap in that table, not a deliberate omission -- see task-11-report.md.
  // '...006 is picked to stay clear of every number the brief DOES assign
  // (auth: 001/002, contacts: 003, graph: 004, settings: 005).
  const second = '+919999000006';

  final otpThrottle = OtpSendThrottle();
  Future<void> signIn(String phone) async {
    await otpThrottle.run(() => auth.sendOtp(phone));
    await auth.verifyOtp(phoneE164: phone, token: '123456');
  }

  setUp(() async {
    await signIn(primary);
    await auth.claimProfile();
  });

  // Always deletes whichever account is signed in when the test ends. Every
  // test below signs back into `primary` as its last auth step before
  // finishing, so this always tears down `primary`, never `second` --
  // `second` is deliberately left alive across the whole suite (see
  // `asSecondUsersPerson` below).
  tearDown(() => auth.deleteAccount().catchError((_) {}));

  // Signs into `second`, has it claim its own person row and set its OWN
  // birthday (both idempotent, so safe to call from more than one test), and
  // leaves that account NOT deleted -- deleting it would scrub and
  // phone-hash-rotate the very row these tests need to stay claimed and
  // findable. Returns to `primary` before returning, since every test's own
  // tearDown expects `primary` to be the active session.
  const secondBirthday = Birthday(month: 8, day: 9, year: 1995);
  Future<int> asSecondUsersPerson() async {
    await auth.signOut();
    await signIn(second);
    final personId = await auth.claimProfile();
    await auth.completeProfile(
      handle: 'graph_second',
      displayName: 'Graph Second',
      city: 'Jaipur',
      birthday: secondBirthday,
    );
    await auth.signOut();
    await signIn(primary);
    await auth.claimProfile();
    return personId;
  }

  test('celebrations returns the edges this user owns, person embedded',
      () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Edge One', phoneE164: '+919999444401'),
    ]);
    final personId = summary.results.single.personId;

    final rows = await graph.celebrations();

    expect(rows.any((c) => c.person.id == personId), isTrue);
    final row = rows.firstWhere((c) => c.person.id == personId);
    expect(row.person.displayName, 'Edge One');
    expect(row.person.isClaimed, isFalse);
  });

  // Only a person sets their own birthday (20261017000003). What a
  // celebrator sees is exactly what the member entered on their profile --
  // there is no longer any call that lets the celebrator change it.
  test("a member's birthday is the one they set themselves", () async {
    final secondPersonId = await asSecondUsersPerson();

    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Whatever I Call Them', phoneE164: second),
    ]);
    expect(summary.results.single.personId, secondPersonId);

    final row = (await graph.celebrations())
        .firstWhere((c) => c.person.id == secondPersonId);
    expect(row.person.isClaimed, isTrue);
    expect(row.person.birthday, secondBirthday);
    // Their own name, not the one in the importer's address book.
    expect(row.person.displayName, 'Graph Second');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('the removed birthday-edit call no longer exists', () async {
    await expectLater(
      ApiClient.instance.rpc('rpc_update_person_birthday', params: {
        'p_person_id': 1,
        'p_birth_month': 1,
        'p_birth_day': 1,
        'p_birth_year': null,
      }),
      throwsA(anything),
    );
  });

  test('stopCelebrating removes the edge; celebrations no longer returns it',
      () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Soon Gone', phoneE164: '+919999444404'),
    ]);
    final personId = summary.results.single.personId!;
    final before = await graph.celebrations();
    final celebrationId = before.firstWhere((c) => c.person.id == personId).id;

    await graph.stopCelebrating(celebrationId);

    final after = await graph.celebrations();
    expect(after.any((c) => c.person.id == personId), isFalse);
  });

  test("celebrations shows each person by their own name", () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Formal Name', phoneE164: '+919999444405'),
    ]);
    final personId = summary.results.single.personId!;

    final row = (await graph.celebrations())
        .firstWhere((c) => c.person.id == personId);
    expect(row.person.displayName, 'Formal Name');
  });
}
