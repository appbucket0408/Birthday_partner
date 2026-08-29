@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
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

  // Proving 45002 and 45003 needs a person who has genuinely claimed a
  // profile, and claiming only ever happens for a real, OTP-verified
  // account's OWN person row -- there is no service-role shortcut for it in
  // the client surface this repository exposes. That requires a second real
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

  // Signs into `second`, has it claim its own person row (idempotent, so
  // safe to call from more than one test), and leaves that account signed
  // in but NOT deleted -- deleting it would scrub and phone-hash-rotate the
  // very row these tests need to stay claimed and findable. Returns to
  // `primary` before returning, since every test's own tearDown expects
  // `primary` to be the active session.
  Future<int> asSecondUsersPerson() async {
    await signIn(second);
    final personId = await auth.claimProfile();
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

  test(
      'updateBirthday sets a birthday on an unclaimed person, and '
      'celebrations reflects it', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'No Birthday Yet', phoneE164: '+919999444402'),
    ]);
    final personId = summary.results.single.personId!;

    await graph.updateBirthday(personId, const Birthday(month: 6, day: 20));

    final rows = await graph.celebrations();
    final row = rows.firstWhere((c) => c.person.id == personId);
    expect(row.person.birthday, const Birthday(month: 6, day: 20));
  });

  test(
      'updateBirthday on a person this user does not celebrate throws '
      "ServerFailure with code '45002'", () async {
    // `second` claims its own person row. `primary` never adds `second` as
    // a contact in this test, so `primary` holds no celebration edge to it.
    final secondPersonId = await asSecondUsersPerson();

    await expectLater(
      graph.updateBirthday(secondPersonId, const Birthday(month: 3, day: 3)),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '45002')),
    );
  });

  test(
      'updateBirthday on a claimed person throws ServerFailure with code '
      "'45003' -- their own birthday wins", () async {
    final secondPersonId = await asSecondUsersPerson();

    // Give `primary` a real edge to the already-claimed person, by adding
    // `second`'s own phone number as a contact. This resolves to the
    // existing, claimed row rather than minting a new one.
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Second User', phoneE164: second),
    ]);
    expect(summary.results.single.personId, secondPersonId);

    await expectLater(
      graph.updateBirthday(secondPersonId, const Birthday(month: 3, day: 3)),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '45003')),
    );
  });

  test(
      'an impossible date throws ServerFailure with code '
      "'23514' -- security definer does not bypass the CHECK constraint",
      () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'April Fool', phoneE164: '+919999444403'),
    ]);
    final personId = summary.results.single.personId!;

    await expectLater(
      // April has 30 days -- April 31 does not exist in any year.
      graph.updateBirthday(personId, const Birthday(month: 4, day: 31)),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '23514')),
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

  test(
      'updateNickname changes the label; celebrations prefers the nickname '
      "over the person's display name", () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Formal Name', phoneE164: '+919999444405'),
    ]);
    final personId = summary.results.single.personId!;
    final before = await graph.celebrations();
    final celebrationId = before.firstWhere((c) => c.person.id == personId).id;

    await graph.updateNickname(celebrationId, 'Buddy');

    final after = await graph.celebrations();
    final row = after.firstWhere((c) => c.person.id == personId);
    expect(row.nickname, 'Buddy');
    expect(row.label, 'Buddy');
  });
}
