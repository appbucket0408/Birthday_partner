@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
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

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/profile_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late WishRepository wish;
  late GraphRepository graph;
  late ProfileRepository profile;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    wish = WishRepositoryImpl(ApiClient.instance);
    graph = GraphRepositoryImpl(ApiClient.instance);
    profile = ProfileRepositoryImpl(ApiClient.instance);
  });

  // This suite's own number, per the task-7 brief's phone assignment.
  const primary = '+919999000009';

  // Assertions 4 and 5 need a second real identity that celebrates `primary`.
  // This is this suite's OWN dedicated number, not shared with any other
  // suite's second identity: `flutter test` runs test FILES concurrently,
  // and OtpSendThrottle (see contract_test_harness.dart) only serialises
  // sends WITHIN this process, so a number shared with another file's own
  // second identity can trip GoTrue's real cross-process rate limit when
  // both processes send to it around the same wall-clock moment --
  // reproduced once during this task's development while this suite was
  // still assigned '...006 (graph_repository_test.dart's own second
  // identity), fixed by dedicating '...012 instead. See
  // wish_repository_test.dart's own comment on '...011 for the same
  // reasoning. `second`'s account is claimed once and left signed-out-but-
  // not-deleted across every test in this file (never torn down by
  // `tearDown`, which only ever runs while `primary` is the active
  // session) -- only the specific celebration edge each test creates is
  // removed afterwards, signed in as `second`, so a rerun of this suite
  // does not find `primary` already celebrated.
  const second = '+919999000012';

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
  // finishing (assertions 4 and 5 do this explicitly after their own
  // cleanup), so this always tears down `primary`, never `second`.
  tearDown(() => auth.deleteAccount().catchError((_) {}));

  // 1. stats() returns an empty list for a fresh account with no wishes.
  //
  // This stays true across reruns of this suite, not just within one: the
  // `mine` CTE inside my_birthday_stats() matches on `author_profile_id =
  // this run's fresh auth.uid()` (never seen before) OR `subject_person_id =
  // primary's own, STABLE person id`. Nothing in this file ever posts a wish
  // TO primary's own person row (only assertion 2 posts one BY primary, to a
  // throwaway contact), and wishes primary authors cascade-delete with the
  // account in tearDown -- so no run ever leaves a residue the next run's
  // assertion 1 could trip over.
  test('stats() returns an empty list for a fresh account with no wishes',
      () async {
    final stats = await profile.stats();
    expect(stats, isEmpty);
  });

  // 2. After posting a wish, stats() has a row for that occasion year with
  //    wishesSent == 1. Seeded via WishRepository (Task 5), not raw SQL --
  //    this proves the function reflects what the app actually writes.
  test(
      'after posting a wish, stats() has a row for that occasion year with '
      'wishesSent == 1', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Stat Target', phoneE164: '+919999444701'),
    ]);
    final personId = summary.results.single.personId!;

    await wish.post(personId: personId, body: 'Happy birthday!',
        occasionYear: 2026);

    final stats = await profile.stats();
    final row =
        stats.firstWhere((s) => s.year == 2026, orElse: () => fail(
            'expected a 2026 row in stats(), got: $stats'));
    expect(row.wishesSent, 1);
  });

  // 3. celebrates() is empty for an account nobody celebrates.
  test('celebrates() is empty for an account nobody celebrates', () async {
    final celebrators = await profile.celebrates();
    expect(celebrators, isEmpty);
  });

  // 4. celebrates() returns the celebrator with their name once a second
  //    identity celebrates the caller. can_see_person's third branch ("they
  //    celebrate me") is what makes that name readable -- this asserts it.
  //    This is the assertion that proves the profile's Celebrates list can
  //    render names at all.
  test(
      'celebrates() returns the celebrator with their name once a second '
      "identity celebrates the caller -- can_see_person's 'they celebrate "
      "me' branch is what makes that name readable", () async {
    await signIn(second);
    final secondPersonId = await auth.claimProfile();
    final secondProfile = await auth.loadProfile();

    // `second` celebrates `primary`'s own phone number directly, creating the
    // incoming edge my_celebrates() reads from primary's side. The name
    // passed here is irrelevant to what primary eventually sees -- RLS keeps
    // that private to `second`, which is exactly the point of the two-step
    // read this repository performs.
    final summary = await contacts.addCelebrations([
      const DeviceContact(name: "second's private label for primary",
          phoneE164: primary),
    ]);
    final primaryPersonId = summary.results.single.personId!;
    final celebrationId = (await graph.celebrations())
        .firstWhere((c) => c.person.id == primaryPersonId)
        .id;

    await signIn(primary);
    await auth.claimProfile();

    final celebrators = await profile.celebrates();

    expect(celebrators, hasLength(1));
    expect(celebrators.single.id, secondPersonId);
    expect(celebrators.single.displayName, secondProfile.displayName);

    // Cleanup: remove the edge now, signed in as `second`, so a rerun of
    // this suite does not find `primary` already celebrated (see the note
    // on assertion 1 above, and on `second` at the top of this file).
    await signIn(second);
    await graph.stopCelebrating(celebrationId);
    await signIn(primary);
    await auth.claimProfile();
  }, timeout: const Timeout(Duration(seconds: 90)));

  // 5. A celebrator the caller has blocked does not appear in celebrates().
  test('a celebrator the caller has blocked does not appear in celebrates()',
      () async {
    await signIn(second);
    await auth.claimProfile();
    final secondProfile = await auth.loadProfile();

    final summary = await contacts.addCelebrations([
      const DeviceContact(name: 'Soon blocked', phoneE164: primary),
    ]);
    final primaryPersonId = summary.results.single.personId!;
    final celebrationId = (await graph.celebrations())
        .firstWhere((c) => c.person.id == primaryPersonId)
        .id;

    await signIn(primary);
    await auth.claimProfile();

    // No BlockRepository exists yet (Phase 3 does not add one -- see
    // task-7-report.md). This is a direct authenticated insert under
    // blocks_all_own's own RLS policy (`using (blocker_profile_id =
    // auth.uid())`), the same tier of access a future BlockRepository would
    // use, not a raw-SQL/service-role bypass.
    await ApiClient.instance.from('blocks').insert({
      'blocker_profile_id': auth.currentUserId,
      'blocked_profile_id': secondProfile.id,
    });

    final celebrators = await profile.celebrates();
    expect(celebrators, isEmpty);

    // Cleanup: the block row cascades away automatically when `primary`'s
    // account is deleted in tearDown (blocks.blocker_profile_id references
    // profiles(id) on delete cascade), but the celebration edge belongs to
    // `second`, not `primary`, and would otherwise persist across runs.
    // Remove it now, signed in as `second`.
    await signIn(second);
    await graph.stopCelebrating(celebrationId);
    await signIn(primary);
    await auth.claimProfile();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
