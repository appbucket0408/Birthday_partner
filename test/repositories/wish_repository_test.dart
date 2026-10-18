@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:birthday_app/repositories/wish_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/wish_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late WishRepository wish;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    wish = WishRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number, per the task-11 phone pool assignment.
  const primary = '+919999000008';

  // Assertion 5 (the privacy assertion this task exists for) needs a second
  // real identity distinct from `primary`, so it can celebrate and wish a
  // person `primary` also celebrates, without `primary` and `second` ever
  // being connected to each other. This is its own dedicated number, not
  // '...006 (graph_repository_test.dart's second identity): `flutter test`
  // runs test FILES concurrently, and each file's OtpSendThrottle only
  // serialises sends within its own process -- sharing a number across
  // files lets GoTrue's real cross-process 5s rate limit trip a suite that
  // never touched the file racing it. '...011 is added to
  // [auth.sms.test_otp] specifically so this suite owns it alone.
  const second = '+919999000011';

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

  test(
      'post() then wishesFor() returns the wish, with its body and '
      'occasionYear', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Wish Target One', phoneE164: '+919999444601'),
    ]);
    final personId = summary.results.single.personId!;

    await wish.post(
      personId: personId,
      body: 'Happy birthday!',
      occasionYear: 2026,
    );

    final wishes = await wish.wishesFor(personId);

    expect(wishes, hasLength(1));
    expect(wishes.single.body, 'Happy birthday!');
    expect(wishes.single.occasionYear, 2026);
  });

  test('feed() pages the visible wishes newest first, with names', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Wish Target Feed', phoneE164: '+919999444603'),
    ]);
    final personId = summary.results.single.personId!;
    for (final year in [2024, 2025, 2026]) {
      await wish.post(personId: personId, body: 'Wish $year', occasionYear: year);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final first = await wish.feed(limit: 2);
    expect(first.map((e) => e.wish.body).toList(), ['Wish 2026', 'Wish 2025']);
    expect(first.every((e) => e.subjectName == 'Wish Target Feed'), isTrue);

    final rest = await wish.feed(before: first.last.wish.createdAt, limit: 2);
    expect(rest.map((e) => e.wish.body).toList(), ['Wish 2024']);
  });

  test('wishesFor() returns newest first', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Wish Target Two', phoneE164: '+919999444602'),
    ]);
    final personId = summary.results.single.personId!;

    // Different occasionYear on each post: wishes_one_message_per_year is
    // unique on (author_profile_id, subject_person_id, occasion_year) for
    // kind='message', and both wishes here share an author and a subject.
    // A short delay between the two guards created_at ordering against
    // timestamp-resolution ties, since created_at ordering -- not
    // occasion_year -- is what this test is actually verifying.
    await wish.post(personId: personId, body: 'First wish', occasionYear: 2024);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await wish.post(
      personId: personId,
      body: 'Second wish',
      occasionYear: 2025,
    );

    final wishes = await wish.wishesFor(personId);

    expect(wishes.map((w) => w.body).toList(), ['Second wish', 'First wish']);
  });

  test('post() to a person the caller does not celebrate is refused',
      () async {
    // A person who genuinely exists (so the FK on subject_person_id is
    // satisfied) but that `primary` holds no celebration edge to: `second`'s
    // own claimed person row. `second`'s account is deleted immediately
    // after claiming so its person row is left unclaimed and inert for the
    // rest of the suite -- `primary` never celebrates it, at no point.
    await signIn(second);
    final secondPersonId = await auth.claimProfile();
    await auth.deleteAccount();

    await signIn(primary);
    await auth.claimProfile();

    Object? caught;
    try {
      await wish.post(
        personId: secondPersonId,
        body: 'uninvited',
        occasionYear: 2026,
      );
      fail('expected wishes_insert_own to refuse this insert');
    } catch (e) {
      caught = e;
    }

    // wishes_insert_own is a bare RLS `with check`, not a raised exception
    // with a custom errcode, so mapError may see a PostgrestException whose
    // code is the generic RLS-violation SQLSTATE rather than one of this
    // schema's custom 450xx codes. Record what was actually observed here in
    // task-5-report.md rather than assuming a specific code.
    // ignore: avoid_print
    print(
      'post()-not-celebrated -> ${caught.runtimeType}'
      '${caught is ServerFailure ? " code=${caught.code}" : ""}: $caught',
    );
    expect(caught, isA<AppFailure>());
  });

  test(
      "the caller's own wish resolves authorName to their own display "
      'name', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(
        name: 'Wish Target Four',
        phoneE164: '+919999444604',
      ),
    ]);
    final personId = summary.results.single.personId!;

    await wish.post(personId: personId, body: 'From me', occasionYear: 2026);

    final wishes = await wish.wishesFor(personId);
    final mine = wishes.single;
    final profile = await auth.loadProfile();

    expect(mine.authorProfileId, auth.currentUserId);
    expect(mine.authorName, profile.displayName);
  });

  test(
      'a wish by an author the caller is not connected to has a null '
      'authorName, and the wish itself still appears -- THE PRIVACY '
      'ASSERTION', () async {
    // This scenario needs four OTP sign-ins beyond setUp's own (second,
    // primary, second again for cleanup, primary again), all through this
    // FILE's own OtpSendThrottle instance. Giving `second` its own number
    // (see above) removes the cross-file collision risk but does nothing
    // for this: the throttle's cooldown is paid once per send regardless of
    // which number is being sent to. Measured standalone at both ~26s and
    // ~31s across separate runs -- genuinely straddling the 30s default,
    // not "just in case".
    const subjectPhone = '+919999444605';
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Shared Wall Subject', phoneE164: subjectPhone),
    ]);
    final personId = summary.results.single.personId!;

    // `second` celebrates the SAME person and posts a wish on their wall,
    // but never becomes connected to `primary` in either direction --
    // `primary` and `second` share no celebration edge to each other.
    await signIn(second);
    await auth.claimProfile();
    final secondSummary = await contacts.addCelebrations([
      const DeviceContact(name: 'Shared Wall Subject', phoneE164: subjectPhone),
    ]);
    expect(secondSummary.results.single.personId, personId);
    await wish.post(
      personId: personId,
      body: 'unconnected wish',
      occasionYear: 2026,
    );
    // Signed out, not deleted yet: deleteAccount cascades wishes.
    // author_profile_id references profiles(id) on delete cascade, which
    // would erase the very wish this test needs to read back.
    await auth.signOut();

    await signIn(primary);
    await auth.claimProfile();

    final wishes = await wish.wishesFor(personId);
    final unconnected =
        wishes.firstWhere((w) => w.body == 'unconnected wish');

    expect(unconnected.authorName, isNull);

    // Cleanup for repeatability: delete `second`'s account now that the
    // assertion above has already read its wish back, so a rerun of this
    // suite does not collide with wishes_one_message_per_year's unique
    // index on (author_profile_id, subject_person_id, occasion_year).
    await signIn(second);
    await auth.deleteAccount();
    await signIn(primary);
    await auth.claimProfile();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
      "wishesToMe() is empty for a new account, then returns a wish posted "
      "to the caller's own person by someone who celebrates them", () async {
    expect(await wish.wishesToMe(), isEmpty);

    // `second` adds `primary` by phone, which resolves to primary's own
    // claimed person row, and wishes them.
    await signIn(second);
    await auth.claimProfile();
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Primary', phoneE164: primary),
    ]);
    await wish.post(
      personId: summary.results.single.personId!,
      body: 'happy birthday, primary',
      occasionYear: 2026,
    );
    // Signed out, not deleted: deleteAccount cascades the wish.
    await auth.signOut();

    await signIn(primary);
    await auth.claimProfile();

    final wall = await wish.wishesToMe();
    expect(wall.map((w) => w.body), ['happy birthday, primary']);
    // `second` celebrates `primary`, so can_see_person resolves the name.
    expect(wall.single.authorName, isNotNull);

    await signIn(second);
    await auth.deleteAccount();
    await signIn(primary);
    await auth.claimProfile();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
      'a body over 500 characters is refused by the DB check constraint '
      "wishes_body_length, ServerFailure code '23514'", () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Wish Target Six', phoneE164: '+919999444606'),
    ]);
    final personId = summary.results.single.personId!;

    await expectLater(
      wish.post(
        personId: personId,
        body: 'a' * 501,
        occasionYear: 2026,
      ),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '23514')),
    );
  });
}
