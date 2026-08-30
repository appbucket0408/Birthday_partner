# M3 Phase 1a — Gifting: Catalog, Slot Hold, Draft — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a sender pick a cake and a delivery slot for someone they celebrate, and hold that slot for fifteen real minutes against a database-enforced capacity.

**Architecture:** `view → cubit → repository → Supabase client`, unchanged. M0 already built the gifts schema, the eleven-state machine, the slot reservation helpers and their race test; this phase adds the two things it lacks — a cron to release abandoned holds, and a public wrapper with the one guard `create_gift` is missing — then four screens on top.

**Tech Stack:** Flutter 3.35.2 (FVM), Dart 3.9, `flutter_bloc`, `go_router`, `supabase_flutter`; Postgres 17 + pgTAP + pg_cron.

**Spec:** `docs/superpowers/specs/2026-08-30-m3-phase1a-gifting-draft-design.md`

## Global Constraints

- **Flutter 3.35.2**, pinned in `.fvmrc`. Every command through `fvm`. Never bare `flutter`.
- **All user-facing copy lives in `lib/core/app_strings.dart`.** No literals in a screen. Review-rejection criterion.
- **No one-off sub-widget classes.** Screens own their layout inline; a `StatefulWidget` split for controllers is fine.
- **Every repository is registered in `app.dart` and read with `context.read<T>()`. No `?? ConcreteImpl(...)` fallback in new code.** `TimelineScreen` and `SettingsScreen` keep theirs by explicit decision — do not copy them and do not migrate them.
- **Every new cubit mixes in `ReentrancyGuard`** from `lib/core/reentrancy_guard.dart` and routes actions through `guard(key, body)`. A state check is not a substitute: the in-flight state is often emitted after the first `await`, and that window is where a double-tap lands. Here a double-tap burns real delivery capacity.
- **`supabase/config.toml` must keep `[auth.sms] enable_confirmations = true`** (line 252 under `[auth.sms]`; the `false` at 209 is `[auth.email]`, unrelated and correct). It is the fix for a reproduced total-account-takeover bug and nothing tests it.
- **One phone number per contract-test suite.** `flutter test` runs files concurrently and GoTrue's rate limit is cross-process; two suites sharing a number has produced a failure in an untouched file twice on this project. Existing: auth `001`+`002`, contacts `003`, graph `004`+`006`, settings `005`, person `007`, wish `008`+`011`, profile `009`+`012`, e2e `010`. **This phase uses `+919999000013`**, added in Task 1 — the only `config.toml` edit of the phase.
- **New `public` functions executable by `authenticated` extend the R3 allowlist** in `supabase/tests/database/11_rls_coverage.test.sql`, or the suite fails from cold. New `private` functions extend `01_private.test.sql`.
- **SQLSTATE is a public API decision** — PostgREST maps it to an HTTP status. Class 45 in use: `45001` self-celebration, `45002` no edge, `45003` person claimed, `45004` person not visible. This phase adds **`45005`**.
- **`private.can_see_person` returns NULL, not false**, for a caller with no claimed person row, and plpgsql's `if not NULL then` never branches. Any indirect visibility check needs `coalesce(..., false)`. Recorded in `docs/db.md:175-185`.
- **A green suite is not evidence.** Every new assertion must be watched to FAIL with its implementation reverted. Eight tests across earlier phases passed against the exact bug they were written to catch.
- **In widget tests `find.byType` defaults to `skipOffstage: true`** and Navigator marks a covered route offstage — pass `skipOffstage: false` when counting screens.
- **Contract tests must use `test/support/contract_test_harness.dart`** — `setUpContractTestEnvironment()` as the first statement of `setUpAll`, before any Supabase client is constructed, OTP through its throttle. Never re-inlined: without it Flutter's test binding fakes every `dart:io` request with a 400 stub and the test reaches nothing.
- **Any route reached with `context.go` needs an explicit `leading` back affordance** — `go` replaces the page stack, so `canPop()` is false and no arrow renders. This has shipped as a trap three times on this project.
- **Every gift status transition writes a `public.gift_events` row.** `create_gift` writes `null → draft`; M4's ops console reads that table.
- Read `docs/db.md` before touching anything in `supabase/`.

---

## File Structure

**Backend (Tasks 1–2)**

| File | Responsibility |
|---|---|
| `supabase/migrations/20260831000001_expire_stale_gifts_cron.sql` | Schedules the existing `expire_stale_gifts` |
| `supabase/tests/database/28_expire_stale_gifts_cron.test.sql` | Proves an expired hold actually releases its slot |
| `supabase/migrations/20260831000002_rpc_create_gift.sql` | The public wrapper and its celebration guard |
| `supabase/tests/database/29_rpc_create_gift.test.sql` | The guard, the oversold path, the sender-cannot-see-address rule |

**Flutter (Tasks 3–8)**

| File | Responsibility |
|---|---|
| `lib/models/service_area.dart`, `product.dart`, `delivery_slot.dart`, `gift.dart` | Row mappings |
| `lib/repositories/gift_repository.dart` (+`_impl`) | Catalog reads, draft creation, the sender's list |
| `lib/features/gifting/catalog_cubit.dart`, `catalog_state.dart`, `catalog_screen.dart` | Service area → product |
| `lib/features/gifting/slot_picker_screen.dart` | Slots with remaining capacity |
| `lib/features/gifting/draft_cubit.dart`, `draft_state.dart`, `draft_screen.dart` | Message, create, the dead-end notice |
| `lib/features/gifting/gift_list_cubit.dart`, `gift_list_state.dart`, `gift_list_screen.dart` | The sender's own gifts |
| `lib/router/app_router.dart` | `/gift/new/:personId`, `/gift/slots`, `/gift/draft`, `/gifts` |

Tests mirror `lib/` under `test/`; contract tests under `test/repositories/`.

---

## Task 1: Schedule the abandoned-hold sweep

Spec §4. `private.expire_stale_gifts()` shipped in M0 and **nothing calls it**. Slot capacity is a hard constraint (`delivery_slots_not_oversold check (reserved <= capacity)`), so an abandoned draft holds a delivery slot permanently and a real customer eventually cannot book a van that is in fact free.

Unlike M1's deferred drain cron, this needs no credentials and no external service. It is pure SQL.

**Files:**
- Create: `supabase/migrations/20260831000001_expire_stale_gifts_cron.sql`
- Create: `supabase/tests/database/28_expire_stale_gifts_cron.test.sql`
- Modify: `supabase/config.toml` (one test number)

**Interfaces:**
- Consumes: `private.expire_stale_gifts()`, `private.release_slot(bigint)`, `private.gift_transition(bigint, gift_status)`, and the `tests.*` helpers in `supabase/seed.sql`.
- Produces: a `cron.job` named `gift-hold-sweep`. Nothing in Dart consumes it.

- [ ] **Step 1: Add the phone number**

In `supabase/config.toml`, inside the existing `[auth.sms.test_otp]` block, after `919999000012`:

```toml
919999000013 = "123456"
```

Then confirm the guard survives:

```bash
awk '/^\[auth\./{sec=$0} /enable_confirmations/{print NR": "sec" -> "$0}' supabase/config.toml
```

Expected: `[auth.email] -> false` and `[auth.sms] -> true`. **This is the only `config.toml` edit in the phase** — later tasks must not touch it.

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/database/28_expire_stale_gifts_cron.test.sql`:

```sql
begin;
select plan(5);

