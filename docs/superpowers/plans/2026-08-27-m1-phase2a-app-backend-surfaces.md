# M1 Phase 2a — Backend Surfaces the App Needs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the three server-side doors the Flutter app cannot function without — linking a signed-up user to their person row, minting a person when the user picks a contact, and honouring a per-user reminder preference — plus the local auth configuration that makes phone OTP work at all.

**Architecture:** Same shape Phase 1 established. Business logic stays in `private` functions covered by pgTAP; anything an Edge Function must reach gets a thin `public.rpc_*` wrapper granted to `service_role` only, because PostgREST exposes only `public` and `graphql_public`. Edge Functions add HTTP shape and caller validation, nothing else.

**Tech Stack:** Postgres 17, Supabase CLI 2.78.1, pgTAP, Deno (Edge Functions), Docker via colima.

**Spec:** `docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md`

## Global Constraints

These are Phase 1's hard-won rules. Every task's requirements implicitly include this section.

- **Migrations are append-only.** Never edit a `20260822*` or `20260824*` migration. New migrations only, named `20260827NNNNNN_<topic>.sql`.
- **Every new `private` function ships with `revoke execute on function ... from public, anon, authenticated;`.** A function is `PUBLIC`-executable the moment it is created, and `alter default privileges ... revoke execute` is a **no-op on PG17**. A guard in `01_private.test.sql` asserts the private functions `authenticated` may execute are exactly `can_see_person,is_staff,my_person_id`.
- **`revoke ... from public` also strips `authenticated`** — it held the privilege only via the PUBLIC grant. Any private function an RLS policy calls needs an explicit `grant execute ... to authenticated`.
- **New `public` functions are PUBLIC-executable by default too.** A guard in `11_rls_coverage.test.sql` asserts the public functions `authenticated` may execute are exactly `my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token`. Every `rpc_*` wrapper in this plan is **service_role only** and must NOT change that list.
- **A column-level revoke cannot cut back a table-level grant**, and a new column on `public.profiles` is not client-writable until it is added to that table's column grant list. Updating a non-granted column raises `permission denied for table profiles` — **loudly**, aborting the whole statement even when a granted column appears in the same `SET` list.
- **Other users' profiles are invisible.** `profiles_select_own` means a session reads only its own row, so tests must resolve other users' ids **as `postgres`** before switching role.
- **Observe RED before implementing.** A test that cannot fail is a defect.
- **Every `public` and `private` table needs RLS; every `public` FK column needs an index.** Both are asserted by `11_rls_coverage.test.sql`.
- **CLI 2.78.1 has no `--file` flag.** Use `supabase test db supabase/tests/database/NN_name.test.sql` positionally. A nonexistent path makes Docker create a *directory* — `rmdir` it.
- **`supabase test db` does NOT reset the database.** Run `supabase db reset` before any suite run if you inserted fixtures via psql. This hazard already caused one wrong diagnosis on this project.
- **`supabase functions serve` needs `--env-file`** — prefixed shell variables are silently ignored.
- Identifiers lowercase with underscores. `text`, never `varchar`. `timestamptz`, never `timestamp`.
- **Baseline:** `supabase db reset && supabase test db` currently gives **`Files=19, Tests=168, PASS`**. Per-task figures below are targets; report what you actually get.
- **Bringing the stack up:** `colima start` must run with the sandbox disabled, then `supabase start`.

## Why this plan exists

The Flutter app cannot call `private.claim_person` or `private.upsert_person` — both are revoked from every client role, no `public` wrapper exists, and no Edge Function references them. Verified against the live database:

```
claim_person  executable by authenticated: false
upsert_person executable by authenticated: false
public functions matching claim/person/celebrat: my_celebrates
```

Without those two doors, a user can sign up but never becomes findable, and can never celebrate anyone. Phase 1's spec listed only `resolve_contacts` and `drain_reminders` as Edge Functions; these two were never planned. The Settings notification toggle has no backend either, recorded as the M1 spec's open question 6.

## File Structure

**Modify:**

| File | Responsibility |
|---|---|
| `supabase/config.toml` | Enable SMS signup and the local test-OTP map so phone auth works without a provider |

**New migrations:**

| File | Responsibility |
|---|---|
| `20260827000001_reminder_preference.sql` | `profiles.reminders_enabled`, its column grant, and the fan-out filter |
| `20260827000002_claim_person_rpc.sql` | `public.rpc_claim_person` — service_role wrapper |
| `20260827000003_add_celebration.sql` | `private.add_celebration` + `public.rpc_add_celebration` |

**New tests:**

| File | Responsibility |
|---|---|
| `19_reminder_preference.test.sql` | The toggle is user-writable and the fan-out honours it |
| `20_claim_person_rpc.test.sql` | The wrapper links a profile and is service_role only |
| `21_add_celebration.test.sql` | Mint-and-edge, suppression, idempotency, self-celebration |

