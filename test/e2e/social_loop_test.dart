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
import 'package:birthday_app/repositories/profile_repository.dart';
import 'package:birthday_app/repositories/profile_repository_impl.dart';
import 'package:birthday_app/repositories/wish_repository.dart';
import 'package:birthday_app/repositories/wish_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// The parent spec's single end-to-end test: sign in -> import -> timeline
/// -> wish -> profile counts tick. It has been unwritable since M1 began
/// because it needs the wish and the profile, both of which Phase 3 adds.
///
/// Deliberately not widget-driven. A widget-level E2E on the Dart VM would
/// add mounting/pumping complexity for every screen in the chain without
/// touching the one thing still genuinely unverified -- the app running on
/// a real device -- and would be slower and more brittle for it. This test
/// drives the repositories directly instead: the same seam every other
/// contract test in this project already exercises, so the loop is proven
/// at the layer that actually talks to the server, at the cost of not
/// proving any widget wiring above it. See docs/superpowers/execution/
/// 2026-08-30-m1-phase3-ledger.md's "Not verified" section for what this
/// still does not cover.
///
/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/e2e/social_loop_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late GraphRepository graph;
  late WishRepository wish;
  late ProfileRepository profile;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    graph = GraphRepositoryImpl(ApiClient.instance);
    wish = WishRepositoryImpl(ApiClient.instance);
    profile = ProfileRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number, already added to [auth.sms.test_otp] in
  // Task 1 and unused by every other suite (graph=004/006, person=007,
  // wish=008/011, profile=009/012, contacts=003, auth=001/002,
  // settings=005).
  const primary = '+919999000010';

  // The friend being wished. Only a person sets their own birthday
  // (20261017000003), so the friend has to be a member who entered one --
  // an imported contact who is not on the app has no birthday to wish on.
  const friend = '+919999000016';
  const friendBirthday = Birthday(month: 6, day: 15);

  final otpThrottle = OtpSendThrottle();

  Future<void> signIn(String phone) async {
    await otpThrottle.run(() => auth.sendOtp(phone));
    await auth.verifyOtp(phoneE164: phone, token: '123456');
    await auth.claimProfile();
  }

  setUp(() => signIn(primary));

  tearDown(() => auth.deleteAccount().catchError((_) {}));

  test(
      'sign in, claim, add a celebration, read the timeline, post a wish, '
      'and see it counted in profile stats', () async {
    // 1. Sign in + claim already happened in setUp -- AuthRepository is the
    //    first leg of the loop.

    // 2. The friend joins and sets their own birthday. Signed out after,
    //    not deleted: the wish below needs their person row to stay claimed.
    await auth.signOut();
    await signIn(friend);
    await auth.completeProfile(
      handle: 'loop_friend',
      displayName: 'Loop Friend',
      city: 'Jaipur',
      birthday: friendBirthday,
    );
    await auth.signOut();
    await signIn(primary);

    // Import: add the friend through ContactsRepository. The import itself
    //    carries no birthday -- it comes from the friend's own profile.
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Loop Friend', phoneE164: friend),
    ]);
    final personId = summary.results.single.personId!;
    expect(personId, isPositive);

    // 3. Timeline: GraphRepository.celebrations() is the timeline's own
    //    data source (spec §6.3) -- the new edge is readable through it,
    //    with the birthday the friend set themselves.
    final celebrations = await graph.celebrations();
    final edge = celebrations.firstWhere(
      (c) => c.person.id == personId,
      orElse: () => fail('expected the new celebration to appear in '
          'GraphRepository.celebrations()'),
    );
    expect(edge.person.birthday, friendBirthday);
    // 4. Wish: post through WishRepository, with occasionYear computed the
    //    same way the real UI would derive it.
    final occasionYear = friendBirthday.occasionYear(DateTime.now());
    await wish.post(
      personId: personId,
      body: 'Happy birthday!',
      occasionYear: occasionYear,
    );

    // 5. Profile: the wish must be counted for the SAME occasion year it
    //    was posted for.
    final stats = await profile.stats();
    final row = stats.firstWhere(
      (s) => s.year == occasionYear,
      orElse: () => fail(
        'expected a $occasionYear row in ProfileRepository.stats(), '
        'got: $stats',
      ),
    );
    expect(row.wishesSent, 1);

    // Cleanup: the friend's account, so a rerun starts fresh. tearDown then
    // deletes the primary, which this leaves signed in.
    await auth.signOut();
    await signIn(friend);
    await auth.deleteAccount();
    await signIn(primary);
  }, timeout: const Timeout(Duration(seconds: 150)));
}