select tests.as_postgres();

-- 1. The job exists and is scheduled. Without this the sweep never runs and an
--    abandoned draft holds a delivery slot forever.
select is(
  (select count(*)::int from cron.job where jobname = 'gift-hold-sweep'),
  1,
  'the gift-hold sweep is scheduled exactly once'
);

select is(
  (select command from cron.job where jobname = 'gift-hold-sweep'),
  ' select private.expire_stale_gifts(); ',
  'the job calls expire_stale_gifts'
);

-- Build a real draft holding a real slot, then age it past its hold.
select tests.create_user('gifter');

create temporary table sweep_ids as
select
  (select id from public.profiles where handle = 'gifter') as gifter,
  tests.create_person('+919999555001', 'Slot Holder')      as recipient;

insert into public.service_areas (name) values ('Sweep Test Area');

insert into public.products (service_area_id, name, price_minor)
select id, 'Sweep Cake', 50000 from public.service_areas
where name = 'Sweep Test Area';

insert into public.delivery_slots
  (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 7, '09:00', '11:00', 1
from public.service_areas where name = 'Sweep Test Area';

create temporary table sweep_slot as
select s.id as slot_id, p.id as product_id
from public.delivery_slots s
join public.products p on p.service_area_id = s.service_area_id
where s.slot_date = current_date + 7;

select private.create_gift(
  (select gifter from sweep_ids),
  (select recipient from sweep_ids),
  (select product_id from sweep_slot),
  (select slot_id from sweep_slot),
  current_date + 7
);

-- 2. Reserving is what makes the sweep matter: the slot is now full.
select is(
  (select reserved from public.delivery_slots
     where id = (select slot_id from sweep_slot)),
  1,
  'creating a draft reserves the slot'
);

-- Age the hold past expiry, then sweep.
update public.gifts set slot_hold_expires_at = now() - interval '1 minute'
where slot_id = (select slot_id from sweep_slot);

select private.expire_stale_gifts();

-- 3. THE POINT OF THIS TASK. Not "the function ran" -- the capacity came back.
select is(
  (select reserved from public.delivery_slots
     where id = (select slot_id from sweep_slot)),
  0,
  'the sweep releases the slot an abandoned draft was holding'
);

select is(
  (select status::text from public.gifts
     where slot_id = (select slot_id from sweep_slot)),
  'expired',
  'the abandoned draft is marked expired'
);

select * from finish();
rollback;
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd ~/Desktop/Projects/birthday_app
supabase db reset && supabase test db
```

Expected: assertions 1 and 2 fail — no `gift-hold-sweep` job exists. Assertions 3–5 should already pass, because `expire_stale_gifts` itself works; only its scheduling is missing. **If 3–5 fail too, stop and report** — that would mean M0's function is broken, which is a different and larger finding.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20260831000001_expire_stale_gifts_cron.sql`:

```sql
-- Spec 2026-08-30 §4. private.expire_stale_gifts() shipped in M0 and nothing
-- ever called it. Slot capacity is a hard constraint
-- (delivery_slots_not_oversold), so an abandoned draft holds a delivery slot
-- PERMANENTLY and a real customer eventually cannot book a van that is free.
--
-- This is the same shape as M1's "nothing triggers the drain yet", with one
-- difference that makes it fixable now rather than deferred: the drain needed
-- FCM credentials; this needs nothing. It is pure SQL.
--
-- Every ten minutes. The hold is fifteen, so a released slot is bookable again
-- within a few minutes of being abandoned -- fast enough that a sender who
-- reloads sees it free, slow enough to be trivial load.
--
-- unschedule first, guarded by exists(), so re-running a db reset does not
-- accumulate duplicate jobs. A FROM-less select is one synthesized row filtered
-- by WHERE, so when the exists() is false the target list is never evaluated
-- and unschedule is never called. That is a skip, not a call-and-ignore.
select cron.unschedule('gift-hold-sweep')
where exists (select 1 from cron.job where jobname = 'gift-hold-sweep');

select cron.schedule(
  'gift-hold-sweep',
  '*/10 * * * *',
  $$ select private.expire_stale_gifts(); $$
);
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
supabase db reset && supabase test db
```

Expected: `28_expire_stale_gifts_cron.test.sql .. ok`, suite green from cold at **29 files**, up from 28.

- [ ] **Step 6: Prove the release assertion is load-bearing**

Assertion 4 is the one that matters — it is the difference between "the sweep ran" and "the capacity came back". Comment out the `perform private.release_slot(r.slot_id);` line in the **draft** loop of `private.expire_stale_gifts` (in `20260822000008_gift_lifecycle.sql`), run `supabase db reset && supabase test db`, and confirm **assertion 4 fails** while assertion 5 still passes — the gift still expires, the slot just never comes back. Restore exactly.

That asymmetry is the evidence: it proves the assertion tests the release specifically, not the transition.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260831000001_expire_stale_gifts_cron.sql \
        supabase/tests/database/28_expire_stale_gifts_cron.test.sql \
        supabase/config.toml
git commit -m "feat(db): sweep abandoned slot holds

expire_stale_gifts shipped in M0 and nothing called it, so an abandoned
draft held a delivery slot permanently against a hard capacity
constraint."
```

---

## Task 2: The public wrapper and its missing guard

Spec §5. `private.create_gift` already enforces a non-null sender, no self-gifting, product availability, and that the slot belongs to the product's service area. It does **not** check that the sender celebrates the recipient — and it takes `p_recipient_person_id` directly, where `people.id` is a sequential bigint. A caller could aim a gift at a stranger by guessing an id, and learn the id exists.

**Files:**
- Create: `supabase/migrations/20260831000002_rpc_create_gift.sql`
- Create: `supabase/tests/database/29_rpc_create_gift.test.sql`
- Modify: `supabase/tests/database/11_rls_coverage.test.sql` (R3 allowlist)

**Interfaces:**
- Consumes: `private.create_gift(uuid, bigint, bigint, bigint, date, text, int)`.
- Produces: `public.rpc_create_gift(p_recipient_person_id bigint, p_product_id bigint, p_slot_id bigint, p_occasion_date date, p_message text) returns public.gifts`. Raises `45005` when the caller holds no celebration edge. Task 4's `GiftRepositoryImpl.createDraft` calls it.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/29_rpc_create_gift.test.sql`:

```sql
begin;
select plan(6);

select tests.as_postgres();
select tests.create_user('sender');
select tests.create_user('stranger');

create temporary table gift_ids as
select
  (select id from public.profiles where handle = 'sender')   as sender,
  (select id from public.profiles where handle = 'stranger') as stranger,
  tests.create_person('+919999556001', 'Gift Friend')        as friend;
grant select on gift_ids to authenticated;

insert into public.service_areas (name) values ('Gift Test Area');
insert into public.products (service_area_id, name, price_minor)
select id, 'Gift Cake', 50000 from public.service_areas where name = 'Gift Test Area';
insert into public.delivery_slots
  (service_area_id, slot_date, window_start, window_end, capacity)
select id, current_date + 7, '09:00', '11:00', 1
from public.service_areas where name = 'Gift Test Area';

create temporary table gift_catalog as
select s.id as slot_id, p.id as product_id
from public.delivery_slots s
join public.products p on p.service_area_id = s.service_area_id
where s.slot_date = current_date + 7;
grant select on gift_catalog to authenticated;

-- The sender celebrates the friend. The stranger does not.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select sender, friend, 'contacts' from gift_ids;

-- 1. The happy path.
select tests.as_user((select sender from gift_ids));
select lives_ok(
  $$ select public.rpc_create_gift(
       (select friend from gift_ids),
       (select product_id from gift_catalog),
       (select slot_id from gift_catalog),
       current_date + 7,
       'Happy birthday!') $$,
  'a sender can draft a gift for someone they celebrate'
);

-- 2. THE PRODUCT'S CORE PROMISE. delivery_city is written only at
--    confirmation, so a sender looking at their own gift sees no city yet.
select is(
  (select delivery_city from public.gifts
     where sender_profile_id = (select sender from gift_ids)),
  null,
  'a draft carries no city -- it is written only at confirmation'
);

-- 3. The sender cannot reach the address row a gift points at. Nothing points
--    at one yet in a draft, but the policy is what must hold, not the null.
select is(
  (select count(*)::int from public.addresses),
  0,
  'no address is readable by the sender'
);

-- 4. THE GUARD THIS TASK ADDS. people.id is a sequential bigint, so without
--    it a caller aims a gift at a stranger by guessing, and learns the id
--    exists.
select tests.as_user((select stranger from gift_ids));
select throws_ok(
  $$ select public.rpc_create_gift(
       (select friend from gift_ids),
       (select product_id from gift_catalog),
       (select slot_id from gift_catalog),
       current_date + 7,
       null) $$,
  '45005',
  null,
  'a caller who does not celebrate the recipient cannot draft a gift'
);

-- 5. The oversold path. Capacity is 1 and assertion 1 took it. Two users
--    racing for the last slot is a legitimate outcome, and 23514 is how the
--    UI learns to say "that slot just filled" rather than "something went
--    wrong".
select tests.as_postgres();
insert into public.celebrations (celebrator_profile_id, person_id, source)
select stranger, friend, 'contacts' from gift_ids;

select tests.as_user((select stranger from gift_ids));
select throws_ok(
  $$ select public.rpc_create_gift(
       (select friend from gift_ids),
       (select product_id from gift_catalog),
       (select slot_id from gift_catalog),
       current_date + 7,
       null) $$,
  '23514',
  null,
  'a full slot refuses with the oversold constraint, not a generic error'
);

-- 6. It is an authenticated door.
select tests.as_anon();
select throws_ok(
  $$ select public.rpc_create_gift(1::bigint, 1::bigint, 1::bigint,
       current_date, null) $$,
  '42501',
  null,
  'anon cannot execute the function'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase db reset && supabase test db
```

Expected: `function public.rpc_create_gift(bigint, bigint, bigint, date, text) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260831000002_rpc_create_gift.sql`:

```sql
-- Spec 2026-08-30 §5. private.create_gift already enforces a non-null sender,
-- no self-gifting, product availability, and that the slot belongs to the
-- product's service area. It does NOT check that the sender celebrates the
-- recipient, and it takes p_recipient_person_id directly -- where people.id is
-- a sequential bigint. Without this wrapper a caller aims a gift at a stranger
-- by guessing an id, and learns the id exists.
--
-- The sender is derived from auth.uid() rather than taken as an argument, so a
-- caller cannot draft a gift as somebody else.
--
-- 45005 is the next unassigned class-45 code (45001 self-celebration, 45002 no
-- edge, 45003 person claimed, 45004 person not visible). docs/db.md: SQLSTATE
-- is a public API decision because PostgREST maps it to an HTTP status.
--
-- The celebration test is a direct `exists` against public.celebrations, NOT a
-- call to private.can_see_person -- that helper returns NULL rather than false
-- for a caller with no claimed person row, and `if not NULL then` never
-- branches (docs/db.md:175-185). An exists() cannot return NULL, so no
-- coalesce is needed here. Anything indirect would need one.
create or replace function public.rpc_create_gift(
  p_recipient_person_id bigint,
  p_product_id bigint,
  p_slot_id bigint,
  p_occasion_date date,
  p_message text default null
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender uuid := auth.uid();
begin
  if not exists (
    select 1
    from public.celebrations c
    where c.person_id = p_recipient_person_id
      and c.celebrator_profile_id = v_sender
  ) then
    raise exception 'you do not celebrate this person'
      using errcode = '45005';
  end if;

  return private.create_gift(
    v_sender,
    p_recipient_person_id,
    p_product_id,
    p_slot_id,
    p_occasion_date,
    p_message
  );
end;
$$;

-- R12/R16 (docs/db.md): `revoke ... from public` also strips `authenticated`,
-- which holds EXECUTE only through the PUBLIC grant. The grant back is not
-- redundant -- without it the function is unreachable by the app.
revoke execute on function public.rpc_create_gift(
  bigint, bigint, bigint, date, text) from public, anon;
grant execute on function public.rpc_create_gift(
  bigint, bigint, bigint, date, text) to authenticated;
```

- [ ] **Step 4: Add it to the R3 allowlist**

`supabase/tests/database/11_rls_coverage.test.sql` allowlists public functions executable by `authenticated`. Add `rpc_create_gift` in alphabetical position. Without this the suite is not green from cold — Phase 2b's Task 1 and Phase 3's Task 1 both hit exactly this.

- [ ] **Step 5: Run the test to verify it passes**

```bash
supabase db reset && supabase test db
```

Expected: **30 files** green from cold.

- [ ] **Step 6: Prove two guards can fail**

For each, revert and confirm **that specific assertion** fails, then restore.

1. Remove the celebration `if not exists (...)` block → assertion 4 (`45005`) must fail.
2. Remove `revoke execute ... from public, anon` → assertion 6 (`42501`) must fail.

Expected: two observed failures. If either passes with its guard removed, the assertion is testing nothing and must be rewritten before continuing.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260831000002_rpc_create_gift.sql \
        supabase/tests/database/29_rpc_create_gift.test.sql \
        supabase/tests/database/11_rls_coverage.test.sql
git commit -m "feat(db): the public gift-draft wrapper and its celebration guard

create_gift never checked that the sender celebrates the recipient, and
people.id is a sequential bigint -- so a caller could aim a gift at a
stranger by guessing an id."
```

---

## Task 3: The catalog and gift models

Spec §8. Four row mappings. `DeliverySlot` carries the only real logic in the set — remaining capacity, and whether it can still be booked.

**Files:**
- Create: `lib/models/service_area.dart`, `lib/models/product.dart`, `lib/models/delivery_slot.dart`, `lib/models/gift.dart`
- Create: `test/models/delivery_slot_test.dart`, `test/models/gift_test.dart`
- Modify: `lib/api/api_params.dart`

**Interfaces:**
- Consumes: `ApiParams`.
- Produces: `ServiceArea(id, name)`; `Product(id, serviceAreaId, name, flavour, size, priceMinor, imageUrl)`; `DeliverySlot(id, serviceAreaId, slotDate, windowStart, windowEnd, capacity, reserved)` with `int get remaining` and `bool get isBookable`; `GiftStatus` enum with `fromWire`; `Gift(id, recipientPersonId, productId, slotId, occasionDate, amountMinor, message, status, deliveryCity, slotHoldExpiresAt)` with `bool get isHoldExpired`. Tasks 4–8 consume all four.

- [ ] **Step 1: Add the column names**

Append to `lib/api/api_params.dart`:

```dart
  // catalog
  static const serviceAreas = 'service_areas';
  static const products = 'products';
  static const deliverySlots = 'delivery_slots';
  static const gifts = 'gifts';
  static const serviceAreaId = 'service_area_id';
  static const name = 'name';
  static const flavour = 'flavour';
  static const size = 'size';
  static const priceMinor = 'price_minor';
  static const imageUrl = 'image_url';
  static const isActive = 'is_active';
  static const slotDate = 'slot_date';
  static const windowStart = 'window_start';
  static const windowEnd = 'window_end';
  static const capacity = 'capacity';
  static const reserved = 'reserved';

  // gifts
  static const senderProfileId = 'sender_profile_id';
  static const recipientPersonId = 'recipient_person_id';
  static const productId = 'product_id';
  static const slotId = 'slot_id';
  static const occasionDate = 'occasion_date';
  static const amountMinor = 'amount_minor';
  static const status = 'status';
  static const message = 'message';
  static const deliveryCity = 'delivery_city';
  static const slotHoldExpiresAt = 'slot_hold_expires_at';

  // rpc_create_gift
  static const pRecipientPersonId = 'p_recipient_person_id';
  static const pProductId = 'p_product_id';
  static const pSlotId = 'p_slot_id';
  static const pOccasionDate = 'p_occasion_date';
  static const pMessage = 'p_message';
```

`ApiParams.id` and `createdAt` already exist — do not re-add them. `ApiParams.body` also exists but belongs to `wishes`; it is not the gift's message column.

- [ ] **Step 2: Write the failing tests**

Create `test/models/delivery_slot_test.dart`:

```dart
import 'package:birthday_app/models/delivery_slot.dart';
import 'package:flutter_test/flutter_test.dart';

DeliverySlot _slot({required int capacity, required int reserved}) =>
    DeliverySlot(
      id: 1,
      serviceAreaId: 1,
      slotDate: DateTime(2026, 9, 6),
      windowStart: '09:00',
      windowEnd: '11:00',
      capacity: capacity,
      reserved: reserved,
    );

void main() {
  test('remaining is capacity minus reserved', () {
    expect(_slot(capacity: 5, reserved: 2).remaining, 3);
  });

  test('a slot with room is bookable', () {
    expect(_slot(capacity: 5, reserved: 2).isBookable, isTrue);
  });

  // The screen disables a full slot rather than letting the user find out by
  // hitting the oversold constraint.
  test('a full slot is not bookable', () {
    expect(_slot(capacity: 2, reserved: 2).isBookable, isFalse);
    expect(_slot(capacity: 2, reserved: 2).remaining, 0);
  });

  // delivery_slots_not_oversold makes this impossible in the database, but the
  // client must not render a negative if a row ever arrives inconsistent.
  test('remaining never goes below zero', () {
    expect(_slot(capacity: 1, reserved: 3).remaining, 0);
    expect(_slot(capacity: 1, reserved: 3).isBookable, isFalse);
  });

  test('a zero-capacity slot is never bookable', () {
    expect(_slot(capacity: 0, reserved: 0).isBookable, isFalse);
  });
}
```

Create `test/models/gift_test.dart`:

```dart
import 'package:birthday_app/models/gift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GiftStatus.fromWire', () {
    test('maps every state the database can emit', () {
      expect(GiftStatus.fromWire('draft'), GiftStatus.draft);
      expect(GiftStatus.fromWire('paid'), GiftStatus.paid);
      expect(GiftStatus.fromWire('awaiting_confirm'),
          GiftStatus.awaitingConfirm);
      expect(GiftStatus.fromWire('confirmed'), GiftStatus.confirmed);
      expect(GiftStatus.fromWire('placed'), GiftStatus.placed);
      expect(GiftStatus.fromWire('out_for_delivery'),
          GiftStatus.outForDelivery);
      expect(GiftStatus.fromWire('delivered'), GiftStatus.delivered);
      expect(GiftStatus.fromWire('expired'), GiftStatus.expired);
      expect(GiftStatus.fromWire('declined'), GiftStatus.declined);
      expect(GiftStatus.fromWire('delivery_failed'),
          GiftStatus.deliveryFailed);
      expect(GiftStatus.fromWire('refunded'), GiftStatus.refunded);
    });

    // A server that grows a twelfth state must not crash a gift list. The
    // enum has eleven members and the DB enum has eleven; this guards the
    // gap opening later.
    test('an unrecognised state falls back rather than throwing', () {
      expect(GiftStatus.fromWire('teleported'), GiftStatus.unknown);
    });
  });

  group('isHoldExpired', () {
    test('a draft past its hold is expired', () {
      final g = Gift(
        id: 1,
        recipientPersonId: 1,
        productId: 1,
        slotId: 1,
        occasionDate: DateTime(2026, 9, 6),
        amountMinor: 50000,
        status: GiftStatus.draft,
        slotHoldExpiresAt: DateTime(2026, 8, 30, 10, 0),
      );
      expect(g.isHoldExpiredAt(DateTime(2026, 8, 30, 10, 1)), isTrue);
      expect(g.isHoldExpiredAt(DateTime(2026, 8, 30, 9, 59)), isFalse);
    });

    // Only a draft holds a slot. A paid gift past that timestamp is not
    // "expired" in any sense the user should be shown.
    test('a non-draft is never reported as hold-expired', () {
      final g = Gift(
        id: 1,
        recipientPersonId: 1,
        productId: 1,
        slotId: 1,
        occasionDate: DateTime(2026, 9, 6),
        amountMinor: 50000,
        status: GiftStatus.paid,
        slotHoldExpiresAt: DateTime(2026, 8, 30, 10, 0),
      );
      expect(g.isHoldExpiredAt(DateTime(2026, 8, 30, 11, 0)), isFalse);
    });
  });
}
```

- [ ] **Step 3: Run to verify they fail, then write the models**

```bash
fvm flutter test test/models/delivery_slot_test.dart test/models/gift_test.dart
```

Expected: FAIL — the URIs do not exist.

`lib/models/delivery_slot.dart`:

```dart
import '../api/api_params.dart';