**New Edge Functions:**

| File | Responsibility |
|---|---|
| `supabase/functions/claim_profile/index.ts` | Reads the caller's VERIFIED phone from their JWT, claims their person row |
| `supabase/functions/add_celebrations/index.ts` | Batch: mint people and celebration edges for picked contacts |
| `supabase/functions/delete_account/index.ts` | Settings → delete account; a client cannot delete its own auth user |

---

### Task 1: Make phone OTP work locally

Phone OTP is the app's front door and it cannot work as configured: `[auth.sms] enable_signup = false` rejects new phone signups outright, and the test-OTP map is commented out, so there is no way to receive a code without a paid SMS provider. The M1 spec's decision is to build the full flow against the local test provider and swap in a real one at first device test.

**Files:**
- Modify: `supabase/config.toml` (the `[auth.sms]` block, around line 240)

**Interfaces:**
- Consumes: nothing.
- Produces: a working local OTP flow — `POST /auth/v1/otp` then `POST /auth/v1/verify` returns an `access_token`. Tasks 5 and 6 need a real user session to test against.

- [ ] **Step 1: Prove it is broken first**

```bash
curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' \
  -H 'apikey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
  -H 'content-type: application/json' \
  -d '{"phone":"+919999000001"}'
```

Expected: an error — signups via SMS are disabled. Capture the exact body; it is the evidence this task is needed.

- [ ] **Step 2: Enable SMS signup and the test-OTP map**

In `supabase/config.toml`, in the `[auth.sms]` block, change:

```toml
enable_signup = false
```

to:

```toml
# Phone is the app's front door and the whole graph is keyed on a verified
# number, so signup by SMS has to be allowed.
enable_signup = true
```

Then, immediately below the commented `[auth.sms.test_otp]` example, add a real block:

```toml
# Local test numbers. No SMS provider is configured, and the M1 spec's decision
# is to build the full OTP flow against these and swap in a real provider at
# first real-device test. These are LOCAL ONLY — config.toml is not applied to a
# hosted project by `supabase db push`.
[auth.sms.test_otp]
919999000001 = "123456"
919999000002 = "123456"
919999000003 = "123456"
```

**These two changes alone are NOT sufficient** — discovered during execution.
GoTrue refuses every phone request with `phone_provider_disabled` until an SMS
provider is nominally enabled, even when `test_otp` covers every number in use,
and `supabase start` warns "no SMS provider is enabled. Disabling phone login".
Enable the already-scaffolded `[auth.sms.twilio]` block with unmistakably fake
local values (`local_test_sid` / `local_test_msid` / `local_test_token`), and
keep a comment warning against ever putting a real token there as a literal —
every other secret field in this file uses `env(...)` substitution.

**Verify the key format empirically.** Supabase's own example (`4152127777 = "123456"`) is written without a leading `+`. If sign-in fails with these keys, try the `+`-prefixed form, and report which format actually worked — later tasks and the Flutter app both depend on knowing.

**Settled during execution:** the unprefixed form is correct. GoTrue strips the
leading `+` before matching `test_otp` and before storing `auth.users.phone`, so
a verify response returns `user.phone` as `919999000001`. That is why Task 5's
Edge Function re-adds the `+` before hashing — the hash is computed over E.164.

- [ ] **Step 3: Restart the stack so the config is read**

Config changes are read at startup, not hot-reloaded:

```bash
supabase stop && supabase start
```

- [ ] **Step 4: Prove OTP now works end to end**

```bash
PUB=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH

curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' \
  -H "apikey: $PUB" -H 'content-type: application/json' \
  -d '{"phone":"+919999000001"}'

curl -s -X POST 'http://127.0.0.1:54321/auth/v1/verify' \
  -H "apikey: $PUB" -H 'content-type: application/json' \
  -d '{"phone":"+919999000001","token":"123456","type":"sms"}'
```

Expected: the second call returns JSON containing an `access_token` and a `user` whose `phone` is `919999000001`. Paste both bodies (redact the token itself to its first 12 characters).

Then confirm the signup trigger fired:

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select handle, display_name from public.profiles order by created_at desc limit 1;"
```

Expected: a handle like `u<32 hex chars>` and display_name `New user` — that is `private.handle_new_user` doing its job.

- [ ] **Step 5: Confirm the suite is unaffected and commit**

```bash
supabase db reset && supabase test db
```

Expected: `Files=19, Tests=168, PASS` — unchanged; this task touches no schema.

```bash
git add supabase/config.toml
git commit -m "feat(auth): enable phone OTP locally with a test-code map"
```

---

### Task 2: A per-user reminder preference the fan-out honours

The Settings screen has a notification toggle and there is nothing behind it — no column, and `private.enqueue_reminders` consults nothing. Recorded as the M1 spec's open question 6.

**Files:**
- Create: `supabase/migrations/20260827000001_reminder_preference.sql`
- Create: `supabase/tests/database/19_reminder_preference.test.sql`

**Interfaces:**
- Consumes: `public.profiles`, `private.enqueue_reminders(date)`.
- Produces: `public.profiles.reminders_enabled boolean not null default true`, writable by its owner.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/19_reminder_preference.test.sql`:

```sql
begin;
select plan(4);

select has_column('public', 'profiles', 'reminders_enabled',
  'profiles.reminders_enabled exists');

select tests.as_postgres();
select tests.create_user('quiet');
select private.claim_person(
  (select id from public.profiles where handle = 'quiet'), '+919210000001');
select tests.create_person('+919210000002', 'Quiet Friend',
  extract(month from current_date)::smallint,
  extract(day from current_date)::smallint);
insert into public.celebrations (celebrator_profile_id, person_id, source)
values ((select id from public.profiles where handle = 'quiet'),
        (select id from public.people where display_name = 'Quiet Friend'),
        'contacts');

-- Default on: the reminder is queued.
select is(
  private.enqueue_reminders(),
  1,
  'a user with reminders on is queued a reminder'
);

-- Turned off: nothing is queued.
delete from private.notification_outbox;
update public.profiles set reminders_enabled = false where handle = 'quiet';
select is(
  private.enqueue_reminders(),
  0,
  'a user who turned reminders off is queued nothing'
);

-- And the user can actually flip it themselves — a new column on profiles is
-- not client-writable until it is added to the column grant list, and updating
-- a non-granted column raises "permission denied for table profiles".
-- Assert the value LANDED, not merely that nothing was raised: a grant that is
-- present while an RLS predicate matches zero rows would update nothing, raise
-- nothing, and pass a bare lives_ok.
select tests.as_user((select id from public.profiles where handle = 'quiet'));
update public.profiles set reminders_enabled = true
where id = (select auth.uid());

select is(
  (select reminders_enabled from public.profiles where id = (select auth.uid())),
  true,
  'a user can turn their own reminders back on'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run it and watch it fail**

```bash
supabase test db supabase/tests/database/19_reminder_preference.test.sql
```

Expected: FAIL — `has_column` fails because `reminders_enabled` does not exist, and the later statements error on the missing column.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260827000001_reminder_preference.sql`:

```sql
-- The Settings screen's notification toggle. Defaults to on: a user who
-- installed a reminder app wants reminders, and an opt-out is the only shape
-- that does not silently drop the product's core function.
alter table public.profiles
  add column reminders_enabled boolean not null default true;

-- R14: profiles has NO table-level update grant for authenticated — it was
-- revoked and specific columns granted back one at a time. A new column is
-- therefore not client-writable until it is named here. The failure is LOUD,
-- not silent: updating a non-granted column raises
-- "permission denied for table profiles", and it aborts the whole statement
-- even when a granted column appears in the same SET list.
grant update (reminders_enabled) on public.profiles to authenticated;

-- The fan-out has to consult it. Without this the toggle is decorative.
create or replace function private.enqueue_reminders(p_today date default current_date)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted int := 0;
  v_offset smallint;
  v_target date;
  v_match_month smallint;
  v_match_day smallint;
begin
  foreach v_offset in array array[7, 1, 0]::smallint[]
  loop
    v_target := p_today + v_offset;
    v_match_month := extract(month from v_target)::smallint;
    v_match_day := extract(day from v_target)::smallint;

    with due as (
      insert into private.notification_outbox (
        recipient_profile_id, subject_person_id, offset_days, occasion_date
      )
      select c.celebrator_profile_id, p.id, v_offset, v_target
      from public.celebrations c
      join public.people p on p.id = c.person_id
      join public.profiles r on r.id = c.celebrator_profile_id
      where p.birth_month is not null
        and p.birth_month = v_match_month
        and (
          p.birth_day = v_match_day
          or (
            v_match_month = 2 and v_match_day = 28
            and p.birth_day = 29
            and not (
              extract(year from v_target)::int % 4 = 0
              and (extract(year from v_target)::int % 100 <> 0
                   or extract(year from v_target)::int % 400 = 0)
            )
          )
        )
        -- The Settings toggle.
        and r.reminders_enabled
        and not exists (
          select 1 from public.blocks b
          where b.blocker_profile_id = p.profile_id
            and b.blocked_profile_id = c.celebrator_profile_id
        )
      on conflict on constraint notification_outbox_once do nothing
      returning 1
    )
    select v_inserted + count(*)::int into v_inserted from due;
  end loop;

  return v_inserted;
end;
$$;

revoke execute on function private.enqueue_reminders(date)
  from public, anon, authenticated;
```

Note this is `create or replace` on an existing function, so its ACL is preserved — but the revoke is repeated anyway, because relying on ACL preservation is how a leak eventually happens.

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=20, Tests=172, PASS`. `17_reminders.test.sql` must still pass untouched — its fixtures create users whose `reminders_enabled` defaults to true.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260827000001_reminder_preference.sql \
        supabase/tests/database/19_reminder_preference.test.sql
git commit -m "feat(db): add a reminder preference the fan-out honours"
```

