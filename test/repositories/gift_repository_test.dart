@Tags(['contract'])
library;

import 'dart:io';

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/gift.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:birthday_app/repositories/gift_repository.dart';
import 'package:birthday_app/repositories/gift_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/gift_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
///
/// Seeding note: this suite needs catalog rows (service_areas, products,
/// delivery_slots) that no repository can create -- products_staff_write
/// requires staff. They are seeded with a direct connection to Postgres, the
/// same mechanism supabase/functions/add_celebrations/index.test.ts uses for
/// suppressions: a bypass of RLS/PostgREST that only staff-equivalent access
/// can reach. Nothing on this host has psql or a Postgres client library
/// installed, so the "direct connection" here execs into the already-running
/// local db container (`supabase_db_birthday_app`) instead of dialing
/// postgresql://postgres:postgres@127.0.0.1:54322/postgres from a client --
/// same database, same superuser bypass, no new dependency added to pubspec.
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;
  late GiftRepository gift;

  // This suite's own number -- every contract suite owns one because
  // `flutter test` runs files concurrently and a shared OTP identity
  // produces failures in files this task never touched. Task 1 added this
  // number to [auth.sms.test_otp].
  const primary = '+919999000013';

  final otpThrottle = OtpSendThrottle();
  Future<void> signIn(String phone) async {
    await otpThrottle.run(() => auth.sendOtp(phone));
    await auth.verifyOtp(phoneE164: phone, token: '123456');
  }

  const testAreaNamePrefix = 'Gift Repo Test Area';
  const decoyUserPhone = '+919999555001';
  // 64 hex chars to satisfy people_phone_hash_format -- a stable function of
  // decoyUserPhone rather than a random value, so cleanUpStaleRows() can find
  // and remove this row on a second run without having persisted its id.
  const decoyPersonHashExpr = "encode(sha256('$decoyUserPhone'::bytea), 'hex')";

  Future<String> psql(String sql) async {
    final result = await Process.run('docker', [
      'exec',
      '-i',
      'supabase_db_birthday_app',
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-v',
      'ON_ERROR_STOP=1',
      // -q suppresses the command tag ("INSERT 0 1") that a bare -tA still
      // prints after a RETURNING clause's value on this psql version --
      // without it, int.parse sees "9\nINSERT 0 1" instead of "9".
      '-q',
      '-tA',
      '-c',
      sql,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'psql failed (${result.exitCode}): ${result.stderr}\nSQL: $sql',
      );
    }
    return (result.stdout as String).trim();
  }

  // Undoes whatever a previous, possibly-interrupted run of this suite left
  // behind, so a second run starts clean without relying on this run's own
  // tearDownAll having completed.
  Future<void> cleanUpStaleRows() async {
    await psql('''
      delete from public.gifts
      where service_area_id in (
        select id from public.service_areas where name like '$testAreaNamePrefix%'
      )
      or sender_profile_id in (
        select id from auth.users where phone = '$decoyUserPhone'
      );
    ''');
    await psql(
      'delete from public.people where phone_e164_hash = $decoyPersonHashExpr;',
    );
    await psql("delete from auth.users where phone = '$decoyUserPhone';");
    await psql('''
      delete from public.delivery_slots
      where service_area_id in (
        select id from public.service_areas where name like '$testAreaNamePrefix%'
      );
    ''');
    await psql('''
      delete from public.products
      where service_area_id in (
        select id from public.service_areas where name like '$testAreaNamePrefix%'
      );
    ''');
    await psql(
      "delete from public.service_areas where name like '$testAreaNamePrefix%';",
    );
  }

  late int serviceAreaId;
  late int otherAreaId;
  late int productId;
  late int inactiveProductId;
  late int otherAreaProductId;
  late int roomySlotId;
  late int tightSlotId;
  late int pastSlotId;
  late int primaryPersonId;
  late int recipientPersonId;
  late String decoyProfileId;
  // A real, existing people row the primary caller never celebrates --
  // assertion 5 targets this rather than a nonexistent sentinel id, so that
  // with the celebration guard removed the RPC's only remaining obstacle
  // would be a genuine one, not a foreign-key violation on a fake id.
  late int decoyPersonId;
  // A gift sent BY the decoy TO the primary caller. RLS's recipient branch
  // (`recipient_person_id = private.my_person_id()`) makes this row visible
  // to the primary caller, so only the explicit `.eq(senderProfileId, ...)`
  // filter in GiftRepositoryImpl.myGifts() keeps it out of that list --
  // exercising the actual property the brief calls out ("silently
  // over-fetching if a policy ever loosens").
  late int receivedGiftId;

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
    gift = GiftRepositoryImpl(ApiClient.instance);

    await cleanUpStaleRows();

    serviceAreaId = int.parse(await psql(
      'insert into public.service_areas (name) values '
      "('$testAreaNamePrefix') returning id;",
    ));
    otherAreaId = int.parse(await psql(
      'insert into public.service_areas (name) values '
      "('$testAreaNamePrefix (Other)') returning id;",
    ));
    productId = int.parse(await psql(
      'insert into public.products (service_area_id, name, price_minor) '
      "values ($serviceAreaId, 'Test Cake', 50000) returning id;",
    ));
    inactiveProductId = int.parse(await psql(
      'insert into public.products '
      '(service_area_id, name, price_minor, is_active) '
      "values ($serviceAreaId, 'Retired Cake', 50000, false) returning id;",
    ));
    otherAreaProductId = int.parse(await psql(
      'insert into public.products (service_area_id, name, price_minor) '
      "values ($otherAreaId, 'Other Area Cake', 50000) returning id;",
    ));
    roomySlotId = int.parse(await psql(
      'insert into public.delivery_slots '
      '(service_area_id, slot_date, window_start, window_end, capacity) '
      "values ($serviceAreaId, current_date + 1, '09:00', '12:00', 10) "
      'returning id;',
    ));
    tightSlotId = int.parse(await psql(
      'insert into public.delivery_slots '
      '(service_area_id, slot_date, window_start, window_end, capacity) '
      "values ($serviceAreaId, current_date + 2, '09:00', '12:00', 1) "
      'returning id;',
    ));
    pastSlotId = int.parse(await psql(
      'insert into public.delivery_slots '
      '(service_area_id, slot_date, window_start, window_end, capacity) '
      "values ($serviceAreaId, current_date - 1, '09:00', '12:00', 5) "
      'returning id;',
    ));

    await signIn(primary);
    primaryPersonId = await auth.claimProfile();

    final summary = await contacts.addCelebrations([
      const DeviceContact(
        name: 'Gift Recipient',
        phoneE164: '+919999444601',
        birthday: null,
      ),
    ]);
    recipientPersonId = summary.results.single.personId!;

    // A second identity, for the "not another sender's" assertion. No
    // repository can create a gift row for someone else, so this decoy is
    // seeded directly too: `id` is the only NOT NULL column on auth.users,
    // and the on_auth_user_created trigger mints its public.profiles row,
    // which is all a gift's sender_profile_id needs to satisfy the foreign
    // key. It never signs in -- decoyUserPhone is not in
    // [auth.sms.test_otp], it exists only so a second run of this suite can
    // find and remove this row.
    decoyProfileId = await psql(
      'insert into auth.users (id, phone) values (gen_random_uuid(), '
      "'$decoyUserPhone') returning id;",
    );
    // The decoy's own people row -- claim_person is what normally creates
    // one, and the decoy never signs in to call it, so this is seeded
    // directly too. A real, existing person id the primary caller holds no
    // celebration edge to.
    decoyPersonId = int.parse(await psql(
      'insert into public.people (phone_e164_hash, profile_id, display_name) '
      "values ($decoyPersonHashExpr, '$decoyProfileId', 'Decoy Person') "
      'returning id;',
    ));
    receivedGiftId = int.parse(await psql(
      'insert into public.gifts '
      '(sender_profile_id, recipient_person_id, product_id, '
      'service_area_id, slot_id, occasion_date, amount_minor, status) '
      "values ('$decoyProfileId', $primaryPersonId, $productId, "
      "$serviceAreaId, $roomySlotId, current_date + 1, 50000, 'draft') "
      'returning id;',
    ));
  });

  tearDownAll(() async {
    // Every gift this suite created must go before the profiles, the
    // products, or the service area it references -- all three are ON
    // DELETE RESTRICT foreign keys from public.gifts. Deleting them first
    // also means AuthRepository.deleteAccount() below can actually succeed:
    // once a sender has a gift row, deleting their account otherwise fails
    // (delete_account/index.ts documents this as a known M3 limit) and the
    // profile would be left behind for good. This also clears receivedGiftId
    // (recipient_person_id also on delete restrict), so the decoy's people
    // row below can be deleted cleanly too.
    await psql(
      'delete from public.gifts where service_area_id in '
      '($serviceAreaId, $otherAreaId);',
    );
    await auth.deleteAccount().catchError((_) {});
    await psql(
      'delete from public.people where phone_e164_hash = $decoyPersonHashExpr;',
    );
    await psql("delete from auth.users where phone = '$decoyUserPhone';");
    await psql(
      'delete from public.delivery_slots where service_area_id in '
      '($serviceAreaId, $otherAreaId);',
    );
    await psql(
      'delete from public.products where service_area_id in '
      '($serviceAreaId, $otherAreaId);',
    );
    await psql(
      'delete from public.service_areas where id in '
      '($serviceAreaId, $otherAreaId);',
    );
  });

  test('1. serviceAreas() returns active areas', () async {
    final areas = await gift.serviceAreas();

    expect(areas.map((a) => a.id), contains(serviceAreaId));
    expect(
      areas.singleWhere((a) => a.id == serviceAreaId).name,
      testAreaNamePrefix,
    );
  });

  test(
      '2. productsIn() returns only that area\'s active products',
      () async {
    final products = await gift.productsIn(serviceAreaId);
    final ids = products.map((p) => p.id).toList();

    expect(ids, contains(productId));
    expect(ids, isNot(contains(inactiveProductId)));
    expect(ids, isNot(contains(otherAreaProductId)));
  });

  test(
      '3. slotsIn() returns slots on or after the given date, with capacity '
      'and reserved populated', () async {
    final slots = await gift.slotsIn(
      serviceAreaId,
      onOrAfter: DateTime.now(),
    );
    final byId = {for (final s in slots) s.id: s};

    expect(byId.keys, contains(roomySlotId));
    expect(byId.keys, contains(tightSlotId));
    expect(byId.keys, isNot(contains(pastSlotId)));

    expect(byId[roomySlotId]!.capacity, 10);
    expect(byId[roomySlotId]!.reserved, 0);
    expect(byId[roomySlotId]!.remaining, 10);
    expect(byId[tightSlotId]!.capacity, 1);
    expect(byId[tightSlotId]!.reserved, 0);
  });

  test(
      '4. createDraft() for a person the caller celebrates returns a Gift '
      'in GiftStatus.draft, with slotHoldExpiresAt set roughly 15 minutes '
      'out', () async {
    final before = DateTime.now();

    final draft = await gift.createDraft(
      recipientPersonId: recipientPersonId,
      productId: productId,
      slotId: roomySlotId,
      occasionDate: DateTime.now().add(const Duration(days: 1)),
      message: 'Happy birthday!',
    );

    expect(draft.status, GiftStatus.draft);
    expect(draft.slotHoldExpiresAt, isNotNull);
    final holdMinutes =
        draft.slotHoldExpiresAt!.difference(before).inSeconds / 60;
    expect(holdMinutes, greaterThan(14));
    expect(holdMinutes, lessThan(16));
  });

  test(
      '5. createDraft() for a person the caller does NOT celebrate throws '
      "ServerFailure with code '45005'", () async {
    // decoyPersonId is a real, existing people row -- not a nonexistent
    // sentinel. With the guard in place this proves the RPC checks
    // celebration rather than mere existence; Step 7 (see task-4-report.md)
    // proves that with the guard removed, THIS is the id-space-walking
    // exploit the guard exists to close, because there is no foreign key
    // left to trip on a real id.
    await expectLater(
      gift.createDraft(
        recipientPersonId: decoyPersonId,
        productId: productId,
        slotId: roomySlotId,
        occasionDate: DateTime.now().add(const Duration(days: 1)),
      ),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '45005')),
    );
  });

  test(
      '6. createDraft() into a full slot throws ServerFailure with code '
      "'23514'", () async {
    // tightSlotId has capacity 1. This first call fills it.
    final filler = await gift.createDraft(
      recipientPersonId: recipientPersonId,
      productId: productId,
      slotId: tightSlotId,
      occasionDate: DateTime.now().add(const Duration(days: 2)),
    );
    expect(filler.status, GiftStatus.draft);

    // A second caller racing for the same, now-full slot gets a distinct,
    // pinned code -- the UI branches on it to say "that slot just filled"
    // rather than a generic failure.
    await expectLater(
      gift.createDraft(
        recipientPersonId: recipientPersonId,
        productId: productId,
        slotId: tightSlotId,
        occasionDate: DateTime.now().add(const Duration(days: 2)),
      ),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '23514')),
    );
  });

  test(
      '7. myGifts() returns the caller\'s own drafts and NOT another '
      'sender\'s, and every returned gift has deliveryCity == null',
      () async {
    final mine = await gift.createDraft(
      recipientPersonId: recipientPersonId,
      productId: productId,
      slotId: roomySlotId,
      occasionDate: DateTime.now().add(const Duration(days: 1)),
    );

    final gifts = await gift.myGifts();
    final ids = gifts.map((g) => g.id).toList();

    expect(ids, contains(mine.id));
    // receivedGiftId is visible to the caller under RLS (they are its
    // recipient) -- only the sender filter in myGifts() keeps it out here.
    expect(ids, isNot(contains(receivedGiftId)));
    // THE PRODUCT'S CORE PROMISE: the city is denormalised onto the gift
    // only at confirmation, which does not exist in this phase, so the
    // sender must never be able to reach the recipient's address through it.
    expect(gifts.every((g) => g.deliveryCity == null), isTrue);
  });
}