/// A delivery window. `remaining` is public information — it is a van's
/// schedule, not anyone's personal data — so the picker shows it.
class DeliverySlot {
  const DeliverySlot({
    required this.id,
    required this.serviceAreaId,
    required this.slotDate,
    required this.windowStart,
    required this.windowEnd,
    required this.capacity,
    required this.reserved,
  });

  final int id;
  final int serviceAreaId;
  final DateTime slotDate;
  final String windowStart;
  final String windowEnd;
  final int capacity;
  final int reserved;

  /// Clamped at zero. `delivery_slots_not_oversold` makes a negative
  /// impossible in the database, but a client must never render one.
  int get remaining => (capacity - reserved).clamp(0, capacity);

  bool get isBookable => remaining > 0;

  factory DeliverySlot.fromRow(Map<String, dynamic> row) => DeliverySlot(
        id: row[ApiParams.id] as int,
        serviceAreaId: row[ApiParams.serviceAreaId] as int,
        slotDate: DateTime.parse(row[ApiParams.slotDate] as String),
        windowStart: row[ApiParams.windowStart] as String,
        windowEnd: row[ApiParams.windowEnd] as String,
        capacity: row[ApiParams.capacity] as int,
        reserved: row[ApiParams.reserved] as int,
      );
}
```

`lib/models/gift.dart` — the enum carries an `unknown` member so a server that grows a twelfth state degrades instead of crashing a list, exactly as `ImportStatus.fromWire` does:

```dart
import '../api/api_params.dart';

