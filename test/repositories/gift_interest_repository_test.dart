@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:birthday_app/repositories/gift_interest_repository.dart';
import 'package:birthday_app/repositories/gift_interest_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// "Notify me" for cake gifting against the real table
/// (20261017000007_gift_interest.sql). Signs in by email, so it uses no
/// number from the shared test-phone pool.
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late GiftInterestRepository interest;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    interest = GiftInterestRepositoryImpl(ApiClient.instance);
  });

  setUp(() async {
    final email = 'interest${DateTime.now().microsecondsSinceEpoch}@example.com';
    await auth.sendEmailOtp(email);
    await auth.verifyEmailOtp(email: email, token: await mailedCode(email));
  });

  tearDown(() => auth.deleteAccount().catchError((_) {}));

  test('register records interest once, and isRegistered reads it back',
      () async {
    // Interest is only accepted for someone the caller celebrates, so
    // celebrate someone first, through the same import the app uses.
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Cake Friend', phoneE164: '+919999444701'),
    ]);
    final personId = summary.results.single.personId!;

    expect(await interest.isRegistered(personId), isFalse);

    await interest.register(personId);
    await interest.register(personId); // a second tap is not an error

    expect(await interest.isRegistered(personId), isTrue);
  });

  test('interest for someone you do not celebrate is refused', () async {
    await expectLater(interest.register(1), throwsA(isA<AppFailure>()));
  });
}