---

### Task 3: Let a signed-up user claim their person row

`private.claim_person` links a profile to a `people` row keyed on their phone hash. It is what makes a user findable by everyone who has their number, and it is what gives them a non-null `private.my_person_id()` — without which their Celebrates list, their wish wall and their stats are all empty. The app cannot call it.

**Files:**
- Create: `supabase/migrations/20260827000002_claim_person_rpc.sql`
- Create: `supabase/tests/database/20_claim_person_rpc.test.sql`

**Interfaces:**
- Consumes: `private.claim_person(uuid, text)`.
- Produces: `public.rpc_claim_person(p_profile_id uuid, p_phone text) returns bigint` — **service_role only**.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/20_claim_person_rpc.test.sql`:

```sql
begin;
select plan(4);

select tests.as_postgres();
select tests.create_user('claimer');

create temporary table ids as
select (select id from public.profiles where handle = 'claimer') as claimer;
grant select on ids to authenticated;

-- Before claiming, the user has no person row at all.
select is(
  (select count(*)::int from public.people
     where profile_id = (select claimer from ids)),
  0,
  'a fresh user has no person row'
);

-- Call it in its own statement. A volatile function inside a WHERE clause is
-- evaluated per candidate row and is exactly the fragility that broke an
-- assertion in Phase 1 -- assert the resulting state instead.
select public.rpc_claim_person((select claimer from ids), '+919220000001');

select is(
  (select profile_id from public.people
     where phone_e164_hash = private.phone_hash('+919220000001')),
  (select claimer from ids),
  'the wrapper links the profile to the person row for that number'
);

-- Claiming twice is the same row, not a second one. A user re-running
-- onboarding, or a retried request, must not fork their identity.
select is(
  public.rpc_claim_person((select claimer from ids), '+919220000001'),
  (select id from public.people
     where phone_e164_hash = private.phone_hash('+919220000001')),
  'claiming the same number twice returns the same person'
);