enum GiftStatus {
  draft,
  paid,
  awaitingConfirm,
  confirmed,
  placed,
  outForDelivery,
  delivered,
  expired,
  declined,
  deliveryFailed,
  refunded,
  unknown;

  static GiftStatus fromWire(String value) => switch (value) {
        'draft' => GiftStatus.draft,
        'paid' => GiftStatus.paid,
        'awaiting_confirm' => GiftStatus.awaitingConfirm,
        'confirmed' => GiftStatus.confirmed,
        'placed' => GiftStatus.placed,
        'out_for_delivery' => GiftStatus.outForDelivery,
        'delivered' => GiftStatus.delivered,
        'expired' => GiftStatus.expired,
        'declined' => GiftStatus.declined,
        'delivery_failed' => GiftStatus.deliveryFailed,
        'refunded' => GiftStatus.refunded,
        _ => GiftStatus.unknown,
      };
}

/// A row in public.gifts, as the SENDER sees it.
///
/// [deliveryCity] is null until the recipient confirms — it is denormalised
/// onto the gift at confirmation precisely so the sender can learn the city
/// without any access to the addresses row, which RLS hides from them
/// entirely. In this phase nothing confirms, so it is always null.
class Gift {
  const Gift({
    required this.id,
    required this.recipientPersonId,
    required this.productId,
    required this.slotId,
    required this.occasionDate,
    required this.amountMinor,
    required this.status,
    this.message,
    this.deliveryCity,
    this.slotHoldExpiresAt,
  });

