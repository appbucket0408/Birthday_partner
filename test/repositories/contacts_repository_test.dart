@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/contacts_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
  });

  final otpThrottle = OtpSendThrottle();

  setUp(() async {
    await otpThrottle.run(() => auth.sendOtp('+919999000003'));
    await auth.verifyOtp(phoneE164: '+919999000003', token: '123456');
    await auth.claimProfile();
  });

  tearDown(() => auth.deleteAccount().catchError((_) {}));

  test('adding a contact returns added and a person id', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Test Friend', phoneE164: '+919999333301'),
    ]);
    expect(summary.added, 1);
    expect(summary.results.single.status, ImportStatus.added);
    expect(summary.results.single.personId, isPositive);
  });

  test('the count invariant survives the repository layer', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'A', phoneE164: '+919999333302'),
      const DeviceContact(name: 'A again', phoneE164: '+919999333302'),
      const DeviceContact(name: 'Me', phoneE164: '+919999000003'),
    ]);
    expect(
      summary.added + summary.skipped + summary.failed + summary.duplicates,
      3,
    );
    expect(summary.results.length, 3);
    expect(summary.results[1].status, ImportStatus.duplicate);
    expect(summary.results[2].status, ImportStatus.self);
  });

  // Chunking must not change the answer. This is the assertion that catches a
  // merge bug in [ImportSummary.merge] or an off-by-one in the chunker.
  test('a batch larger than one chunk still returns one result per input',
      () async {
    final many = List.generate(
      12,
      (i) => DeviceContact(
        name: 'Bulk $i',
        phoneE164: '+9199994${i.toString().padLeft(5, '0')}',
      ),
    );
    final summary =
        await contacts.addCelebrations(many, chunkSize: 5);
    expect(summary.results.length, 12);
    expect(summary.added, 12);
  });

  test('progress is reported per chunk', () async {
    final seen = <int>[];
    await contacts.addCelebrations(
      List.generate(
        7,
        (i) => DeviceContact(
          name: 'P $i',
          phoneE164: '+9199995${i.toString().padLeft(5, '0')}',
        ),
      ),
      chunkSize: 3,
      onProgress: (done, total) => seen.add(done),
    );
    expect(seen, [3, 6, 7]);
  });

  test('resolve reports which numbers are already users', () async {
    final resolved =
        await contacts.resolve(['+919999000003', '+919999999999']);
    expect(resolved.any((r) => r.phone == '+919999000003'), isTrue);
    expect(resolved.any((r) => r.phone == '+919999999999'), isFalse);
  });

  // Only a person sets their own birthday (20261017000003): an import
  // carries a name and a number, and the person it creates has no birthday.
  test('an imported contact gets no birthday', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'No Birthday', phoneE164: '+919999333303'),
    ]);
    expect(summary.added, 1);

    final personId = summary.results.single.personId!;
    final row = await ApiClient.instance
        .from('people')
        .select('birth_month')
        .eq('id', personId)
        .single();
    expect(row['birth_month'], isNull);
  });
}
