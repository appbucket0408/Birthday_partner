@Tags(['contract'])
library;

import 'dart:io';

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/ops_repository.dart';
import 'package:birthday_app/repositories/ops_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contract_test_harness.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories/ops_repository_test.dart \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
///
/// What this suite is really for: proving that **a non-staff caller is
/// refused** on every write `OpsRepository` exposes. RLS is the boundary --
/// `products_staff_write` and `delivery_slots_staff_write` are each
/// `for all using (private.is_staff())` -- and the console's own is_staff
/// check is only there to make the refusal legible. If these assertions were
/// vacuous, nothing else in this phase would catch it.
///
/// Seeding uses the same `docker exec ... psql` superuser bypass as
/// gift_repository_test.dart, because promoting a user to staff is not
/// something any repository may do: `authenticated` has no update grant on
/// `profiles.is_staff` (20260822000003_profiles.sql:54).
void main() {
  late AuthRepository auth;
  late OpsRepository ops;

  // This suite's own number. Every contract suite owns one because
  // `flutter test` runs files concurrently and GoTrue's OTP rate limit is
  // cross-process -- a shared identity produces failures in files this
  // change never touched. Added to [auth.sms.test_otp] by this task.
  const primary = '+919999000014';

  const areaName = 'Ops Repo Test Area';

  final otpThrottle = OtpSendThrottle();
  Future<void> signIn(String phone) async {
    await otpThrottle.run(() => auth.sendOtp(phone));
    await auth.verifyOtp(phoneE164: phone, token: '123456');
  }

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

  late int areaId;
  late int activeProductId;
  late int inactiveProductId;
  late String inRangeDate;
  late String outOfRangeDate;

  /// Undoes whatever a previous, possibly-interrupted run left behind, so a
  /// second run starts clean without relying on this run's tearDownAll.
  /// Deletes by exact name, never a wildcard scan.
  Future<void> cleanUpStaleRows() async {
    await psql(
      'delete from public.delivery_slots where service_area_id in '
      "(select id from public.service_areas where name = '$areaName');",
    );
    await psql(
      'delete from public.products where service_area_id in '
      "(select id from public.service_areas where name = '$areaName');",
    );
    await psql("delete from public.service_areas where name = '$areaName';");
  }

  setUpAll(() async {
    setUpContractTestEnvironment();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    ops = OpsRepositoryImpl(ApiClient.instance);

    await cleanUpStaleRows();

    areaId = int.parse(await psql(
      "insert into public.service_areas (name) values ('$areaName') "
      'returning id;',
    ));
    activeProductId = int.parse(await psql(
      'insert into public.products (service_area_id, name, price_minor, '
      "is_active) values ($areaId, 'Ops Active Cake', 50000, true) "
      'returning id;',
    ));
    inactiveProductId = int.parse(await psql(
      'insert into public.products (service_area_id, name, price_minor, '
      "is_active) values ($areaId, 'Ops Inactive Cake', 60000, false) "
      'returning id;',
    ));

    // Dates come back FROM the database, never from DateTime.now() on this
    // side: Postgres runs UTC and this host runs IST, and M3 Phase 1b shipped
    // a fixture that passed by day and failed by night for exactly that.
    inRangeDate = await psql(
      'insert into public.delivery_slots (service_area_id, slot_date, '
      'window_start, window_end, capacity) values '
      "($areaId, current_date + 2, '10:00', '13:00', 5) "
      'returning slot_date;',
    );
    outOfRangeDate = await psql(
      'insert into public.delivery_slots (service_area_id, slot_date, '
      'window_start, window_end, capacity) values '
      "($areaId, current_date + 40, '10:00', '13:00', 5) "
      'returning slot_date;',
    );

    await signIn(primary);
  });

  tearDownAll(() async {
    // Demote before anything else, so an interrupted run cannot leave this
    // identity staff-privileged for a later suite. M3 Phase 1b left a
    // promotion in place and it was inert only because that test happened to
    // be last.
    final uid = ApiClient.instance.auth.currentUser?.id;
    if (uid != null) {
      await psql(
        "update public.profiles set is_staff = false where id = '$uid';",
      );
    }
    await cleanUpStaleRows();
    await auth.signOut();
  });

  // Two halves, deliberately, because the "staff can see inactive products"
  // property is NOT a property of OpsRepository's query alone. The repository
  // omits the `.eq(is_active, true)` that GiftRepository.productsIn applies,
  // but what actually admits an inactive row is RLS:
  //   products_select_active  for select using (is_active)
  //   products_staff_write    for all    using (private.is_staff())
  // Postgres ORs permissive policies, so a non-staff caller sees only active
  // rows no matter what the client asks for. Asserting only the staff half
  // would leave the reader thinking the query did the work.
  test('1a. a NON-STAFF caller sees only ACTIVE products, whatever the query',
      () async {
    final ids = (await ops.allProductsIn(areaId)).map((p) => p.id).toList();

    expect(ids, contains(activeProductId));
    expect(ids, isNot(contains(inactiveProductId)),
        reason: 'products_select_active hides it from a non-staff caller');
  });

  test('1b. a STAFF caller sees BOTH, which is what the console needs',
      () async {
    final uid = ApiClient.instance.auth.currentUser!.id;
    await psql("update public.profiles set is_staff = true where id = '$uid';");

    try {
      final ids = (await ops.allProductsIn(areaId)).map((p) => p.id).toList();

      expect(ids, contains(activeProductId));
      // The assertion the console depends on: it must SHOW an inactive
      // product in order to reactivate one.
      expect(ids, contains(inactiveProductId),
          reason: 'staff must see the row the console exists to edit');
    } finally {
      await psql(
        "update public.profiles set is_staff = false where id = '$uid';",
      );
    }
  });

  test('2. slotsBetween is bounded and ordered', () async {
    final from = DateTime.parse(inRangeDate).subtract(const Duration(days: 1));
    final to = DateTime.parse(inRangeDate).add(const Duration(days: 1));

    final slots = await ops.slotsBetween(areaId, from: from, to: to);
    final dates = slots.map((s) => s.slotDate).toList();

    expect(dates, isNotEmpty);
    expect(
      dates.any((d) => d == DateTime.parse(inRangeDate)),
      isTrue,
      reason: 'the in-range slot must be returned',
    );
    expect(
      dates.any((d) => d == DateTime.parse(outOfRangeDate)),
      isFalse,
      reason: 'a slot outside the range must be excluded',
    );
  });

  test('3. a NON-STAFF caller is refused on createProduct', () async {
    await expectLater(
      ops.createProduct(
        serviceAreaId: areaId,
        name: 'Should Not Exist',
        priceMinor: 12345,
      ),
      throwsA(isA<AppFailure>()),
    );

    // The database is the real assertion: nothing was written.
    final count = await psql(
      "select count(*) from public.products where name = 'Should Not Exist';",
    );
    expect(count, '0');
  });

  test('4. a NON-STAFF caller is refused on createSlot and setSlotCapacity',
      () async {
    await expectLater(
      ops.createSlot(
        serviceAreaId: areaId,
        slotDate: DateTime.parse(inRangeDate),
        windowStart: '18:00',
        windowEnd: '20:00',
        capacity: 3,
      ),
      throwsA(isA<AppFailure>()),
    );

    final count = await psql(
      'select count(*) from public.delivery_slots where service_area_id = '
      "$areaId and window_start = '18:00:00';",
    );
    expect(count, '0', reason: 'the slot must not have been created');

    await expectLater(
      ops.setSlotCapacity(
        int.parse(await psql(
          'select id from public.delivery_slots where service_area_id = '
          "$areaId and slot_date = '$inRangeDate' limit 1;",
        )),
        capacity: 99,
      ),
      throwsA(isA<AppFailure>()),
    );

    final capacity = await psql(
      'select capacity from public.delivery_slots where service_area_id = '
      "$areaId and slot_date = '$inRangeDate' limit 1;",
    );
    expect(capacity, '5', reason: 'the capacity must be unchanged');
  });

  test('5. a STAFF caller succeeds at createProduct', () async {
    final uid = ApiClient.instance.auth.currentUser!.id;
    // No repository call can do this: authenticated has no update grant on
    // is_staff. Same superuser bypass every other fixture here uses.
    await psql("update public.profiles set is_staff = true where id = '$uid';");

    try {
      final created = await ops.createProduct(
        serviceAreaId: areaId,
        name: 'Ops Staff Cake',
        flavour: 'vanilla',
        size: '500g',
        priceMinor: 75000,
      );

      expect(created.name, 'Ops Staff Cake');
      expect(created.priceMinor, 75000);
      expect(created.isActive, isTrue);
    } finally {
      // Demote inside the test, not only in tearDownAll: a test appended
      // after this one would otherwise inherit staff and see rows it should
      // not, failing for a reason that looks nothing like the cause.
      await psql(
        "update public.profiles set is_staff = false where id = '$uid';",
      );
    }
  });
}