  final int id;
  final int recipientPersonId;
  final int productId;
  final int? slotId;
  final DateTime occasionDate;
  final int amountMinor;
  final GiftStatus status;
  final String? message;
  final String? deliveryCity;
  final DateTime? slotHoldExpiresAt;

  /// Only a draft holds a slot, so only a draft can have a hold that lapsed.
  bool isHoldExpiredAt(DateTime now) =>
      status == GiftStatus.draft &&
      slotHoldExpiresAt != null &&
      now.isAfter(slotHoldExpiresAt!);

  factory Gift.fromRow(Map<String, dynamic> row) => Gift(
        id: row[ApiParams.id] as int,
        recipientPersonId: row[ApiParams.recipientPersonId] as int,
        productId: row[ApiParams.productId] as int,
        slotId: row[ApiParams.slotId] as int?,
        occasionDate: DateTime.parse(row[ApiParams.occasionDate] as String),
        amountMinor: row[ApiParams.amountMinor] as int,
        status: GiftStatus.fromWire(row[ApiParams.status] as String),
        message: row[ApiParams.message] as String?,
        deliveryCity: row[ApiParams.deliveryCity] as String?,
        slotHoldExpiresAt: row[ApiParams.slotHoldExpiresAt] == null
            ? null
            : DateTime.parse(row[ApiParams.slotHoldExpiresAt] as String),
      );
}
```

**A trap worth naming:** `ApiParams.body` is `'body'` — the **wishes** column, added in a previous phase. `gifts.message` is a different column, so `Gift.fromRow` uses `ApiParams.message`, added above. Reusing `body` here compiles, analyzes clean, and silently returns null for every gift message.

`lib/models/service_area.dart` and `lib/models/product.dart` are plain field mappings in the same shape.

**Check each column's nullability against `supabase/migrations/20260822000006_catalog_slots.sql` rather than inferring it.** `service_areas.name` is `not null`. In `products`, `name` and `price_minor` are `not null`, but **`flavour`, `size` and `image_url` are all nullable** — type those `String?` and cast them `as String?`. Getting this wrong is not a type nit: `Product.fromRow` throws a `TypeError`, the repository's `catch (e) => mapError(e)` flattens it into a code-less `ServerFailure`, and because `productsIn()` maps a list, one product missing a flavour takes down the whole service area's catalog. The only product fixture in `seed.sql` fills every column, so no test in this plan would catch it. (Found in Task 3; an earlier draft described these two models in prose and left nullability to inference.) — `fromRow` reading through `ApiParams`, all fields `final`, `const` constructor. `Product.priceMinor` stays an `int` of minor units; do not add currency formatting to the model.

- [ ] **Step 4: Run to verify they pass**

```bash
fvm flutter test test/models/
```

Expected: `All tests passed!` — 10 new assertions.

- [ ] **Step 5: Prove the clamp is load-bearing**

Change `remaining` to `capacity - reserved` with no `clamp`. Re-run. Expected: **`remaining never goes below zero` fails**, and nothing else does. Restore.

- [ ] **Step 6: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/models lib/api/api_params.dart test/models
git commit -m "feat(models): catalog and gift row mappings

DeliverySlot.remaining clamps at zero: the DB constraint makes a
negative impossible, but a client must never render one."
```

---

## Task 4: `GiftRepository` and its contract tests

Spec §8, §9. Catalog reads, draft creation, and the sender's list. One responsibility, registered in `app.dart`, never constructed in a screen.

**Files:**
- Create: `lib/repositories/gift_repository.dart`, `lib/repositories/gift_repository_impl.dart`
- Create: `test/repositories/gift_repository_test.dart`
- Modify: `lib/app.dart`, `lib/api/api_endpoints.dart`

**Interfaces:**
- Consumes: `ApiClient.instance`, `ApiParams`, `mapError`, and the models from Task 3.
- Produces: `abstract interface class GiftRepository` with `Future<List<ServiceArea>> serviceAreas()`, `Future<List<Product>> productsIn(int serviceAreaId)`, `Future<List<DeliverySlot>> slotsIn(int serviceAreaId, {required DateTime onOrAfter})`, `Future<Gift> createDraft({required int recipientPersonId, required int productId, required int slotId, required DateTime occasionDate, String? message})`, and `Future<List<Gift>> myGifts()`. Throws `ServerFailure` with code `45005` when the caller does not celebrate the recipient, and `23514` when the slot is full. Tasks 5–8 consume it.

- [ ] **Step 1: Write the failing contract test**

Create `test/repositories/gift_repository_test.dart`, signing in as **`+919999000013`**. Follow the exact shape of `test/repositories/person_repository_test.dart` — `@Tags(['contract'])`, `setUpContractTestEnvironment()` as the first statement of `setUpAll`, OTP through the harness throttle.

Seeding note: this suite needs catalog rows, which no repository can create. Insert them through the authenticated client is **not** possible — `products_staff_write` requires staff. Seed them with a direct Postgres connection, the same mechanism `add_celebrations/index.test.ts` uses for suppressions, and tear them down afterwards so a second run is clean.

Cover these seven behaviours:

