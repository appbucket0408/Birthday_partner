@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:birthday_app/repositories/person_repository.dart';
import 'package:birthday_app/repositories/person_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/person_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late PersonRepository person;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    person = PersonRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number -- every contract suite owns one because
  // `flutter test` runs files concurrently and a shared OTP identity
  // produces failures in files this task never touched.
  const primary = '+919999000007';

  final otpThrottle = OtpSendThrottle();
  Future<void> signIn(String phone) async {
    await otpThrottle.run(() => auth.sendOtp(phone));
    await auth.verifyOtp(phoneE164: phone, token: '123456');
  }

  setUp(() async {
    await signIn(primary);
    await auth.claimProfile();
  });

  tearDown(() => auth.deleteAccount().catchError((_) {}));

  test('person() returns a person the caller celebrates, with their birthday',
      () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(
        name: 'Visible Person',
        phoneE164: '+919999444501',
      ),
    ]);
    final personId = summary.results.single.personId!;

    final row = await person.person(personId);

    expect(row.id, personId);
    expect(row.displayName, 'Visible Person');
  });

  test('celebratorCount() returns 1 for a person only the caller celebrates',
      () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Counted Person', phoneE164: '+919999444502'),
    ]);
    final personId = summary.results.single.personId!;

    final count = await person.celebratorCount(personId);

    expect(count, 1);
  });

  test(
      'person() on a person the caller does not celebrate throws an '
      'AppFailure', () async {
    // A person id the caller holds no edge to and does not own. people.id is
    // a sequential bigint; a fresh account's own claimed id plus a large
    // offset lands well past anything this suite has minted, and is not
    // guaranteed to exist -- either way the row is invisible to `primary`.
    // Observed (task-4-report.md): PostgREST answers PGRST116 ("Cannot
    // coerce the result to a single JSON object" / 0 rows) via .single(),
    // not a class-45 code -- mapError wraps it as a ServerFailure, still an
    // AppFailure, which is the only claim this assertion makes.
    const invisiblePersonId = 999999999;

    await expectLater(
      person.person(invisiblePersonId),
      throwsA(isA<AppFailure>()),
    );
  });

  test(
      'celebratorCount() on a person the caller does not celebrate throws '
      "ServerFailure with code '45004'", () async {
    const invisiblePersonId = 999999999;

    await expectLater(
      person.celebratorCount(invisiblePersonId),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '45004')),
    );
  });
}