-- It is a machine door. A signed-in user must not be able to claim a number
-- they did not verify — the Edge Function reads the phone from the JWT.
select tests.as_user((select claimer from ids));
select throws_ok(
  $$ select public.rpc_claim_person(
       (select auth.uid()), '+919220000099') $$,
  '42501',
  null,
  'a signed-in user cannot call the claim wrapper directly'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run it and watch it fail**

```bash
supabase test db supabase/tests/database/20_claim_person_rpc.test.sql
```

Expected: FAIL with `function public.rpc_claim_person(uuid, text) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260827000002_claim_person_rpc.sql`:

```sql
-- Onboarding's last step. private.claim_person links a profile to the person
-- row for their phone hash, which is what makes the user findable by anyone
-- holding their number and what gives them a non-null private.my_person_id().
-- Without it their Celebrates list, wish wall and stats are all empty.
--
-- service_role ONLY. The phone must come from the caller's VERIFIED JWT, not
-- from a request body — otherwise a signed-in user could claim someone else's
-- number and inherit their inbound celebration edges. The Edge Function reads
-- it from the session; this wrapper trusts its caller because only the Edge
-- Function can reach it.
create or replace function public.rpc_claim_person(
  p_profile_id uuid,
  p_phone text
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select private.claim_person(p_profile_id, p_phone);
$$;

revoke execute on function public.rpc_claim_person(uuid, text)
  from public, anon, authenticated;
grant execute on function public.rpc_claim_person(uuid, text) to service_role;
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=21, Tests=176, PASS`. `11_rls_coverage.test.sql`'s public-function allowlist must be **unchanged** — this wrapper is service_role only, so `authenticated` still sees exactly `my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token`. If that guard fails, the grant is wrong.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260827000002_claim_person_rpc.sql \
        supabase/tests/database/20_claim_person_rpc.test.sql
git commit -m "feat(db): expose person claiming to the onboarding function"
```

---

### Task 4: Mint a person and a celebration edge when the user picks a contact

Contacts import resolves matches read-only (Phase 1), then the user picks who they celebrate. Picking is what mints the `people` row — the "create on select" decision that stops an import minting thousands of rows for non-consenting contacts. The app cannot call `private.upsert_person`, and the edge and the person must be created together or a failure leaves one without the other.

**Files:**
- Create: `supabase/migrations/20260827000003_add_celebration.sql`
- Create: `supabase/tests/database/21_add_celebration.test.sql`

**Interfaces:**
- Consumes: `private.upsert_person(text, text, smallint, smallint, smallint)`, `public.celebrations`, `private.my_person_id()`.
- Produces:
  - `private.add_celebration(p_celebrator uuid, p_phone text, p_name text, p_birth_month smallint, p_birth_day smallint, p_birth_year smallint) returns bigint` — the person id, or null when suppressed
  - `public.rpc_add_celebration(...)` with the same signature — **service_role only**

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/21_add_celebration.test.sql`:

```sql
begin;
select plan(6);

select tests.as_postgres();
select tests.create_user('picker');
select private.claim_person(
  (select id from public.profiles where handle = 'picker'), '+919230000001');

create temporary table ids as
select (select id from public.profiles where handle = 'picker') as picker;

-- Picking a contact mints the person AND the edge together.
select isnt(
  private.add_celebration((select picker from ids), '+919230000002',
    'Picked Friend', 4::smallint, 1::smallint, null::smallint),
  null,
  'picking a contact returns a person id'
);

select is(
  (select count(*)::int from public.celebrations c
     join public.people p on p.id = c.person_id
    where c.celebrator_profile_id = (select picker from ids)
      and p.display_name = 'Picked Friend'),
  1,
  'the celebration edge is created alongside the person'
);

-- Picking the same contact twice is idempotent — a retried request or a
-- double tap must not error and must not fork the graph.
select lives_ok(
  $$ select private.add_celebration((select picker from ids), '+919230000002',
       'Picked Friend', 4::smallint, 1::smallint, null::smallint) $$,
  'picking the same contact twice does not error'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select picker from ids)),
  1,
  'and does not create a second edge'
);

-- A suppressed number returns null and creates nothing. Someone who asked to
-- be removed must not be re-added by the next person who imports their phone.
select private.suppress_person(
  tests.create_person('+919230000003', 'Opted Out'));
select is(
  private.add_celebration((select picker from ids), '+919230000003',
    'Opted Out', null::smallint, null::smallint, null::smallint),
  null,
  'a suppressed number returns null instead of a person'
);

-- Celebrating yourself is meaningless. M0's guard trigger raises P0001.
select throws_ok(
  $$ select private.add_celebration((select picker from ids), '+919230000001',
       'Me', null::smallint, null::smallint, null::smallint) $$,
  'P0001',
  'you cannot celebrate yourself',
  'picking your own number is rejected'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run it and watch it fail**

```bash
supabase test db supabase/tests/database/21_add_celebration.test.sql
```

Expected: FAIL with `function private.add_celebration(...) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260827000003_add_celebration.sql`:

```sql
-- "Create on select": the import screen resolves matches read-only, and the
-- person row is minted only when the user actually picks someone. The person
-- and the edge are created in one call so a failure cannot leave a person
-- nobody celebrates, or an edge pointing at nothing.
--
-- Returns null when the number is suppressed. Callers must treat that as
-- "skip this contact", not as an error — someone who asked to be removed must
-- not be resurrected by the next person who imports their number.
create or replace function private.add_celebration(
  p_celebrator uuid,
  p_phone text,
  p_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person_id bigint;
begin
  v_person_id := private.upsert_person(
    p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);

  if v_person_id is null then
    return null;  -- suppressed
  end if;

  -- on conflict: a retried request or a double tap is idempotent. The
  -- celebrations_guard trigger still fires first and rejects self-celebration
  -- with P0001, which propagates to the caller.
  insert into public.celebrations (celebrator_profile_id, person_id, source)
  values (p_celebrator, v_person_id, 'contacts')
  on conflict on constraint celebrations_unique_edge do nothing;

  return v_person_id;
end;
$$;

revoke execute on function private.add_celebration(
  uuid, text, text, smallint, smallint, smallint)
  from public, anon, authenticated;

-- service_role only, reached through the add_celebrations Edge Function.
create or replace function public.rpc_add_celebration(
  p_celebrator uuid,
  p_phone text,
  p_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select private.add_celebration(
    p_celebrator, p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);
$$;

revoke execute on function public.rpc_add_celebration(
  uuid, text, text, smallint, smallint, smallint)
  from public, anon, authenticated;
grant execute on function public.rpc_add_celebration(
  uuid, text, text, smallint, smallint, smallint) to service_role;
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=22, Tests=182, PASS`. Both standing guards must pass untouched: `01_private.test.sql`'s private allowlist stays `can_see_person,is_staff,my_person_id` (the new private function is revoked from everyone), and `11_rls_coverage.test.sql`'s public allowlist is unchanged (the wrapper is service_role only).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260827000003_add_celebration.sql \
        supabase/tests/database/21_add_celebration.test.sql
git commit -m "feat(db): mint a person and a celebration edge in one call"
```

---

### Task 5: The `claim_profile` Edge Function

The app calls this once, at the end of onboarding. Its whole job is to take the phone the user actually verified — from their session, never from a request body — and claim their person row with it.

**Files:**
- Create: `supabase/functions/claim_profile/index.ts`
- Create: `supabase/functions/claim_profile/deno.json`

**Interfaces:**
- Consumes: `public.rpc_claim_person(uuid, text)`.
- Produces: `POST /functions/v1/claim_profile` with no body, returning `{"person_id": <bigint>}`.

- [ ] **Step 1: Write the function**

Create `supabase/functions/claim_profile/index.ts`:

```ts
// Onboarding's last step. Takes the phone the caller VERIFIED during OTP —
// read from their session, never from the request body — and claims the person
// row for it. Accepting a phone from the body would let a signed-in user claim
// someone else's number and inherit every celebration edge pointing at it.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return new Response(JSON.stringify({ error: "missing authorization" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "function is misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const phone = userData.user.phone;
  if (!phone) {
    // Email-only sessions cannot be claimed: the whole graph is keyed on a
    // verified phone number.
    return new Response(JSON.stringify({ error: "session has no verified phone" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // GoTrue stores the phone without a leading '+'; phone_hash is computed over
  // the E.164 form the app sends everywhere else, so normalise here.
  const e164 = phone.startsWith("+") ? phone : `+${phone}`;

  const admin = createClient(url, serviceKey);
  const { data, error } = await admin.rpc("rpc_claim_person", {
    p_profile_id: userData.user.id,
    p_phone: e164,
  });

  if (error) {
    console.error("rpc_claim_person failed", error.message);
    return new Response(JSON.stringify({ error: "claim failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ person_id: data }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
```

Create `supabase/functions/claim_profile/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

- [ ] **Step 2: Serve it and exercise the refusal paths**

```bash
supabase functions serve claim_profile --no-verify-jwt &
sleep 5
curl -s -X GET  http://127.0.0.1:54321/functions/v1/claim_profile
curl -s -X POST http://127.0.0.1:54321/functions/v1/claim_profile
```

Expected: `{"error":"method not allowed"}` then `{"error":"missing authorization"}`.

- [ ] **Step 3: Exercise the happy path with a real OTP session**

Use Task 1's test number to get a real token, then call the function with it:

```bash
PUB=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' -H "apikey: $PUB" \
  -H 'content-type: application/json' -d '{"phone":"+919999000002"}' >/dev/null
TOKEN=$(curl -s -X POST 'http://127.0.0.1:54321/auth/v1/verify' -H "apikey: $PUB" \
  -H 'content-type: application/json' \
  -d '{"phone":"+919999000002","token":"123456","type":"sms"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s -X POST http://127.0.0.1:54321/functions/v1/claim_profile \
  -H "Authorization: Bearer $TOKEN"
```

Expected: `{"person_id": <a number>}`.

Then prove it actually linked the row, and that the phone came from the session:

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select p.id, p.profile_id is not null as linked,
          p.phone_e164_hash = private.phone_hash('+919999000002') as right_number
   from public.people p order by p.id desc limit 1;"
```

Expected: `linked = t` and `right_number = t`.

- [ ] **Step 4: Stop the server, confirm the suite, and commit**

```bash
kill %1
supabase db reset && supabase test db
```

Expected: `Files=22, Tests=182, PASS` — this task adds no pgTAP.

```bash
git add supabase/functions/claim_profile/
git commit -m "feat(functions): claim a person row from the verified session phone"
```

---

### Task 6: The `add_celebrations` Edge Function

The import screen sends the contacts the user picked. This mints each person and edge, reports per-contact outcomes, and never fails the whole batch because one contact was suppressed.

**Files:**
- Create: `supabase/functions/add_celebrations/index.ts`
- Create: `supabase/functions/add_celebrations/deno.json`

**Interfaces:**
- Consumes: `public.rpc_add_celebration(uuid, text, text, smallint, smallint, smallint)`.
- Produces: `POST /functions/v1/add_celebrations` with body
  `{"contacts": [{"phone": string, "name": string, "birth_month"?: number, "birth_day"?: number, "birth_year"?: number}]}`
  returning `{"added": n, "skipped": n, "results": [{phone, person_id|null, status}]}`.

- [ ] **Step 1: Write the function**

Create `supabase/functions/add_celebrations/index.ts`:

```ts
// The import screen's commit step. Each picked contact mints a person and a
// celebration edge together.
//
// A suppressed number returns null from the RPC and is reported as "skipped",
// not as an error — someone who asked to be removed must not be resurrected,
// and one such contact must not fail an import of five hundred.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BATCH = 500;

type Contact = {
  phone: string;
  name: string;
  birth_month?: number | null;
  birth_day?: number | null;
  birth_year?: number | null;
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return new Response(JSON.stringify({ error: "missing authorization" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  let contacts: unknown;
  try {
    ({ contacts } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (
    !Array.isArray(contacts) ||
    contacts.some((c) =>
      !c || typeof c.phone !== "string" || typeof c.name !== "string"
    )
  ) {
    return new Response(
      JSON.stringify({ error: "contacts must be {phone, name}[]" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  if (contacts.length > MAX_BATCH) {
    return new Response(
      JSON.stringify({ error: `at most ${MAX_BATCH} contacts per request` }),
      { status: 413, headers: { "content-type": "application/json" } },
    );
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "function is misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const admin = createClient(url, serviceKey);
  const results: Array<
    { phone: string; person_id: number | null; status: string }
  > = [];
  let added = 0;
  let skipped = 0;

  for (const c of contacts as Contact[]) {
    const { data, error } = await admin.rpc("rpc_add_celebration", {
      p_celebrator: userData.user.id,
      p_phone: c.phone,
      p_name: c.name,
      p_birth_month: c.birth_month ?? null,
      p_birth_day: c.birth_day ?? null,
      p_birth_year: c.birth_year ?? null,
    });

    if (error) {
      // Never log the contact — it carries a phone number and a name.
      console.error("rpc_add_celebration failed", error.message);
      results.push({ phone: c.phone, person_id: null, status: "failed" });
      skipped++;
      continue;
    }

    if (data === null) {
      results.push({ phone: c.phone, person_id: null, status: "suppressed" });
      skipped++;
      continue;
    }

    results.push({ phone: c.phone, person_id: data, status: "added" });
    added++;
  }

  return new Response(JSON.stringify({ added, skipped, results }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
```

Create `supabase/functions/add_celebrations/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

- [ ] **Step 2: Serve it and exercise the refusal paths**

```bash
supabase functions serve add_celebrations --no-verify-jwt &
sleep 5
curl -s -X GET  http://127.0.0.1:54321/functions/v1/add_celebrations
curl -s -X POST http://127.0.0.1:54321/functions/v1/add_celebrations \
  -H 'Authorization: Bearer x' -H 'content-type: application/json' \
  -d '{"contacts":"nope"}'
```

Expected: `{"error":"method not allowed"}` then `{"error":"contacts must be {phone, name}[]"}`.

- [ ] **Step 3: Exercise the happy path, including a suppressed contact**

Get a session for test number 3, suppress one number first, then send a batch of two:

```bash
PUB=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' -H "apikey: $PUB" \
  -H 'content-type: application/json' -d '{"phone":"+919999000003"}' >/dev/null
TOKEN=$(curl -s -X POST 'http://127.0.0.1:54321/auth/v1/verify' -H "apikey: $PUB" \
  -H 'content-type: application/json' \
  -d '{"phone":"+919999000003","token":"123456","type":"sms"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

docker exec supabase_db_birthday_app psql -U postgres -d postgres -c \
  "select private.suppress_person(private.upsert_person('+919240000002','Gone'));"

curl -s -X POST http://127.0.0.1:54321/functions/v1/add_celebrations \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"contacts":[{"phone":"+919240000001","name":"Real Friend","birth_month":5,"birth_day":9},{"phone":"+919240000002","name":"Gone"}]}'
```

Expected: `added: 1`, `skipped: 1`, with the second result carrying `status: "suppressed"` and `person_id: null`.

Then confirm exactly one edge exists for that caller:

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select count(*) from public.celebrations c
    join public.profiles pr on pr.id = c.celebrator_profile_id
   where pr.handle like 'u%';"
```

- [ ] **Step 4: Stop the server, confirm the suite, and commit**

```bash
kill %1
supabase db reset && supabase test db
```

Expected: `Files=22, Tests=182, PASS`.

```bash
git add supabase/functions/add_celebrations/
git commit -m "feat(functions): add celebrations for picked contacts"
```

---

### Task 7: The `delete_account` Edge Function

The Settings screen offers "delete account". A Supabase client cannot delete its own auth user — that is an admin-API operation — so without this the button has nothing behind it.

**Files:**
- Create: `supabase/functions/delete_account/index.ts`
- Create: `supabase/functions/delete_account/deno.json`

**Interfaces:**
- Consumes: the Supabase auth admin API (`auth.admin.deleteUser`).
- Produces: `POST /functions/v1/delete_account` with no body, returning `{"deleted": true}`.

**What deletion actually does — verified against the live foreign keys:**

Deleting the auth user cascades to `profiles`, and from there:

| Cascades away | Survives |
|---|---|
| their outgoing `celebrations` | their `people` row, with `profile_id` **SET NULL** |
| `wishes` they authored | everyone else's edges pointing at that person |
| their `device_tokens`, `blocks`, queued `notification_outbox` rows | |

The person row surviving unclaimed is correct: it was built from other people's address books, and deleting it would break every celebration edge pointing at it. Deleting an account is not the same as asking not to be imported — that is `private.suppress_person`, a separate mechanism.

**One hazard this task must record but not fix:** `gifts.sender_profile_id` is `ON DELETE RESTRICT`. There are no gifts in M1, so deletion succeeds today. The moment M3 ships and a user has sent one, deleting their account will fail with a foreign-key violation. M3 must decide whether a sender's gifts are reassigned, anonymised, or deletion refused — this plan only names the problem.

- [ ] **Step 1: Write the function**

Create `supabase/functions/delete_account/index.ts`:

```ts
// Settings -> delete account. A client cannot delete its own auth user; only
// the admin API can, so this exists purely to do that on the caller's behalf.
//
// The caller is identified from their session and NEVER from a request body —
// accepting an id here would let any signed-in user delete anyone.
//
// Cascade, verified against the live foreign keys: profiles goes, and with it
// their outgoing celebrations, the wishes they authored, their device tokens,
// blocks and queued reminders. Their people row SURVIVES with profile_id set
// to null, because it was built from other people's address books and deleting
// it would break every celebration edge pointing at it. Not being imported at
// all is a different request -- that is private.suppress_person.
//
// KNOWN LIMIT: gifts.sender_profile_id is ON DELETE RESTRICT. No gifts exist in
// M1 so this succeeds today, but once M3 ships, a user who has sent a gift
// cannot be deleted until M3 decides what happens to their gifts.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return new Response(JSON.stringify({ error: "missing authorization" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "function is misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const admin = createClient(url, serviceKey);
  const { error } = await admin.auth.admin.deleteUser(userData.user.id);

  if (error) {
    // Do not echo the driver text: once M3 exists this is where a
    // gifts-RESTRICT violation will surface, and it names internal tables.
    console.error("deleteUser failed", error.message);
    return new Response(JSON.stringify({ error: "delete failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
```

Create `supabase/functions/delete_account/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

- [ ] **Step 2: Serve it and exercise the refusal paths**

```bash
supabase functions serve delete_account --no-verify-jwt &
sleep 5
curl -s -X GET  http://127.0.0.1:54321/functions/v1/delete_account
curl -s -X POST http://127.0.0.1:54321/functions/v1/delete_account
```

Expected: `{"error":"method not allowed"}` then `{"error":"missing authorization"}`.

- [ ] **Step 3: Prove the cascade behaves as documented**

Create a user via OTP, give them a celebration edge and a device token, then delete and inspect what survived:

```bash
PUB=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' -H "apikey: $PUB" \
  -H 'content-type: application/json' -d '{"phone":"+919999000001"}' >/dev/null
TOKEN=$(curl -s -X POST 'http://127.0.0.1:54321/auth/v1/verify' -H "apikey: $PUB" \
  -H 'content-type: application/json' \
  -d '{"phone":"+919999000001","token":"123456","type":"sms"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# claim a person and celebrate someone, so there is something to cascade
curl -s -X POST http://127.0.0.1:54321/functions/v1/claim_profile \
  -H "Authorization: Bearer $TOKEN" >/dev/null
curl -s -X POST http://127.0.0.1:54321/functions/v1/add_celebrations \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"contacts":[{"phone":"+919250000001","name":"Cascade Friend"}]}' >/dev/null

docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select 'before: profiles=' || (select count(*) from public.profiles) ||
          ' edges=' || (select count(*) from public.celebrations) ||
          ' people=' || (select count(*) from public.people);"

curl -s -X POST http://127.0.0.1:54321/functions/v1/delete_account \
  -H "Authorization: Bearer $TOKEN"

docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select 'after:  profiles=' || (select count(*) from public.profiles) ||
          ' edges=' || (select count(*) from public.celebrations) ||
          ' people=' || (select count(*) from public.people) ||
          ' unclaimed=' || (select count(*) from public.people where profile_id is null);"
```

Expected: `{"deleted":true}`; profiles and edges drop; **people does NOT drop**, and the deleted user's own person row is now unclaimed. Paste both lines — that contrast is the point of the task.

- [ ] **Step 4: Stop the server, confirm the suite, and commit**

```bash
kill %1
supabase db reset && supabase test db
```

Expected: `Files=22, Tests=182, PASS` — this task adds no pgTAP.

```bash
git add supabase/functions/delete_account/
git commit -m "feat(functions): let a user delete their own account"
```

---

## Phase 2a Definition of Done

- `supabase db reset && supabase test db` → **`Files=22, Tests=182, PASS`** from a cold database
- `supabase db lint --level warning` reports warnings only inside `extensions.*`
- Both standing allowlists unchanged: private stays `can_see_person,is_staff,my_person_id`; public stays `my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token` — every wrapper added here is service_role only
- Phone OTP works end to end locally against the test-code map, and the report records which key format worked
- `claim_profile` claims from the **session's** phone, never a request body
- `add_celebrations` reports a suppressed contact as skipped rather than failing the batch
- `delete_account` removes the profile and its edges while the person row survives unclaimed, and the report records the before/after counts

## What Phase 2a deliberately does not do

- No Flutter code — that is Phase 2b
- No real SMS provider; the test-OTP map is local only and `config.toml` is not applied to a hosted project
- The drain stays unscheduled; that waits on FCM credentials (M1 spec open question 1)
- No `send_invite` for non-users — that is M3's growth loop