```dart
// 1. serviceAreas() returns active areas.
// 2. productsIn() returns only that area's active products.
// 3. slotsIn() returns slots on or after the given date, with capacity and
//    reserved populated so the picker can compute `remaining`.
// 4. createDraft() for a person the caller celebrates returns a Gift in
//    GiftStatus.draft, with slotHoldExpiresAt set roughly 15 minutes out.
//    Seed the celebration through ContactsRepositoryImpl, not raw SQL, so the
//    test proves the repository works against rows the app itself creates.
// 5. createDraft() for a person the caller does NOT celebrate throws
//    ServerFailure with code '45005', pinned with
//    .having((f) => f.code, 'code', '45005'). This is the assertion that stops
//    the sequential id space being walked.
// 6. createDraft() into a full slot throws ServerFailure with code '23514'.
//    Seed a capacity-1 slot, take it, then try again. Pin the code — the UI
//    branches on it to say "that slot just filled" rather than a generic error.
// 7. myGifts() returns the caller's own drafts and NOT another sender's, and
//    every returned gift has deliveryCity == null. THE PRODUCT'S CORE PROMISE:
//    the city is written only at confirmation.
```

Assertions 5, 6 and 7 are the ones that matter. A matcher accepting any `ServerFailure` would pass even when the wrong guard fired.

- [ ] **Step 2: Run to verify it fails**

```bash
supabase start && supabase functions serve &
fvm flutter test test/repositories/gift_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: FAIL — the URIs do not exist. **If the OTP is refused via real Twilio, the local stack has stale GoTrue config — do `supabase stop && supabase start` before suspecting your code.** Two earlier phases lost time to exactly this.

- [ ] **Step 3: Write the interface**

Create `lib/repositories/gift_repository.dart`:

```dart
import '../models/delivery_slot.dart';
import '../models/gift.dart';
import '../models/product.dart';
import '../models/service_area.dart';

/// Everything the sender's gifting flow reads and writes. One responsibility;
/// deliberately not folded into GraphRepository or PersonRepository.
abstract interface class GiftRepository {
  Future<List<ServiceArea>> serviceAreas();

  Future<List<Product>> productsIn(int serviceAreaId);

  /// Slots for an area on or after [onOrAfter], with `capacity` and `reserved`
  /// so the picker can show what is left.
  Future<List<DeliverySlot>> slotsIn(
    int serviceAreaId, {
    required DateTime onOrAfter,
  });

  /// Drafts a gift and reserves the slot for fifteen minutes.
  ///
  /// Throws [ServerFailure] with code `45005` when the caller does not
  /// celebrate the recipient, and `23514` when the slot just filled — that
  /// second one is a race two users hit legitimately, not a fault.
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  });

  /// The caller's own gifts. `deliveryCity` is null until the recipient
  /// confirms; nothing in this phase confirms.
  Future<List<Gift>> myGifts();
}
```

Add to `lib/api/api_endpoints.dart`:

```dart
  static const rpcCreateGift = 'rpc_create_gift';
```

- [ ] **Step 4: Write the implementation**

`lib/repositories/gift_repository_impl.dart` follows the shape of `lib/repositories/person_repository_impl.dart` exactly: a `const` constructor taking `SupabaseClient`, every method wrapping its call in `try { … } catch (e) { throw mapError(e); }` so `PostgrestException.code` survives into `ServerFailure.code`.

`createDraft` calls the RPC and maps the returned row:

```dart
  @override
  Future<Gift> createDraft({
    required int recipientPersonId,
    required int productId,
    required int slotId,
    required DateTime occasionDate,
    String? message,
  }) async {
    try {
      final row = await _client.rpc(
        ApiEndpoints.rpcCreateGift,
        params: {
          ApiParams.pRecipientPersonId: recipientPersonId,
          ApiParams.pProductId: productId,
          ApiParams.pSlotId: slotId,
          ApiParams.pOccasionDate:
              occasionDate.toIso8601String().split('T').first,
          ApiParams.pMessage: message,
        },
      );
      return Gift.fromRow(row as Map<String, dynamic>);
    } catch (e) {
      throw mapError(e);
    }
  }
```

`myGifts` filters on the signed-in user, rather than relying on `gifts_select_participants` alone — correct today, but silently over-fetching if a policy ever loosens:

```dart
      .from(ApiParams.gifts)
      .select()
      .eq(ApiParams.senderProfileId, userId)
      .order(ApiParams.createdAt, ascending: false);
```

- [ ] **Step 5: Register it in `app.dart`**

```dart
  late final GiftRepository _gift = GiftRepositoryImpl(ApiClient.instance);
```

```dart
        RepositoryProvider<GiftRepository>.value(value: _gift),
```

**No `?? GiftRepositoryImpl(...)` fallback anywhere.**

- [ ] **Step 6: Run to verify it passes**

Expected: `All tests passed!` — 7 tests.

- [ ] **Step 7: Prove the celebration guard reaches the client**

Comment out the `if not exists (...)` block in `supabase/migrations/20260831000002_rpc_create_gift.sql`, run `supabase db reset`, and confirm **assertion 5 fails**. Restore.

Task 2 proved that guard from SQL; this proves the client surfaces `45005` rather than flattening it into a generic failure. Different claims, both needed.

- [ ] **Step 8: Commit**

```bash
git add lib/repositories/gift_repository.dart lib/repositories/gift_repository_impl.dart \
        lib/api/api_endpoints.dart lib/app.dart test/repositories/gift_repository_test.dart
git commit -m "feat(gift): catalog reads, draft creation and the sender's list

myGifts filters on sender_profile_id rather than relying on the RLS
policy alone -- correct today, silently over-fetching if it loosens."
```

---

## Task 5: The catalog screen

Spec §7. Service area, then the active products in it. Reached from a person page's "Send a cake" action, since you gift someone you celebrate.

**Files:**
- Create: `lib/features/gifting/catalog_cubit.dart`, `catalog_state.dart`, `catalog_screen.dart`
- Create: `test/features/gifting/catalog_cubit_test.dart`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart`, `lib/features/person/person_screen.dart`

**Interfaces:**
- Consumes: `GiftRepository` (Task 4), `ReentrancyGuard` (Phase 3).
- Produces: `CatalogCubit(GiftRepository)` with `load()` and `selectArea(int)`; `CatalogState` = `CatalogLoading | CatalogLoaded(areas, selectedAreaId, products) | CatalogError(message)`. Route `/gift/new/:personId`.

- [ ] **Step 1: Add the strings**

```dart
  // Gifting
  static const giftSendCake = 'Send a cake';
  static const giftCatalogTitle = 'Choose a cake';
  static const giftAreaLabel = 'Delivering to';
  static const giftNoAreas = 'No delivery areas are available yet.';
  static const giftNoProducts = 'Nothing available in this area yet.';
  static const giftPriceTemplate = '₹%s';
```

- [ ] **Step 2: Write the failing Cubit test**

Create `test/features/gifting/catalog_cubit_test.dart` with a fake `GiftRepository`. Cover:

```dart
// 1. load() emits CatalogLoading then CatalogLoaded with the areas, the first
//    area preselected, and that area's products.
// 2. selectArea() swaps the products without refetching the areas — assert the
//    fake recorded ONE serviceAreas() call and TWO productsIn() calls.
// 3. An empty area list still loads (CatalogLoaded with no areas), not an
//    error screen. A pilot with no service area configured is a normal state.
// 4. A failing serviceAreas() surfaces as CatalogError with a human message.
//    Assert a non-AppFailure falls back to AppStrings.somethingWentWrong —
//    that is the discriminating assertion; an "Instance of" check alone would
//    pass merely because AppFailure.toString() exists.
// 5. A second load() while the first is in flight is ignored (ReentrancyGuard).
```

- [ ] **Step 3: Run to verify it fails, then write the state, cubit and screen**

`CatalogCubit extends Cubit<CatalogState> with ReentrancyGuard`, every action through `guard(key, body)`. Error handling in the `lib/features/timeline/timeline_cubit.dart` shape — `on AppFailure catch (f)` then `catch (_)`, **never `'$e'`**.

`catalog_screen.dart`: a dropdown or segmented control of areas, then a list of products showing name, flavour/size and price. Price renders through `giftPriceTemplate` with the minor units converted — the conversion lives in a `String priceLabel(int minor)` helper on `Product`, not inline in the screen, so the rule sits with the value object.

**An explicit `leading` back affordance** to `/person/:personId` — `context.go` replaces the stack, so no arrow renders by default. This has shipped as a trap three times.

Tapping a product **pushes** the slot picker with `Navigator.push`, carrying the chosen product forward.

**Only `/gift/new/:personId` is a route.** The slot picker and the draft screen are not, and must not be added to the router. Both are parameterless and neither can carry the selection accumulating across the three screens — the person and their birthday from the person page, the product from here, the slot from the picker. A URL-addressable `/gift/draft` would render with no product and no slot. This is the precedent set for `OtpScreen` in M1 Phase 2b, which is pushed rather than routed for exactly the same reason. (`/gifts` in Task 8 *is* a route: parameterless and genuinely addressable, since it only loads the signed-in user's own gifts.)

- [ ] **Step 4: Wire the route and the entry point**

Add `/gift/new/:personId` to the router. Because it carries a path parameter, the redirect guard must match it by **prefix**, exactly as `/person/:personId` does — a literal `signedIn` membership test never matches the substituted path and the screen becomes unreachable while compiling and analyzing clean. Extend the existing `startsWith` check rather than adding the template to the set.

In `lib/features/person/person_screen.dart`, add a "Send a cake" action, shown under the **same condition as the compose FAB** — the person has a birthday and `viewerCelebrates` is true. The RPC refuses without a celebration edge, so offering it otherwise leads to an error the user cannot act on.

- [ ] **Step 5: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/features/gifting lib/router/app_router.dart \
        lib/features/person/person_screen.dart lib/core/app_strings.dart test/features/gifting
git commit -m "feat(gifting): the catalog screen"
```

---

## Task 6: The slot picker

Spec §7. Slots for the chosen area, each showing what is left.

**Files:**
- Create: `lib/features/gifting/slot_picker_screen.dart`
- Create: `test/features/gifting/slot_picker_screen_test.dart`
- Modify: `lib/core/app_strings.dart`

**Interfaces:**
- Consumes: `GiftRepository.slotsIn`, `DeliverySlot.remaining`, `DeliverySlot.isBookable`.
- Produces: no route. Pushed from the catalog with `Navigator.push`, carrying the product. Selecting a slot pushes the draft screen, carrying product + slot.

- [ ] **Step 1: Add the strings**

```dart
  static const giftSlotTitle = 'Pick a delivery window';
  static const giftSlotRemainingTemplate = '%s left';
  static const giftSlotFull = 'Full';
  static const giftNoSlots = 'No delivery windows are open for this area yet.';
```

- [ ] **Step 2: Write the failing widget test**

Create `test/features/gifting/slot_picker_screen_test.dart`. Cover:

```dart
// 1. A slot with room renders its window and its remaining count, and its
//    onTap is non-null.
// 2. A FULL slot renders AppStrings.giftSlotFull and its onTap is NULL. The
//    screen disables it rather than letting the user discover it by hitting
//    the oversold constraint.
// 3. An empty slot list renders AppStrings.giftNoSlots, not a blank screen.
// 4. The back affordance is present and enabled.
```

Assertion 2 is the point of the screen. If any assertion counts screens, pass `skipOffstage: false`.

- [ ] **Step 3: Run to verify it fails, then write the screen**

A `ListView` of slots grouped by `slotDate`, each row keyed `Key('slot_${slot.id}')`, showing `windowStart`–`windowEnd` and either `giftSlotRemainingTemplate` or `giftSlotFull`. A full slot's `onTap` is `null`, and it renders visibly de-emphasised.

**A back affordance.** This screen is *pushed*, so `Navigator.pop` works and the default arrow renders — unlike the `context.go` routes elsewhere in this app, which need an explicit `leading`. Do not add one here; let the framework supply it.

- [ ] **Step 4: Prove the disable is load-bearing**

Change the row to set `onTap` unconditionally. Re-run. Expected: **assertion 2 fails**. Restore, and paste the transcript. A picker that lets a user select a full slot hands them a `23514` they cannot act on.

- [ ] **Step 5: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/features/gifting lib/router/app_router.dart lib/core/app_strings.dart \
        test/features/gifting
git commit -m "feat(gifting): the slot picker

A full slot is disabled rather than letting the user discover it by
hitting the oversold constraint."
```

---

## Task 7: The draft screen

Spec §7. Recipient, product, slot, an optional message, then create — and an honest statement that the flow stops here.

**Files:**
- Create: `lib/features/gifting/draft_cubit.dart`, `draft_state.dart`, `draft_screen.dart`
- Create: `test/features/gifting/draft_cubit_test.dart`
- Modify: `lib/core/app_strings.dart`

**Interfaces:**
- Consumes: `GiftRepository.createDraft`, `ReentrancyGuard`, `Birthday.nextOccurrence`.
- Produces: `DraftCubit(GiftRepository, {DateTime Function() now})` with `create({recipientPersonId, productId, slotId, birthday, message})`; `DraftState` = `DraftIdle | DraftSaving | DraftCreated(Gift) | DraftError(message, {slotFull})`.

- [ ] **Step 1: Add the strings**

```dart
  static const giftDraftTitle = 'Confirm the details';
  static const giftMessageHint = 'Add a message (optional)';
  static const giftCreate = 'Reserve this slot';
  static const giftSlotJustFilled =
      'That slot just filled. Please pick another window.';
  static const giftNotCelebrating =
      'You can only send a cake to someone you celebrate.';
  static const giftHoldNoticeTitle = 'Slot reserved for 15 minutes';
  static const giftHoldNoticeBody =
      'Checkout is not built yet, so this gift stays a draft and the slot is '
      'released when the hold expires. Nothing has been charged.';
  static const giftSeeMyGifts = 'See my gifts';
```

`giftHoldNoticeBody` is the honest dead-end notice spec §7 requires. **Do not soften it into "payment coming soon"** — a screen implying a payment step is next is worse than one saying plainly that checkout does not exist.

- [ ] **Step 2: Write the failing Cubit test**

Cover:

```dart
// 1. create() emits DraftSaving then DraftCreated carrying the returned Gift.
// 2. The occasion date is DERIVED from the recipient's birthday via
//    Birthday.nextOccurrence(_now()), never taken as an argument. Assert the
//    fake recorded the date that method returns for the injected clock. This
//    is the assertion that keeps a cake dated to the birthday.
// 3. A 23514 surfaces as DraftError with slotFull true and the message
//    AppStrings.giftSlotJustFilled — NOT the generic failure. Two users racing
//    for the last slot is a legitimate outcome.
// 4. A 45005 surfaces as DraftError with AppStrings.giftNotCelebrating.
// 5. Any other ServerFailure surfaces with slotFull false and a human message;
//    a non-AppFailure falls back to AppStrings.somethingWentWrong.
// 6. A second create() while the first is in flight is ignored. Assert the
//    fake recorded ONE createDraft call — a double-tap here burns real
//    delivery capacity, not just a duplicate row.
```

Assertions 2, 3 and 6 are the ones that matter.

- [ ] **Step 3: Run to verify it fails, then write the state, cubit and screen**

`DraftCubit extends Cubit<DraftState> with ReentrancyGuard`. The clock is injected for the same reason `TimelineCubit`'s is — a test reading the real one passes this year and fails next.

`draft_screen.dart` shows the recipient's label, the product, the chosen window, a `TextField` with `maxLength: 280` (matching `gifts_message_length`), and a submit button keyed `Key('gift_create')` disabled while saving.

On `DraftCreated`, show the hold notice with `giftHoldNoticeTitle` / `giftHoldNoticeBody` and a button to `/gifts`. **After an awaited dialog or sheet, check `mounted` before touching `context`** — an earlier phase shipped exactly that bug.

- [ ] **Step 4: Prove the occasion-date derivation is load-bearing**

Break `create` to pass `_now()` instead of `birthday.nextOccurrence(_now())`. Re-run and confirm **assertion 2 fails**. Restore, and paste the transcript.

- [ ] **Step 5: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test --exclude-tags=contract
git add lib/features/gifting lib/router/app_router.dart lib/core/app_strings.dart \
        test/features/gifting
git commit -m "feat(gifting): the draft screen and its honest dead-end notice

The occasion date is derived from the birthday, never asked. A double-tap
on create is guarded because it burns real delivery capacity."
```

---

## Task 8: The gift list, and the phase close

Spec §7, §9.

**Files:**
- Create: `lib/features/gifting/gift_list_cubit.dart`, `gift_list_state.dart`, `gift_list_screen.dart`
- Create: `test/features/gifting/gift_list_cubit_test.dart`
- Create: `docs/superpowers/execution/2026-08-31-m3-phase1a-ledger.md`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart`, `lib/features/profile/profile_screen.dart`

**Interfaces:**
- Consumes: `GiftRepository.myGifts`, `ReentrancyGuard`.
- Produces: `GiftListCubit(GiftRepository, {DateTime Function() now})` with `load()`; route `/gifts`.

- [ ] **Step 1: Add the strings**

```dart
  static const giftListTitle = 'My gifts';
  static const giftListEmpty = 'You have not sent a cake yet.';
  static const giftCityPending = 'Address not confirmed yet';
  static const giftCityTemplate = 'Delivering to %s';
  static const giftHoldExpired = 'Slot hold expired';
```

`giftCityPending` matters: **every gift in this phase has a null city**, and rendering nothing there looks like a bug rather than a state.

- [ ] **Step 2: Write the failing Cubit test**

Cover:

```dart
// 1. load() emits Loading then Loaded with the gifts newest-first.
// 2. An empty list emits a Loaded empty state, not an error.
// 3. A draft past its hold is flagged via Gift.isHoldExpiredAt against the
//    INJECTED clock — a test reading the real clock is a time bomb.
// 4. A failure surfaces with a human message; a non-AppFailure falls back to
//    AppStrings.somethingWentWrong.
// 5. A second load() while the first is in flight is ignored.
```

- [ ] **Step 3: Write the screen and wire it**

Each row shows the product, the occasion date, the status, and either `giftCityTemplate` when `deliveryCity` is non-null or `giftCityPending` when it is not. A draft past its hold shows `giftHoldExpired`.

Add `/gifts` to the router's `signedIn` set — it has no path parameter, so literal membership is correct here, unlike `/gift/new/:personId`. Give it an explicit `leading` back affordance to `/profile`. Add an entry point on the profile screen.

- [ ] **Step 4: Full cold verification**

```bash
supabase db reset && supabase test db          # expect 30 files green from cold
supabase functions serve --no-verify-jwt &
./supabase/functions/test.sh
fvm flutter analyze
fvm flutter test --exclude-tags=contract
fvm flutter test test/repositories test/e2e \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Report the numbers you observe. If any differs from expectation, that is a finding — say so; do not adjust the expectation to match.

- [ ] **Step 5: Re-verify the config guard**

```bash
awk '/^\[auth\./{sec=$0} /enable_confirmations/{print NR": "sec" -> "$0}' supabase/config.toml
```

The `[auth.sms]` occurrence must read `true`. Task 1 edited that file, so this phase is one that can disturb it.

- [ ] **Step 6: Write and commit the ledger**

`docs/superpowers/execution/2026-08-31-m3-phase1a-ledger.md`, **committed** — a previous milestone's ledger lived in git-ignored scratch and was nearly destroyed with it. It must carry: the verification numbers with their commands; the config lines quoted; the per-task commit range; a **"Not verified"** section stating that no end-to-end run of the app on a device has ever been performed for this project and that this phase adds four screens without closing that; and a **"Carried forward"** section taking every `minor (deferred)` and every `Ruling:` line from the controller's running notes.

It must also record the two live carry-forwards from the spec: **the recipient can read `amount_minor`** on a gift aimed at them (`gifts_select_participants` has no column restriction), which becomes live in Phase 1b; and **the suppression oracle** remains reduced but not closed.

- [ ] **Step 7: Do NOT merge**

The merge decision belongs to the human. Stop here.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §4 schedule `expire_stale_gifts` | 1 |
| §5 `rpc_create_gift` + celebration guard + `45005` + `23514` | 2, 4, 7 |
| §6 sender never sees the address; `delivery_city` null until confirmation | 2 (pgTAP), 4 (contract), 8 (rendering) |
| §7 catalog | 5 |
| §7 slot picker | 6 |
| §7 draft + dead-end notice | 7 |
| §7 gift list | 8 |
| §8 architecture — narrow repository, DI, `ReentrancyGuard`, `AppStrings` | 4–8 |
| §9 testing matrix | every task; closed out in 8 |
| §10 risks | 8's ledger |
| §11.1 occasion date derived, not overridable | 7 |
| §11.2 recipient can read `amount_minor` | 8's ledger (live in Phase 1b) |
| §11.3 two slots at once | Deliberately not implemented — the spec defers it, and the 15-minute expiry bounds the damage |

**Known gaps, deliberate**

- Tasks 5–8 specify tests as enumerated behaviours with reasoning rather than literal source. The shapes are established in Tasks 1–4 and in three merged phases. **The enumerated assertions are mandatory, not suggestions.**
- The race test using M0's `tests.race_last_slot` is covered by Task 2's assertion 5 (the oversold path) rather than a separate concurrency task. The helper races two real connections; assertion 5 proves the client-visible outcome, which is what this phase ships.

**Type consistency checked:** `ServiceArea`, `Product`, `DeliverySlot`, `Gift`, `GiftStatus`, `GiftRepository` and its five methods, and the five `ApiParams.p*` RPC argument names are each defined once and referenced identically throughout. `ApiParams.message` is added in Task 3 rather than reusing `ApiParams.body`, which is the wishes column.
