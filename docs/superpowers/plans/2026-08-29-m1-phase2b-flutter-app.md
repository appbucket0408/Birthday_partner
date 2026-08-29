# M1 Phase 2b — App: Identity and Graph — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first runnable Flutter app for this project — phone OTP onboarding, contacts import, and a Celebrating timeline grouped by how soon each birthday falls — running against local Supabase.

**Architecture:** `view → cubit → repository → Supabase client`. Each feature owns a Cubit and a repository interface with one implementation; `api/` holds only cross-cutting plumbing. Two backend prerequisites land first, because the client depends on contracts that do not exist yet.

**Tech Stack:** Flutter 3.35.2 (FVM), Dart 3.9, `flutter_bloc`, `go_router`, `supabase_flutter`, `flutter_contacts`, `phone_numbers_parser`, `fluttertoast`, `bloc_test`; Postgres 17 + pgTAP; Deno for Edge Function tests.

**Spec:** `docs/superpowers/specs/2026-08-29-m1-phase2b-flutter-app-design.md`

## Global Constraints

- **Flutter 3.35.2**, pinned in `.fvmrc`. Every Flutter command in this plan is run through `fvm` (`fvm flutter …`, `fvm dart …`).
- **All user-facing copy lives in `lib/core/app_strings.dart`.** No string literals in screens. This is a review-rejection criterion, not a preference.
- **No one-off sub-widget classes.** Screens own their layout inline. Extract only what is reused in 2+ places or is genuinely oversized.
- **`supabase/config.toml` must keep `[auth.sms] enable_confirmations = true`.** It is the fix for total account takeover (reproduced 27 Aug 2026) and nothing tests it. Any task touching `config.toml` re-verifies this line before committing.
- **Local test phone numbers** are `+919999000001`, `+919999000002`, `+919999000003`, all with OTP `123456`, from `[auth.sms.test_otp]`. Default onboarding country is **IN**.
- **Local Supabase** is `http://127.0.0.1:54321`. Get the anon and service-role keys from `supabase status`. Colima must be running and Supabase analytics must stay disabled.
- **A green suite is not evidence.** Every new assertion must be watched to FAIL with the implementation reverted before the task is considered done. Two assertions in Phase 2a passed with and without the fix; the implementer caught it and said so, and that is the standard here.
- **New `private` functions extend the allowlist** in `supabase/tests/database/01_private.test.sql`. That guard caught five leaked functions during M0.
- **New `public` functions executable by `authenticated` extend the R3 allowlist** in `supabase/tests/database/11_rls_coverage.test.sql`. Missing this makes the suite fail from cold. (Added 29 Aug 2026 after Task 1 hit it.)
- **SQLSTATE is a public API decision.** PostgREST maps it to an HTTP status. Use unassigned class-45 codes for application errors; `P0002` becomes a 500.
- Read `docs/db.md` before touching anything in `supabase/`. It carries eleven rules that each shipped a bug first.
- **Every contract test must use the shared harness** at `test/support/contract_test_harness.dart`. Three things are required before a `flutter test` process can reach a real Supabase instance at all, and none of them are obvious (discovered in Task 5):
  1. `HttpOverrides.global = null` — `AutomatedTestWidgetsFlutterBinding` installs an `HttpOverrides` that fakes every `dart:io` request with a 400 stub. Without this line a "contract test" silently talks to nothing, which is the worst possible failure for a suite whose entire purpose is hitting the real stack.
  2. An in-memory `SharedPreferencesStorePlatform` — there is no platform channel under `flutter test`, so `supabase_flutter`'s session storage throws `MissingPluginException`.
  3. An OTP send-cooldown helper — `[auth.sms] max_frequency = "5s"` rate-limits back-to-back sends to the same test number, which otherwise reads as a flaky suite.

  Tasks 9, 11 and 13 import this harness. They must not re-inline any of it.

---

## File Structure

**Backend (Tasks 1–2)**

| File | Responsibility |
|---|---|
| `supabase/migrations/20260829000001_update_person_birthday.sql` | The inline birthday-edit RPC and its grants |
| `supabase/tests/database/26_update_person_birthday.test.sql` | pgTAP proof of both of its access conditions |
| `supabase/functions/add_celebrations/index.test.ts` | Deno integration test for the import contract |

**Flutter (Tasks 3–13)**

| File | Responsibility |
|---|---|
| `lib/main.dart` | Supabase init, `runApp` |
| `lib/app.dart` | `MaterialApp.router`, theme, top-level `RepositoryProvider`s |
| `lib/core/app_colors.dart` | Seed colour and the derived scheme |
| `lib/core/app_text_styles.dart` | Type scale |
| `lib/core/app_spacing.dart` | Spacing constants |
| `lib/core/app_strings.dart` | Every user-facing string |
| `lib/core/logger.dart` | One logger, no `print` |
| `lib/core/result.dart` | `AppFailure` and its subtypes |
| `lib/api/api_client.dart` | The Supabase singleton |
| `lib/api/api_endpoints.dart` | Edge Function names |
| `lib/api/api_params.dart` | RPC argument and column-key constants |
| `lib/api/api_connectivity.dart` | Pre-flight connectivity check |
| `lib/api/api_error_mapper.dart` | `PostgrestException`/`FunctionException` → `AppFailure` |
| `lib/models/birthday.dart` | Month/day/year value type and the occurrence rules |
| `lib/models/profile.dart`, `person.dart`, `celebration.dart` | Row mappings |
| `lib/models/import_outcome.dart` | The `add_celebrations` status vocabulary |
| `lib/router/app_router.dart` | `go_router` + the three-state onboarding guard |
| `lib/repositories/auth_repository.dart` (+ `_impl`) | OTP, session, claim, sign out, delete |
| `lib/repositories/contacts_repository.dart` (+ `_impl`) | Device contacts, E.164, resolve, add |
| `lib/repositories/graph_repository.dart` (+ `_impl`) | Timeline reads, birthday/nickname edit, un-celebrate |
| `lib/repositories/settings_repository.dart` (+ `_impl`) | `reminders_enabled` |
| `lib/features/onboarding/` | `phone_cubit`, `profile_setup_cubit`, their states and screens |
| `lib/features/contacts_import/` | `import_cubit`, state, disclosure/pick/fill/summary screens |
| `lib/features/timeline/` | `timeline_cubit`, state, screen |
| `lib/features/settings/` | `settings_cubit`, state, screen |

Test files mirror `lib/` under `test/`, with repository contract tests under `test/repositories/` (these require local Supabase running) and Cubit tests under `test/features/`.

---

## Task 1: The inline birthday-edit RPC

Spec §4.1. Parent carry-forward #4: spec §7.3 requires editing a contact's birthday from a timeline row, and no surface exists. `public.people` has no UPDATE policy and `private.upsert_person` only fills NULLs.

Written test-first, per M0's discipline: the migration is implemented, then the tests find the defects.

**Files:**
- Create: `supabase/migrations/20260829000001_update_person_birthday.sql`
- Create: `supabase/tests/database/26_update_person_birthday.test.sql`

**Interfaces:**
- Consumes: `tests.create_user(text) returns uuid`, `tests.create_person(text, text, smallint, smallint, smallint) returns bigint`, `tests.as_user(uuid)`, `tests.as_anon()`, `tests.as_postgres()` from `supabase/seed.sql`; `private.phone_hash(text)`.
- Produces: `public.rpc_update_person_birthday(p_person_id bigint, p_birth_month smallint, p_birth_day smallint, p_birth_year smallint) returns void`. Raises `45002` when the caller holds no edge, `45003` when the person has claimed a profile. Task 11's `GraphRepository.updateBirthday` calls it.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/26_update_person_birthday.test.sql`:

```sql
begin;
select plan(7);

select tests.as_postgres();
select tests.create_user('editor');
select tests.create_user('stranger');
select tests.create_user('claimant');

create temporary table ids as
select
  (select id from public.profiles where handle = 'editor')    as editor,
  (select id from public.profiles where handle = 'stranger')  as stranger,
  (select id from public.profiles where handle = 'claimant')  as claimant,
  tests.create_person('+919999111101', 'Unclaimed Friend')    as unclaimed,
  tests.create_person('+919999111102', 'Claimed Friend')      as claimed;
grant select on ids to authenticated;

-- The editor celebrates both people. Edges are minted by the RPC in real use;
-- here we are setting up the precondition, not testing the mint.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select editor, unclaimed, 'contacts' from ids;
insert into public.celebrations (celebrator_profile_id, person_id, source)
select editor, claimed, 'contacts' from ids;

-- The second person has claimed their own profile, so their own birthday wins.
update public.people set profile_id = (select claimant from ids)
where id = (select claimed from ids);

-- 1. The happy path: a celebrator fills in a birthday their address book lacked.
select tests.as_user((select editor from ids));
select lives_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 4::smallint, 15::smallint, null::smallint) $$,
  'a celebrator can set the birthday of an unclaimed person they celebrate'
);

select is(
  (select birth_month || '/' || birth_day from public.people
     where id = (select unclaimed from ids)),
  '4/15',
  'the birthday is actually written'
);

-- 2. A year-less birthday is the common case from a device address book, and
--    overwriting it with a year must work too.
select lives_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 4::smallint, 15::smallint, 1991::smallint) $$,
  'the year can be added later'
);

-- 3. The edge is the authorisation. people.id is a sequential bigint, so
--    without this check it is an open write target for any authenticated user.
select tests.as_user((select stranger from ids));
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 1::smallint, 1::smallint, null::smallint) $$,
  '45002',
  null,
  'a non-celebrator cannot edit the birthday'
);

-- 4. A claimed user owns their own date of birth. Without this, any celebrator
--    could rewrite a real user's DOB.
select tests.as_user((select editor from ids));
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       (select claimed from ids), 1::smallint, 1::smallint, null::smallint) $$,
  '45003',
  null,
  'a claimed person''s birthday cannot be edited by a celebrator'
);

-- 5. The table's own check constraints still apply through the RPC. April has
--    30 days; security definer must not become a way around data integrity.
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       (select unclaimed from ids), 4::smallint, 31::smallint, null::smallint) $$,
  '23514',
  null,
  'an impossible date is still rejected by the check constraint'
);

-- 6. It is an authenticated door.
select tests.as_anon();
select throws_ok(
  $$ select public.rpc_update_person_birthday(
       1::bigint, 1::smallint, 1::smallint, null::smallint) $$,
  '42501',
  null,
  'anon cannot execute the function'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ~/Desktop/Projects/birthday_app
supabase test db
```

Expected: `26_update_person_birthday.test.sql` fails with `function public.rpc_update_person_birthday(bigint, smallint, smallint, smallint) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260829000001_update_person_birthday.sql`:

```sql
-- Spec 2026-08-29 §4.1. Phase 2a left the timeline's inline birthday edit with
-- no surface at all: public.people has no UPDATE policy, and
-- private.upsert_person only fills NULLs and only when profile_id is null.
--
-- This is security definer, so it bypasses RLS and must do its own
-- authorisation. Two conditions, both load-bearing:
--
--   1. The caller holds a celebration edge to the person. people.id is a
--      sequential bigint; without this check it is an open write target.
--   2. The person has not claimed a profile. Otherwise any celebrator could
--      rewrite a real user's date of birth. A claimed user's own birthday wins.
--
-- SQLSTATEs are chosen, not incidental: docs/db.md records that PostgREST maps
-- them straight to HTTP status codes, so class 45 (unassigned) keeps these
-- reaching the client as 400-class application errors rather than 500s.
create or replace function public.rpc_update_person_birthday(
  p_person_id   bigint,
  p_birth_month smallint,
  p_birth_day   smallint,
  p_birth_year  smallint default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.celebrations c
    where c.person_id = p_person_id
      and c.celebrator_profile_id = auth.uid()
  ) then
    raise exception 'not celebrating this person'
      using errcode = '45002';
  end if;

  if exists (
    select 1
    from public.people p
    where p.id = p_person_id
      and p.profile_id is not null
  ) then
    raise exception 'person has claimed their profile'
      using errcode = '45003';
  end if;

  update public.people
     set birth_month = p_birth_month,
         birth_day   = p_birth_day,
         birth_year  = p_birth_year
   where id = p_person_id;
end;
$$;

-- R12/R16 (docs/db.md): `revoke ... from public` also strips `authenticated`,
-- which holds EXECUTE only through the PUBLIC grant. The grant back is not
-- redundant -- without it the function is unreachable by the app.
revoke execute on function public.rpc_update_person_birthday(
  bigint, smallint, smallint, smallint) from public, anon;
grant execute on function public.rpc_update_person_birthday(
  bigint, smallint, smallint, smallint) to authenticated;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
supabase db reset && supabase test db
```

Expected: `26_update_person_birthday.test.sql .. ok`, and the whole suite green from cold — **27 files**, up from 26.

- [ ] **Step 5: Prove each assertion can fail**

This is the step Phase 2a's implementer caught themselves skipping. For each of assertions 4, 5 and 7 (the `45002`, `45003` and `42501` guards), comment out the corresponding block in the migration, run `supabase db reset && supabase test db`, and confirm **that specific assertion fails**. Restore the block afterwards.

Expected: three separate observed failures. If any assertion passes with its guard removed, the assertion is testing nothing and must be rewritten before continuing.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260829000001_update_person_birthday.sql \
        supabase/tests/database/26_update_person_birthday.test.sql
git commit -m "feat(db): the inline birthday-edit RPC the timeline needs

Carry-forward #4 from Phase 2a. Authorises on the celebration edge and
refuses claimed people, so a celebrator cannot rewrite a real user's
date of birth."
```

---

## Task 2: A Deno test for `add_celebrations`

Spec §4.2. Parent carry-forward #1: every Edge Function has zero automated coverage, and this one's status vocabulary is what Task 10 bakes into the import screen. This task closes that one contract before any Dart depends on it.

The test is an integration test against the locally served function — the same thing the app will call — because the contract being pinned is HTTP-level, not module-level.

**Files:**
- Create: `supabase/functions/add_celebrations/index.test.ts`

**Interfaces:**
- Consumes: the running local stack (`supabase start`, `supabase functions serve`) and the keys from `supabase status`.
- Produces: nothing importable. Pins the response shape `{added, skipped, failed, duplicates, results: [{phone, person_id, status}]}` that Task 9's `ContactsRepository.addCelebrations` parses and Task 10's summary renders.

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/add_celebrations/index.test.ts`:

```typescript
// Integration test. Requires the local stack:
//   supabase start
//   supabase functions serve --no-verify-jwt
//
// --no-verify-jwt is REQUIRED for the 401 test. config.toml has no
// [functions] block, so every function runs at verify_jwt = true and the
// gateway rejects an unauthenticated request BEFORE the handler sees it --
// the function's own `if (!auth)` branch is then unreachable and the test
// fails against the wrong response body. Serving without gateway verification
// is what lets this suite test the handler's own guard. The gateway's 401 in
// the default config is a separate, additive layer; parent carry-forward #3
// is the open decision about whether it stays on.
//
// Run with:
//   deno test --allow-net --allow-env supabase/functions/add_celebrations/index.test.ts
//
// It talks HTTP to the served function rather than importing the handler,
// because the contract Phase 2b's import screen depends on is the HTTP one:
// the status vocabulary, the count invariant, and the positional results array.
import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FN = `${URL}/functions/v1/add_celebrations`;

const TEST_PHONES = ["+919999000001", "+919999000002", "+919999000003"];
let cursor = 0;

// deno-lint-ignore no-explicit-any
async function deleteUserByPhone(admin: any, phone: string): Promise<void> {
  const { data } = await admin.auth.admin.listUsers();
  const existing = data?.users?.find((u: { phone?: string }) =>
    u.phone === phone.replace("+", "")
  );
  if (existing) await admin.auth.admin.deleteUser(existing.id);
}

// A fresh signed-in user per test, so repeated runs never collide on the
// unique celebration edge and read as "duplicate" when they mean "added".
async function signedInUser(): Promise<{ jwt: string; phone: string }> {
  // Only the three numbers in [auth.sms.test_otp] receive code 123456, so the
  // pool is fixed rather than random. Each test deletes its user in a finally
  // block so the next test can reuse the number.
  const admin = createClient(URL, SERVICE);
  const phone = TEST_PHONES[cursor++ % TEST_PHONES.length];
  await deleteUserByPhone(admin, phone);
  const { error } = await admin.auth.admin.createUser({
    phone,
    phone_confirm: true,
  });
  if (error) throw error;

  // The created user is signed in through the test OTP map, which is the same
  // path the app takes. generateLink is email-only and does not apply here.
  const anon = createClient(URL, ANON);
  const { error: otpErr } = await anon.auth.signInWithOtp({ phone });
  if (otpErr) throw otpErr;
  const { data: verified, error: vErr } = await anon.auth.verifyOtp({
    phone,
    token: "123456",
    type: "sms",
  });
  if (vErr) throw vErr;
  const jwt = verified.session!.access_token;

  // Claiming is REQUIRED for the `self` status to be reachable.
  // private.add_celebration's self-guard fires only when the person row is
  // already claimed by the celebrator, or carries their phone hash. A user who
  // has signed in but not claimed gets `added` for their own number, and
  // claim_person deletes the self-edge retroactively instead.
  const claim = await fetch(`${URL}/functions/v1/claim_profile`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${jwt}` },
  });
  if (!claim.ok) throw new Error(`claim_profile failed: ${claim.status}`);

  return { jwt, phone };
}

function post(body: unknown, jwt?: string) {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (jwt) headers["Authorization"] = `Bearer ${jwt}`;
  return fetch(FN, { method: "POST", headers, body: JSON.stringify(body) });
}

Deno.test("rejects a request with no Authorization header", async () => {
  const res = await post({ contacts: [] });
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "missing authorization");
});

Deno.test("rejects more than MAX_BATCH contacts with 413", async () => {
  const { jwt } = await signedInUser();
  const contacts = Array.from({ length: 501 }, (_, i) => ({
    phone: `+91999${String(i).padStart(7, "0")}`,
    name: "Too Many",
  }));
  const res = await post({ contacts }, jwt);
  assertEquals(res.status, 413);
  assertEquals((await res.json()).error, "at most 500 contacts per request");
});

Deno.test("the count invariant holds across every status", async () => {
  const { jwt, phone } = await signedInUser();
  const contacts = [
    { phone: "+919999222201", name: "Added One" },
    { phone: "+919999222201", name: "Added One Again" }, // duplicate
    { phone: "not-a-number", name: "Bad Phone" },        // invalid_phone
    { phone: "+919999222202", name: "   " },             // invalid_name
    { phone: "+919999222203", name: "x".repeat(129) },   // invalid_name
    { phone, name: "Me" },                                // self
  ];
  const res = await post({ contacts }, jwt);
  assertEquals(res.status, 200);
  const body = await res.json();

  assertEquals(
    body.added + body.skipped + body.failed + body.duplicates,
    contacts.length,
    "added + skipped + failed + duplicates must equal contacts.length",
  );
  assertEquals(
    body.results.length,
    contacts.length,
    "one result per input index, so the client can zip positionally",
  );
  assertEquals(body.results.map((r: { status: string }) => r.status), [
    "added",
    "duplicate",
    "invalid_phone",
    "invalid_name",
    "invalid_name",
    "self",
  ]);
});

Deno.test("a repeat occurrence echoes the first verdict, not a second edge", async () => {
  const { jwt } = await signedInUser();
  const contacts = [
    { phone: "+919999222301", name: "Twice" },
    { phone: "+919999222301", name: "Twice" },
  ];
  const body = await (await post({ contacts }, jwt)).json();
  assertEquals(body.added, 1, "one real edge");
  assertEquals(body.duplicates, 1);
  assertEquals(
    body.results[0].person_id,
    body.results[1].person_id,
    "the duplicate carries the first occurrence's person_id",
  );
});

Deno.test("a birthday supplied with the contact is stored", async () => {
  const { jwt } = await signedInUser();
  const contacts = [{
    phone: "+919999222401",
    name: "Has Birthday",
    birth_month: 4,
    birth_day: 15,
    birth_year: null,
  }];
  const body = await (await post({ contacts }, jwt)).json();
  assertEquals(body.added, 1);

  const admin = createClient(URL, SERVICE);
  const { data } = await admin
    .from("people")
    .select("birth_month, birth_day")
    .eq("id", body.results[0].person_id)
    .single();
  assertEquals(data, { birth_month: 4, birth_day: 15 });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ~/Desktop/Projects/birthday_app
# Deno is a prerequisite and is not bundled with the Supabase CLI:
#   brew install deno
supabase start
supabase functions serve --no-verify-jwt &
export SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
export SUPABASE_SERVICE_ROLE_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')
deno test --allow-net --allow-env supabase/functions/add_celebrations/index.test.ts
```

Expected: the file does not exist yet on the first run of this step; after creating it in Step 1, expect the tests to **run and pass**, because the function is already implemented. This task is characterisation, not TDD — the code under test shipped in Phase 2a with no coverage at all.

- [ ] **Step 3: Prove the tests are load-bearing**

Because the implementation already exists, a passing suite proves nothing on its own. For each of the three behavioural tests, break the function and confirm the matching test fails:

1. In `index.ts`, change `status: "duplicate"` to `status: "added"` → the count-invariant test must fail. (Only that one: the repeat-occurrence test asserts on the counters and `person_id`, not on the status string, so it stays green. Expecting both to fail is wrong.)
2. Change `MAX_BATCH` to `5000` → the 413 test must fail.
3. Remove the `if (!auth)` block → the 401 test must fail.

Revert each change after observing the failure.

Expected: three observed failures. Record them in the task's verification notes.

- [ ] **Step 4: Add a runner script so this is not a one-off**

Create `supabase/functions/test.sh`:

```bash
#!/usr/bin/env bash
# Edge Function tests. Requires `supabase start` and `supabase functions serve`
# to already be running -- both are long-lived and this script does not own them.
set -euo pipefail
cd "$(dirname "$0")/../.."

SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
SUPABASE_SERVICE_ROLE_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')
export SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY

deno test --allow-net --allow-env supabase/functions/
```

Then `chmod +x supabase/functions/test.sh` and run it once to confirm it works.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/add_celebrations/index.test.ts supabase/functions/test.sh
git commit -m "test(functions): pin the add_celebrations import contract

Carry-forward #1: this function had zero automated coverage and its
status vocabulary is what the import screen is about to depend on.
Covers the count invariant, positional results, MAX_BATCH and the 401."
```

---

## Task 3: Flutter scaffold

Spec §5. This repository has no `pubspec.yaml`. Everything after this task depends on the project existing, the theme constants being in place, and the app booting against local Supabase.

**Files:**
- Create: `.fvmrc`, `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/app.dart`
- Create: `lib/core/app_colors.dart`, `app_text_styles.dart`, `app_spacing.dart`, `app_strings.dart`, `logger.dart`, `result.dart`
- Create: `lib/api/api_client.dart`, `api_endpoints.dart`, `api_params.dart`, `api_connectivity.dart`, `api_error_mapper.dart`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `ApiClient.instance` (a `SupabaseClient`), `AppFailure` and its subtypes, `mapError(Object)`, and the four `core/` const holders. Every later task consumes these.

- [ ] **Step 1: Pin the Flutter version and generate the project**

```bash
cd ~/Desktop/Projects/birthday_app
fvm use 3.35.2 --force
fvm flutter create --project-name birthday_app --org com.birthdayapp \
  --platforms=android,ios --no-pub .
```

`flutter create` writes its own `.gitignore`. Merge it rather than letting it replace the existing one — the repo's current `.gitignore` covers `supabase/` artefacts that must stay ignored.

- [ ] **Step 2: Write `pubspec.yaml` dependencies**

Replace the generated `dependencies` and `dev_dependencies` blocks:

```yaml
environment:
  sdk: ^3.9.0

dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.8.0
  flutter_bloc: ^8.1.6
  go_router: ^14.6.0
  flutter_contacts: ^1.1.9
  phone_numbers_parser: ^9.0.0
  fluttertoast: ^8.2.8
  connectivity_plus: ^6.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.1.7
  flutter_lints: ^5.0.0
```

Then:

```bash
fvm flutter pub get
```

- [ ] **Step 3: Write the core constant files**

`lib/core/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// One seed colour; Material 3 derives the rest. The spec declines golden
/// tests in M1 precisely because this is expected to change, so nothing here
/// is load-bearing beyond being centralised.
abstract final class AppColors {
  static const seed = Color(0xFFE05A47);

  static ColorScheme light() =>
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
  static ColorScheme dark() =>
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
}
```

`lib/core/app_spacing.dart`:

```dart
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}
```

`lib/core/app_text_styles.dart`:

```dart
import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static TextTheme of(BuildContext context) => Theme.of(context).textTheme;

  static TextStyle sectionHeader(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
}
```

`lib/core/app_strings.dart` — every user-facing string in the app. Start with what Tasks 6–13 need; each later task appends to this file rather than writing a literal in a screen:

```dart
abstract final class AppStrings {
  // Generic
  static const appName = 'Birthday';
  static const retry = 'Try again';
  static const cancel = 'Cancel';
  static const save = 'Save';
  static const somethingWentWrong = 'Something went wrong. Please try again.';
  static const noConnection = 'No internet connection.';

  // Onboarding — phone
  static const phoneTitle = 'What is your number?';
  static const phoneSubtitle =
      'We use it to find the people you already know.';
  static const phoneHint = 'Phone number';
  static const phoneInvalid = 'That does not look like a valid number.';
  static const sendCode = 'Send code';
  static const otpTitle = 'Enter the code';
  static const otpSubtitleTemplate = 'We sent a 6-digit code to %s.';
  static const otpHint = '6-digit code';
  static const otpIncorrect = 'That code is not right.';
  static const otpExpired = 'That code has expired. Ask for a new one.';
  static const resendCode = 'Resend code';
  static const resendCooldownTemplate = 'Resend in %ss';
  static const claimConflict =
      'This account is already linked to a different phone number.';
}
```

`lib/core/logger.dart`:

```dart
import 'dart:developer' as developer;

/// One logger. `print` is banned by analysis_options.
abstract final class Log {
  static void info(String message) =>
      developer.log(message, name: 'birthday');

  static void error(String message, [Object? error, StackTrace? stack]) =>
      developer.log(message, name: 'birthday', error: error, stackTrace: stack);
}
```

`lib/core/result.dart`:

```dart
/// Failures the UI can branch on. Repositories throw these; Cubits catch them.
/// Anything not modelled here reaches the user as [AppStrings.somethingWentWrong].
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
}

/// No usable network connection, detected before the request was made.
final class OfflineFailure extends AppFailure {
  const OfflineFailure(super.message);
}

/// The server understood and refused. [code] is the SQLSTATE or the HTTP
/// status, kept because callers branch on specific ones (23505, 45002, 409).
final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {this.code});
  final String? code;
}

/// The session is missing or no longer valid.
final class AuthFailure extends AppFailure {
  const AuthFailure(super.message);
}

/// The user, the OS, or a device permission refused.
final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message);
}
```

- [ ] **Step 4: Write the api layer**

`lib/api/api_client.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase singleton. Defaults point at the local stack, so a developer
/// with `supabase start` running needs no --dart-define at all.
abstract final class ApiClient {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> init() =>
      Supabase.initialize(url: url, anonKey: anonKey).then((_) {});

  static SupabaseClient get instance => Supabase.instance.client;
}
```

`lib/api/api_endpoints.dart`:

```dart
/// Edge Function names and RPC names. No caller spells these inline.
abstract final class ApiEndpoints {
  static const claimProfile = 'claim_profile';
  static const resolveContacts = 'resolve_contacts';
  static const addCelebrations = 'add_celebrations';
  static const deleteAccount = 'delete_account';

  static const rpcUpdatePersonBirthday = 'rpc_update_person_birthday';
}
```

`lib/api/api_params.dart`:

```dart
/// Column names and RPC argument names. Typos here are runtime errors that
/// PostgREST reports as "column does not exist", so they live in one place.
abstract final class ApiParams {
  // tables
  static const profiles = 'profiles';
  static const people = 'people';
  static const celebrations = 'celebrations';
  static const deviceTokens = 'device_tokens';

  // profiles
  static const id = 'id';
  static const profileId = 'profile_id';
  static const handle = 'handle';
  static const displayName = 'display_name';
  static const city = 'city';
  static const remindersEnabled = 'reminders_enabled';

  // birthday parts, on both people and profiles
  static const birthMonth = 'birth_month';
  static const birthDay = 'birth_day';
  static const birthYear = 'birth_year';

  // celebrations
  static const celebratorProfileId = 'celebrator_profile_id';
  static const personId = 'person_id';
  static const nickname = 'nickname';
  static const source = 'source';

  // rpc_update_person_birthday
  static const pPersonId = 'p_person_id';
  static const pBirthMonth = 'p_birth_month';
  static const pBirthDay = 'p_birth_day';
  static const pBirthYear = 'p_birth_year';
}
```

`lib/api/api_connectivity.dart`:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

/// Pre-flight check. Cheaper and clearer than letting a request hang and
/// surfacing a socket exception the user cannot act on.
class ApiConnectivity {
  const ApiConnectivity(this._connectivity);
  final Connectivity _connectivity;

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
}
```

`lib/api/api_error_mapper.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_strings.dart';
import '../core/result.dart';

/// Turns the client's exception zoo into the four failures the UI branches on.
///
/// SQLSTATE survives into [ServerFailure.code] deliberately: docs/db.md records
/// that the codes are a public API decision, and callers branch on specific
/// ones -- 23505 for a taken handle, 45002/45003 for the birthday-edit guards.
AppFailure mapError(Object error) {
  if (error is AppFailure) return error;

  if (error is AuthException) {
    return AuthFailure(error.message);
  }
  if (error is PostgrestException) {
    return ServerFailure(error.message, code: error.code);
  }
  if (error is FunctionException) {
    final detail = error.details;
    final message = detail is Map && detail['error'] is String
        ? detail['error'] as String
        : AppStrings.somethingWentWrong;
    return ServerFailure(message, code: '${error.status}');
  }
  return ServerFailure(AppStrings.somethingWentWrong);
}
```

- [ ] **Step 5: Write `main.dart` and `app.dart` booting to a placeholder**

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();
  runApp(const BirthdayApp());
}
```

`lib/app.dart` — a placeholder home for now; Task 6 replaces it with the router:

```dart
import 'package:flutter/material.dart';

import 'core/app_colors.dart';
import 'core/app_strings.dart';

class BirthdayApp extends StatelessWidget {
  const BirthdayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      theme: ThemeData(colorScheme: AppColors.light(), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: AppColors.dark(), useMaterial3: true),
      home: const Scaffold(body: Center(child: Text(AppStrings.appName))),
    );
  }
}
```

- [ ] **Step 6: Tighten the analyzer**

Append to `analysis_options.yaml`:

```yaml
linter:
  rules:
    avoid_print: true
    prefer_single_quotes: true
    require_trailing_commas: true
```

- [ ] **Step 7: Verify it analyzes and boots**

```bash
fvm flutter analyze
fvm flutter run --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: `No issues found.` and an app showing the word "Birthday" on a simulator.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(app): Flutter scaffold, theme constants and the api layer

Pins Flutter 3.35.2. Supabase client rather than dio, per spec §5 --
auth, RLS and token refresh come with it."
```

---

## Task 4: The `Birthday` model and its occurrence rules

Spec §6.3. This is the only model with real logic, and the rule it encodes — **Feb 29 falls on Feb 28 in non-leap years** — must match the reminder fan-out exactly. A timeline that disagrees with the notification the user just received is worse than either alone.

**Files:**
- Create: `lib/models/birthday.dart`, `lib/models/person.dart`, `lib/models/profile.dart`, `lib/models/celebration.dart`
- Create: `test/models/birthday_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `Birthday({required int month, required int day, int? year})`, `Birthday.fromRow(Map<String, dynamic>)` returning `null` when `birth_month` is null, `birthday.nextOccurrence(DateTime from)`, `birthday.groupFrom(DateTime from)` returning `TimelineGroup`. Tasks 9, 10, 11 and 12 all consume these. `Person`, `Profile` and `Celebration` expose `fromRow` constructors.

- [ ] **Step 1: Write the failing test**

Create `test/models/birthday_test.dart`:

```dart
import 'package:birthday_app/models/birthday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextOccurrence', () {
    test('returns this year when the birthday is still ahead', () {
      final b = Birthday(month: 4, day: 15);
      expect(b.nextOccurrence(DateTime(2026, 1, 10)), DateTime(2026, 4, 15));
    });

    test('returns today when the birthday is today', () {
      final b = Birthday(month: 4, day: 15);
      expect(b.nextOccurrence(DateTime(2026, 4, 15)), DateTime(2026, 4, 15));
    });

    test('rolls to next year once the birthday has passed', () {
      final b = Birthday(month: 4, day: 15);
      expect(b.nextOccurrence(DateTime(2026, 4, 16)), DateTime(2027, 4, 15));
    });

    // The December-to-January wraparound that the reminder fan-out is tested
    // for in pgTAP. The client must agree with it.
    test('handles the December to January wraparound', () {
      final b = Birthday(month: 1, day: 4);
      expect(b.nextOccurrence(DateTime(2026, 12, 28)), DateTime(2027, 1, 4));
    });

    test('a Feb 29 birthday falls on Feb 28 in a non-leap year', () {
      final b = Birthday(month: 2, day: 29);
      expect(b.nextOccurrence(DateTime(2027, 1, 1)), DateTime(2027, 2, 28));
    });

    test('a Feb 29 birthday stays on Feb 29 in a leap year', () {
      final b = Birthday(month: 2, day: 29);
      expect(b.nextOccurrence(DateTime(2028, 1, 1)), DateTime(2028, 2, 29));
    });

    test('1900 is not a leap year and 2000 is', () {
      expect(Birthday.isLeapYear(1900), isFalse);
      expect(Birthday.isLeapYear(2000), isTrue);
      expect(Birthday.isLeapYear(2027), isFalse);
      expect(Birthday.isLeapYear(2028), isTrue);
    });
  });

  group('groupFrom', () {
    final b = Birthday(month: 4, day: 15);

    test('today', () {
      expect(b.groupFrom(DateTime(2026, 4, 15)), TimelineGroup.today);
    });

    test('tomorrow and day seven are this week', () {
      expect(b.groupFrom(DateTime(2026, 4, 14)), TimelineGroup.thisWeek);
      expect(b.groupFrom(DateTime(2026, 4, 8)), TimelineGroup.thisWeek);
    });

    test('day eight is this month', () {
      expect(b.groupFrom(DateTime(2026, 4, 7)), TimelineGroup.thisMonth);
    });

    test('day thirty-one is this month and day thirty-two is later', () {
      expect(b.groupFrom(DateTime(2026, 3, 15)), TimelineGroup.thisMonth);
      expect(b.groupFrom(DateTime(2026, 3, 14)), TimelineGroup.later);
    });
  });

  group('fromRow', () {
    test('returns null when the person has no birthday recorded', () {
      expect(
        Birthday.fromRow({'birth_month': null, 'birth_day': null}),
        isNull,
      );
    });

    test('reads month and day without a year', () {
      final b = Birthday.fromRow({
        'birth_month': 4,
        'birth_day': 15,
        'birth_year': null,
      });
      expect(b, isNotNull);
      expect(b!.month, 4);
      expect(b.day, 15);
      expect(b.year, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
fvm flutter test test/models/birthday_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:birthday_app/models/birthday.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/models/birthday.dart`:

```dart
import '../api/api_params.dart';

/// Where a birthday sits relative to today. The boundaries are chosen, not
/// obvious: Today is day 0, This week is days 1-7, This month is days 8-31,
/// and anything further out is Later.
enum TimelineGroup { today, thisWeek, thisMonth, later }

/// Month and day are required together; the year is optional because device
/// address books routinely carry a birthday with no year, and reminders only
/// ever need month and day.
class Birthday {
  const Birthday({required this.month, required this.day, this.year});

  final int month;
  final int day;
  final int? year;

  static Birthday? fromRow(Map<String, dynamic> row) {
    final month = row[ApiParams.birthMonth] as int?;
    final day = row[ApiParams.birthDay] as int?;
    if (month == null || day == null) return null;
    return Birthday(month: month, day: day, year: row[ApiParams.birthYear] as int?);
  }

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  /// The next date this birthday is celebrated on or after [from].
  ///
  /// A Feb 29 birthday falls on **Feb 28** in non-leap years. This keeps the
  /// celebration inside February rather than sliding into March, and it is the
  /// same rule the pg_cron reminder fan-out uses -- the two must not disagree.
  DateTime nextOccurrence(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final thisYear = _inYear(today.year);
    return thisYear.isBefore(today) ? _inYear(today.year + 1) : thisYear;
  }

  DateTime _inYear(int year) {
    if (month == 2 && day == 29 && !isLeapYear(year)) {
      return DateTime(year, 2, 28);
    }
    return DateTime(year, month, day);
  }

  TimelineGroup groupFrom(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final days = nextOccurrence(from).difference(today).inDays;
    if (days == 0) return TimelineGroup.today;
    if (days <= 7) return TimelineGroup.thisWeek;
    if (days <= 31) return TimelineGroup.thisMonth;
    return TimelineGroup.later;
  }

  @override
  bool operator ==(Object other) =>
      other is Birthday &&
      other.month == month &&
      other.day == day &&
      other.year == year;

  @override
  int get hashCode => Object.hash(month, day, year);
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
fvm flutter test test/models/birthday_test.dart
```

Expected: `All tests passed!` — 13 assertions.

- [ ] **Step 5: Prove the Feb 29 assertion is load-bearing**

Delete the `if (month == 2 && day == 29 ...)` branch from `_inYear` and re-run. Expected: `a Feb 29 birthday falls on Feb 28 in a non-leap year` **fails**. Restore the branch.

- [ ] **Step 6: Write the three row models**

`lib/models/person.dart`:

```dart
import '../api/api_params.dart';
import 'birthday.dart';

/// A row in public.people. `isClaimed` decides whether this person's birthday
/// is editable: a claimed person owns their own date of birth, and
/// rpc_update_person_birthday refuses with 45003.
class Person {
  const Person({
    required this.id,
    required this.displayName,
    required this.isClaimed,
    this.birthday,
  });

  final int id;
  final String displayName;
  final bool isClaimed;
  final Birthday? birthday;

  factory Person.fromRow(Map<String, dynamic> row) => Person(
        id: row[ApiParams.id] as int,
        displayName: row[ApiParams.displayName] as String,
        isClaimed: row[ApiParams.profileId] != null,
        birthday: Birthday.fromRow(row),
      );
}
```

`lib/models/celebration.dart`:

```dart
import '../api/api_params.dart';
import 'person.dart';

/// An edge from the signed-in user to a person they celebrate, with the person
/// embedded. `nickname` overrides the address-book name in the UI.
class Celebration {
  const Celebration({
    required this.id,
    required this.person,
    this.nickname,
  });

  final int id;
  final Person person;
  final String? nickname;

  String get label => nickname ?? person.displayName;

  factory Celebration.fromRow(Map<String, dynamic> row) => Celebration(
        id: row[ApiParams.id] as int,
        nickname: row[ApiParams.nickname] as String?,
        person: Person.fromRow(row[ApiParams.people] as Map<String, dynamic>),
      );
}
```

`lib/models/profile.dart`:

```dart
import '../api/api_params.dart';
import 'birthday.dart';

/// A row in public.profiles.
///
/// The row is created by the private.handle_new_user trigger on signup, with a
/// placeholder handle ('u' + uuid without dashes) and display_name 'New user'.
/// Both are non-null from birth, so neither can tell a fresh account from a
/// finished one -- [hasCompletedOnboarding] reads the birthday instead, which
/// is required by the setup screen and null until it completes.
class Profile {
  const Profile({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.remindersEnabled,
    this.city,
    this.birthday,
  });

  final String id;
  final String handle;
  final String displayName;
  final bool remindersEnabled;
  final String? city;
  final Birthday? birthday;

  bool get hasCompletedOnboarding => birthday != null;

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
        id: row[ApiParams.id] as String,
        handle: row[ApiParams.handle] as String,
        displayName: row[ApiParams.displayName] as String,
        remindersEnabled: row[ApiParams.remindersEnabled] as bool,
        city: row[ApiParams.city] as String?,
        birthday: Birthday.fromRow(row),
      );
}
```

- [ ] **Step 7: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test
git add lib/models test/models
git commit -m "feat(models): Birthday with the Feb 29 rule, plus the row models

Feb 29 falls on Feb 28 in non-leap years, matching the reminder fan-out.
A timeline that disagrees with the notification is worse than either."
```

---

## Task 5: `AuthRepository` and its contract tests

Spec §6.1 and §7. Contract-tested against **real local Supabase**, not fakes. That is the spec's deliberate call and M0 is the evidence: `private.can_see_person` broke three separate ways and a fake repository would have passed every one.

**Files:**
- Create: `lib/repositories/auth_repository.dart`, `lib/repositories/auth_repository_impl.dart`
- Create: `test/repositories/auth_repository_test.dart`
- Modify: `lib/core/app_strings.dart` (add the strings this task introduces)

**Interfaces:**
- Consumes: `ApiClient.instance`, `ApiEndpoints`, `ApiParams`, `mapError`, `Profile`, `Birthday`.
- Produces: `AuthRepository` with `currentUserId`, `sendOtp(String)`, `verifyOtp({phoneE164, token})`, `claimProfile() → Future<int>`, `loadProfile() → Future<Profile>`, `completeProfile({handle, displayName, city, birthday})`, `signOut()`, `deleteAccount()`. Tasks 6, 7, 8 and 13 consume it.

- [ ] **Step 1: Write the failing contract test**

Create `test/repositories/auth_repository_test.dart`:

```dart
@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Requires the local stack: `supabase start` and `supabase functions serve`.
/// Run with:
///   fvm flutter test test/repositories \
///     --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | \
///        python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
void main() {
  late AuthRepository repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ApiClient.init();
    repo = AuthRepositoryImpl(ApiClient.instance);
  });

  // The three numbers in [auth.sms.test_otp], all with OTP 123456.
  const phoneA = '+919999000001';
  const phoneB = '+919999000002';

  tearDown(() async {
    if (ApiClient.instance.auth.currentSession != null) {
      await repo.deleteAccount().catchError((_) {});
    }
  });

  test('a full OTP round trip produces a session', () async {
    await repo.sendOtp(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    expect(repo.currentUserId, isNotNull);
  });

  test('a wrong code is an AuthFailure, not a crash', () async {
    await repo.sendOtp(phoneA);
    await expectLater(
      repo.verifyOtp(phoneE164: phoneA, token: '000000'),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('claimProfile returns a person id and is idempotent', () async {
    await repo.sendOtp(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');

    final first = await repo.claimProfile();
    final second = await repo.claimProfile();
    expect(first, isPositive);
    expect(second, first, reason: 'a retried onboarding must not fork identity');
  });

  // The trigger creates the row; the app never inserts one. A fresh profile is
  // therefore readable immediately and is NOT complete.
  test('a fresh profile exists, has a placeholder handle, and is incomplete',
      () async {
    await repo.sendOtp(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');

    final profile = await repo.loadProfile();
    expect(profile.handle, startsWith('u'));
    expect(profile.displayName, 'New user');
    expect(profile.birthday, isNull);
    expect(profile.hasCompletedOnboarding, isFalse);
  });

  test('completeProfile writes every field and flips the onboarding flag',
      () async {
    await repo.sendOtp(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');

    await repo.completeProfile(
      handle: 'contract_test_user',
      displayName: 'Contract Test',
      city: 'Jaipur',
      birthday: const Birthday(month: 4, day: 15, year: 1991),
    );

    final profile = await repo.loadProfile();
    expect(profile.handle, 'contract_test_user');
    expect(profile.displayName, 'Contract Test');
    expect(profile.city, 'Jaipur');
    expect(profile.birthday, const Birthday(month: 4, day: 15, year: 1991));
    expect(profile.hasCompletedOnboarding, isTrue);
  });

  // The schema enforces a unique handle. Onboarding is renaming, not naming,
  // so this branch is reachable on the very first screen a user sees.
  test('a taken handle surfaces as ServerFailure with code 23505', () async {
    await repo.sendOtp(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.completeProfile(
      handle: 'taken_handle',
      displayName: 'First',
      city: 'Jaipur',
      birthday: const Birthday(month: 1, day: 1),
    );
    final firstUserId = repo.currentUserId;

    await repo.signOut();
    await repo.sendOtp(phoneB);
    await repo.verifyOtp(phoneE164: phoneB, token: '123456');

    await expectLater(
      repo.completeProfile(
        handle: 'taken_handle',
        displayName: 'Second',
        city: 'Jaipur',
        birthday: const Birthday(month: 2, day: 2),
      ),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', '23505')),
    );

    // Clean up the first user too; tearDown only reaches the current session.
    await repo.deleteAccount();
    expect(firstUserId, isNotNull);
  });

  test('signOut clears the session', () async {
    await repo.sendOtp(phoneA);
    await repo.verifyOtp(phoneE164: phoneA, token: '123456');
    await repo.signOut();
    expect(repo.currentUserId, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase start && supabase functions serve &
fvm flutter test test/repositories/auth_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: FAIL — `Target of URI doesn't exist: '.../auth_repository.dart'`.

- [ ] **Step 3: Write the interface**

Create `lib/repositories/auth_repository.dart`:

```dart
import '../models/birthday.dart';
import '../models/profile.dart';

/// Everything the app does with identity. The split from the implementation is
/// what keeps the data source swappable -- the spec's justification for using
/// the Supabase client directly instead of the house dio layer.
abstract interface class AuthRepository {
  String? get currentUserId;

  /// Sends the OTP. Locally this is served from [auth.sms.test_otp]; no SMS
  /// provider is configured and none is needed until Phase 2c.
  Future<void> sendOtp(String phoneE164);

  Future<void> verifyOtp({required String phoneE164, required String token});

  /// Links this session's verified phone to its person row. Returns the
  /// person id. Throws [ServerFailure] with code '409' when the profile has
  /// already claimed a different number.
  Future<int> claimProfile();

  Future<Profile> loadProfile();

  /// An UPDATE. The profiles row already exists -- private.handle_new_user
  /// creates it on signup. Throws [ServerFailure] with code '23505' when the
  /// handle is taken.
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  });

  Future<void> signOut();

  Future<void> deleteAccount();
}
```

- [ ] **Step 4: Write the implementation**

Create `lib/repositories/auth_repository_impl.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../core/result.dart';
import '../models/birthday.dart';
import '../models/profile.dart';
import 'auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> sendOtp(String phoneE164) async {
    try {
      await _client.auth.signInWithOtp(phone: phoneE164);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async {
    try {
      await _client.auth.verifyOTP(
        phone: phoneE164,
        token: token,
        type: OtpType.sms,
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<int> claimProfile() async {
    try {
      final res = await _client.functions.invoke(ApiEndpoints.claimProfile);
      final data = res.data as Map<String, dynamic>;
      return data['person_id'] as int;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<Profile> loadProfile() async {
    final id = currentUserId;
    if (id == null) throw const AuthFailure('no session');
    try {
      final row = await _client
          .from(ApiParams.profiles)
          .select()
          .eq(ApiParams.id, id)
          .single();
      return Profile.fromRow(row);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    final id = currentUserId;
    if (id == null) throw const AuthFailure('no session');
    try {
      await _client.from(ApiParams.profiles).update({
        ApiParams.handle: handle,
        ApiParams.displayName: displayName,
        ApiParams.city: city,
        ApiParams.birthMonth: birthday.month,
        ApiParams.birthDay: birthday.day,
        ApiParams.birthYear: birthday.year,
      }).eq(ApiParams.id, id);
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke(ApiEndpoints.deleteAccount);
      await _client.auth.signOut();
    } catch (e) {
      throw mapError(e);
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
fvm flutter test test/repositories/auth_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: `All tests passed!` — 7 tests.

- [ ] **Step 6: Prove the 23505 branch is real**

Change the taken-handle test's second handle to a unique value and confirm the test **fails** (it now expects a throw that no longer happens). Restore it. This is the assertion most likely to pass for the wrong reason, because any error at all would satisfy a looser matcher — the `.having((f) => f.code, 'code', '23505')` is what makes it evidence.

- [ ] **Step 7: Commit**

```bash
git add lib/repositories/auth_repository.dart lib/repositories/auth_repository_impl.dart \
        test/repositories/auth_repository_test.dart
git commit -m "feat(auth): the identity repository, contract-tested against local Supabase

Fakes hide exactly the RLS and grant failures that cost the most in M0,
so these tests run against the real stack."
```

---

## Task 6: The router and its onboarding guard

Spec §6.1. The guard has three states and the signal it reads is not obvious, because `private.handle_new_user` fills both the handle and the display name with placeholders at signup. `profiles.birth_month is not null` is the marker.

`SessionCubit` lives in `lib/router/` rather than `lib/features/`, because the router guard is its only consumer.

**Files:**
- Create: `lib/router/app_router.dart`, `lib/router/session_cubit.dart`, `lib/router/session_state.dart`
- Modify: `lib/app.dart`
- Create: `test/router/session_cubit_test.dart`

**Interfaces:**
- Consumes: `AuthRepository`.
- Produces: `SessionCubit(AuthRepository)` with `load()`, `onSignedIn()`, `onProfileCompleted()`, `signOut()`; `SessionState` = `SessionUnknown | SessionSignedOut | SessionNeedsSetup | SessionReady(Profile)`; `buildRouter(SessionCubit)`. Routes: `/phone`, `/otp`, `/setup`, `/timeline`, `/import`, `/settings`.

- [ ] **Step 1: Write the failing test**

Create `test/router/session_cubit_test.dart`:

```dart
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/profile.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/router/session_cubit.dart';
import 'package:birthday_app/router/session_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake is right here and wrong for repositories. This tests state
/// transitions, which are the Cubit's own logic; the repository's behaviour is
/// covered against real Supabase in Task 5.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.userId, this.profile, this.throwOnLoad = false});

  String? userId;
  Profile? profile;
  bool throwOnLoad;

  @override
  String? get currentUserId => userId;

  @override
  Future<Profile> loadProfile() async {
    if (throwOnLoad) throw const ServerFailure('boom');
    return profile!;
  }

  @override
  Future<void> signOut() async {
    userId = null;
    profile = null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile({Birthday? birthday}) => Profile(
      id: 'uuid',
      handle: 'u123',
      displayName: 'New user',
      remindersEnabled: true,
      birthday: birthday,
    );

void main() {
  blocTest<SessionCubit, SessionState>(
    'no session resolves to signed out',
    build: () => SessionCubit(_FakeAuthRepository()),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionSignedOut>()],
  );

  blocTest<SessionCubit, SessionState>(
    'a session with no birthday needs setup',
    build: () => SessionCubit(
      _FakeAuthRepository(userId: 'uuid', profile: _profile()),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionNeedsSetup>()],
  );

  blocTest<SessionCubit, SessionState>(
    'a session with a birthday is ready',
    build: () => SessionCubit(
      _FakeAuthRepository(
        userId: 'uuid',
        profile: _profile(birthday: const Birthday(month: 4, day: 15)),
      ),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionReady>()],
  );

  // A profile that cannot be read must not strand the user on a blank screen.
  // Signing them out is recoverable; an unknown state is not.
  blocTest<SessionCubit, SessionState>(
    'a failed profile load falls back to signed out',
    build: () => SessionCubit(
      _FakeAuthRepository(userId: 'uuid', throwOnLoad: true),
    ),
    act: (cubit) => cubit.load(),
    expect: () => [isA<SessionSignedOut>()],
  );

  blocTest<SessionCubit, SessionState>(
    'signOut returns to signed out',
    build: () => SessionCubit(
      _FakeAuthRepository(
        userId: 'uuid',
        profile: _profile(birthday: const Birthday(month: 4, day: 15)),
      ),
    ),
    act: (cubit) async {
      await cubit.load();
      await cubit.signOut();
    },
    expect: () => [isA<SessionReady>(), isA<SessionSignedOut>()],
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
fvm flutter test test/router/session_cubit_test.dart
```

Expected: FAIL — the URIs do not exist.

- [ ] **Step 3: Write the state and cubit**

`lib/router/session_state.dart`:

```dart
import '../models/profile.dart';

sealed class SessionState {
  const SessionState();
}

/// Before the first load resolves. The router shows a splash, never a screen.
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// Signed in, but profiles.birth_month is still null.
final class SessionNeedsSetup extends SessionState {
  const SessionNeedsSetup();
}

final class SessionReady extends SessionState {
  const SessionReady(this.profile);
  final Profile profile;
}
```

`lib/router/session_cubit.dart`:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/logger.dart';
import '../repositories/auth_repository.dart';
import 'session_state.dart';

/// The single source of truth for which part of the app the user belongs in.
///
/// The completion signal is `profiles.birth_month is not null`. The handle and
/// display name cannot be used: private.handle_new_user sets both to
/// placeholders at signup, so both are non-null on a brand new account.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._auth) : super(const SessionUnknown());
  final AuthRepository _auth;

  Future<void> load() async {
    if (_auth.currentUserId == null) {
      emit(const SessionSignedOut());
      return;
    }
    try {
      final profile = await _auth.loadProfile();
      emit(profile.hasCompletedOnboarding
          ? SessionReady(profile)
          : const SessionNeedsSetup());
    } catch (e, s) {
      // A session we cannot resolve is worse than no session: the user would
      // sit on a splash with no way forward. Signing out is recoverable.
      Log.error('session load failed', e, s);
      emit(const SessionSignedOut());
    }
  }

  Future<void> onSignedIn() => load();

  Future<void> onProfileCompleted() => load();

  Future<void> signOut() async {
    await _auth.signOut();
    emit(const SessionSignedOut());
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
fvm flutter test test/router/session_cubit_test.dart
```

Expected: `All tests passed!` — 5 tests.

- [ ] **Step 5: Write the router**

Create `lib/router/app_router.dart`. The screen classes referenced here are created in Tasks 7, 8, 10, 12 and 13; until then, stub each as a `Scaffold` so the app compiles, and delete the stub in the task that builds it for real.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'session_cubit.dart';
import 'session_state.dart';

/// Bridges a Cubit to go_router's Listenable-based refresh.
class _CubitRefresh extends ChangeNotifier {
  _CubitRefresh(Stream<SessionState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<SessionState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter buildRouter(SessionCubit session) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _CubitRefresh(session.stream),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: '/timeline', builder: (_, __) => const TimelineScreen()),
      GoRoute(path: '/import', builder: (_, __) => const ImportDisclosureScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
    redirect: (context, state) {
      final s = session.state;
      final at = state.matchedLocation;

      // Never route anywhere until the first load resolves.
      if (s is SessionUnknown) return at == '/splash' ? null : '/splash';

      final target = switch (s) {
        SessionSignedOut() => '/phone',
        SessionNeedsSetup() => '/setup',
        SessionReady() => '/timeline',
        SessionUnknown() => '/splash',
      };

      // Once ready, the user moves freely between the signed-in screens.
      const signedIn = {'/timeline', '/import', '/settings'};
      if (s is SessionReady && signedIn.contains(at)) return null;

      return at == target ? null : target;
    },
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

// Placeholders so this task compiles on its own. Each later screen task
// DELETES its placeholder here and adds the real import at the top of the
// file: Task 7 -> PhoneScreen, Task 8 -> ProfileSetupScreen, Task 10 ->
// ImportDisclosureScreen, Task 12 -> TimelineScreen, Task 13 ->
// SettingsScreen. Leaving one behind shadows the real screen silently.
class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class ImportDisclosureScreen extends StatelessWidget {
  const ImportDisclosureScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold();
}
```


- [ ] **Step 6: Wire `app.dart`**

Replace `lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api/api_client.dart';
import 'core/app_colors.dart';
import 'core/app_strings.dart';
import 'repositories/auth_repository.dart';
import 'repositories/auth_repository_impl.dart';
import 'router/app_router.dart';
import 'router/session_cubit.dart';

class BirthdayApp extends StatefulWidget {
  const BirthdayApp({super.key});

  @override
  State<BirthdayApp> createState() => _BirthdayAppState();
}

class _BirthdayAppState extends State<BirthdayApp> {
  late final AuthRepository _auth = AuthRepositoryImpl(ApiClient.instance);
  late final SessionCubit _session = SessionCubit(_auth)..load();
  late final _router = buildRouter(_session);

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [RepositoryProvider<AuthRepository>.value(value: _auth)],
      child: BlocProvider.value(
        value: _session,
        child: MaterialApp.router(
          title: AppStrings.appName,
          theme: ThemeData(colorScheme: AppColors.light(), useMaterial3: true),
          darkTheme: ThemeData(colorScheme: AppColors.dark(), useMaterial3: true),
          routerConfig: _router,
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test
git add lib/router lib/app.dart test/router
git commit -m "feat(router): the three-state onboarding guard

The completion signal is profiles.birth_month, not the handle or display
name -- the signup trigger sets placeholders for both, so neither can
tell a fresh account from a finished one."
```

---

## Task 7: Phone entry and OTP screens

Spec §6.1. Cubit tested with `bloc_test` against a fake — state transitions are the Cubit's own logic, and the repository is already covered against real Supabase. Plus a widget test, because OTP entry is one of the three screens the spec names as riskiest.

**Files:**
- Create: `lib/features/onboarding/phone_cubit.dart`, `phone_state.dart`, `phone_screen.dart`, `otp_screen.dart`
- Create: `test/features/onboarding/phone_cubit_test.dart`, `test/features/onboarding/otp_screen_test.dart`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart` (drop the `PhoneScreen` stub)

**Interfaces:**
- Consumes: `AuthRepository`, `SessionCubit.onSignedIn()`, `AppFailure` subtypes.
- Produces: `PhoneCubit(AuthRepository)` with `submitPhone(String raw, {String isoCode = 'IN'})`, `submitCode(String)`, `resend()`; `PhoneState` = `PhoneIdle | PhoneSending | PhoneCodeSent | PhoneVerifying | PhoneVerified | PhoneError`.

- [ ] **Step 1: Write the failing Cubit test**

Create `test/features/onboarding/phone_cubit_test.dart`:

```dart
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/phone_cubit.dart';
import 'package:birthday_app/features/onboarding/phone_state.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  Object? sendError;
  Object? verifyError;
  int sendCalls = 0;
  String? lastPhone;

  @override
  Future<void> sendOtp(String phoneE164) async {
    sendCalls++;
    lastPhone = phoneE164;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> verifyOtp({
    required String phoneE164,
    required String token,
  }) async {
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<int> claimProfile() async => 1;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeAuth auth;
  setUp(() => auth = _FakeAuth());

  blocTest<PhoneCubit, PhoneState>(
    'a valid Indian number is normalised to E.164 before sending',
    build: () => PhoneCubit(auth),
    act: (c) => c.submitPhone('99990 00001'),
    expect: () => [isA<PhoneSending>(), isA<PhoneCodeSent>()],
    verify: (_) => expect(auth.lastPhone, '+919999000001'),
  );

  // Nothing reaches the network for a number that cannot be a number. The
  // whole graph is keyed on the hash of this string, so a malformed one is
  // three rows for one person later.
  blocTest<PhoneCubit, PhoneState>(
    'an unparseable number fails locally without calling the repository',
    build: () => PhoneCubit(auth),
    act: (c) => c.submitPhone('abc'),
    expect: () => [isA<PhoneError>()],
    verify: (_) => expect(auth.sendCalls, 0),
  );

  blocTest<PhoneCubit, PhoneState>(
    'a send failure is an error state, not a crash',
    build: () => PhoneCubit(auth..sendError = const ServerFailure('down')),
    act: (c) => c.submitPhone('9999000001'),
    expect: () => [isA<PhoneSending>(), isA<PhoneError>()],
  );

  blocTest<PhoneCubit, PhoneState>(
    'a correct code verifies',
    build: () => PhoneCubit(auth),
    act: (c) async {
      await c.submitPhone('9999000001');
      await c.submitCode('123456');
    },
    expect: () => [
      isA<PhoneSending>(),
      isA<PhoneCodeSent>(),
      isA<PhoneVerifying>(),
      isA<PhoneVerified>(),
    ],
  );

  // The user must land back on the code screen able to try again, not on a
  // dead error screen with the phone number lost.
  blocTest<PhoneCubit, PhoneState>(
    'a wrong code returns to PhoneCodeSent carrying the error',
    build: () => PhoneCubit(auth..verifyError = const AuthFailure('bad')),
    act: (c) async {
      await c.submitPhone('9999000001');
      await c.submitCode('000000');
    },
    expect: () => [
      isA<PhoneSending>(),
      isA<PhoneCodeSent>(),
      isA<PhoneVerifying>(),
      isA<PhoneCodeSent>().having((s) => s.error, 'error', isNotNull),
    ],
  );

  blocTest<PhoneCubit, PhoneState>(
    'resend re-sends the same number',
    build: () => PhoneCubit(auth),
    act: (c) async {
      await c.submitPhone('9999000001');
      await c.resend();
    },
    verify: (_) {
      expect(auth.sendCalls, 2);
      expect(auth.lastPhone, '+919999000001');
    },
  );
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
fvm flutter test test/features/onboarding/phone_cubit_test.dart
```

Expected: FAIL — URIs do not exist.

- [ ] **Step 3: Write the state**

`lib/features/onboarding/phone_state.dart`:

```dart
sealed class PhoneState {
  const PhoneState();
}

final class PhoneIdle extends PhoneState {
  const PhoneIdle();
}

final class PhoneSending extends PhoneState {
  const PhoneSending();
}

/// The code screen. [error] is non-null after a rejected code, so the user
/// stays here with their number intact rather than being thrown out.
final class PhoneCodeSent extends PhoneState {
  const PhoneCodeSent(this.phoneE164, {this.error});
  final String phoneE164;
  final String? error;
}

final class PhoneVerifying extends PhoneState {
  const PhoneVerifying(this.phoneE164);
  final String phoneE164;
}

final class PhoneVerified extends PhoneState {
  const PhoneVerified();
}

final class PhoneError extends PhoneState {
  const PhoneError(this.message);
  final String message;
}
```

- [ ] **Step 4: Write the Cubit**

`lib/features/onboarding/phone_cubit.dart`:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../repositories/auth_repository.dart';
import 'phone_state.dart';

class PhoneCubit extends Cubit<PhoneState> {
  PhoneCubit(this._auth) : super(const PhoneIdle());
  final AuthRepository _auth;

  String? _phoneE164;

  /// Normalises to E.164 on the device before anything is sent.
  ///
  /// This matters more than it looks: people.phone_e164_hash is a bare HMAC,
  /// so three spellings of one number are three rows and three separate
  /// social graphs. docs/db.md records this as a rule the backend paid for.
  Future<void> submitPhone(String raw, {String isoCode = 'IN'}) async {
    final parsed = PhoneNumber.parse(
      raw,
      callerCountry: IsoCode.values.byName(isoCode),
    );
    if (!parsed.isValid()) {
      emit(const PhoneError(AppStrings.phoneInvalid));
      return;
    }
    final e164 = '+${parsed.countryCode}${parsed.nsn}';
    _phoneE164 = e164;

    emit(const PhoneSending());
    try {
      await _auth.sendOtp(e164);
      emit(PhoneCodeSent(e164));
    } on AppFailure catch (f) {
      emit(PhoneError(f.message));
    }
  }

  Future<void> submitCode(String token) async {
    final phone = _phoneE164;
    if (phone == null) return;

    emit(PhoneVerifying(phone));
    try {
      await _auth.verifyOtp(phoneE164: phone, token: token);
      await _auth.claimProfile();
      emit(const PhoneVerified());
    } on ServerFailure catch (f) {
      // 409: this account already claimed a different number. A distinct
      // message, because "try again" is not the remedy.
      emit(PhoneCodeSent(
        phone,
        error: f.code == '409' ? AppStrings.claimConflict : f.message,
      ));
    } on AppFailure catch (f) {
      emit(PhoneCodeSent(phone, error: f.message));
    }
  }

  Future<void> resend() async {
    final phone = _phoneE164;
    if (phone == null) return;
    try {
      await _auth.sendOtp(phone);
      emit(PhoneCodeSent(phone));
    } on AppFailure catch (f) {
      emit(PhoneCodeSent(phone, error: f.message));
    }
  }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
fvm flutter test test/features/onboarding/phone_cubit_test.dart
```

Expected: `All tests passed!` — 6 tests.

- [ ] **Step 6: Write the two screens**

`lib/features/onboarding/phone_screen.dart` — layout inline, no extracted sub-widgets, all copy from `AppStrings`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/auth_repository.dart';
import 'otp_screen.dart';
import 'phone_cubit.dart';
import 'phone_state.dart';

class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => PhoneCubit(c.read<AuthRepository>()),
      child: const _PhoneView(),
    );
  }
}

class _PhoneView extends StatefulWidget {
  const _PhoneView();

  @override
  State<_PhoneView> createState() => _PhoneViewState();
}

class _PhoneViewState extends State<_PhoneView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PhoneCubit, PhoneState>(
      listener: (context, state) {
        if (state is PhoneCodeSent) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: context.read<PhoneCubit>(),
              child: const OtpScreen(),
            ),
          ));
        }
      },
      listenWhen: (prev, next) => prev is! PhoneCodeSent && next is PhoneCodeSent,
      builder: (context, state) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    AppStrings.phoneTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppStrings.phoneSubtitle),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('phone_field'),
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: AppStrings.phoneHint,
                      border: const OutlineInputBorder(),
                      errorText: state is PhoneError ? state.message : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const Key('send_code_button'),
                    onPressed: state is PhoneSending
                        ? null
                        : () => context
                            .read<PhoneCubit>()
                            .submitPhone(_controller.text),
                    child: state is PhoneSending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.sendCode),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

`lib/features/onboarding/otp_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../router/session_cubit.dart';
import 'phone_cubit.dart';
import 'phone_state.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();

  // [auth.sms] max_frequency is 5s, so anything at or above that is safe;
  // 30s is the interval a user reads as "it is really coming".
  static const _cooldownSeconds = 30;
  int _remaining = _cooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remaining = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PhoneCubit, PhoneState>(
      listener: (context, state) {
        if (state is PhoneVerified) {
          context.read<SessionCubit>().onSignedIn();
        }
      },
      builder: (context, state) {
        final phone = switch (state) {
          PhoneCodeSent(:final phoneE164) => phoneE164,
          PhoneVerifying(:final phoneE164) => phoneE164,
          _ => '',
        };
        final error = state is PhoneCodeSent ? state.error : null;

        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.otpTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppStrings.otpSubtitleTemplate.replaceFirst('%s', phone)),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const Key('otp_field'),
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: AppStrings.otpHint,
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                    onChanged: (v) {
                      if (v.length == 6) {
                        context.read<PhoneCubit>().submitCode(v);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (state is PhoneVerifying)
                    const Center(child: CircularProgressIndicator())
                  else
                    TextButton(
                      key: const Key('resend_button'),
                      onPressed: _remaining > 0
                          ? null
                          : () {
                              context.read<PhoneCubit>().resend();
                              _startCooldown();
                            },
                      child: Text(
                        _remaining > 0
                            ? AppStrings.resendCooldownTemplate
                                .replaceFirst('%s', '$_remaining')
                            : AppStrings.resendCode,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 7: Write the widget test**

Create `test/features/onboarding/otp_screen_test.dart`:

```dart
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/features/onboarding/otp_screen.dart';
import 'package:birthday_app/features/onboarding/phone_cubit.dart';
import 'package:birthday_app/features/onboarding/phone_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhoneCubit extends MockCubit<PhoneState> implements PhoneCubit {}

void main() {
  late _MockPhoneCubit cubit;
  setUp(() => cubit = _MockPhoneCubit());

  Widget wrap() => MaterialApp(
        home: BlocProvider<PhoneCubit>.value(value: cubit, child: const OtpScreen()),
      );

  testWidgets('a six-digit entry submits automatically', (tester) async {
    whenListen(cubit, const Stream<PhoneState>.empty(),
        initialState: const PhoneCodeSent('+919999000001'));
    await tester.pumpWidget(wrap());

    await tester.enterText(find.byKey(const Key('otp_field')), '12345');
    verifyNever(() => cubit.submitCode(any()));

    await tester.enterText(find.byKey(const Key('otp_field')), '123456');
    verify(() => cubit.submitCode('123456')).called(1);
  });

  testWidgets('resend is disabled during the cooldown', (tester) async {
    whenListen(cubit, const Stream<PhoneState>.empty(),
        initialState: const PhoneCodeSent('+919999000001'));
    await tester.pumpWidget(wrap());

    final button = tester.widget<TextButton>(find.byKey(const Key('resend_button')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('30'), findsOneWidget);
  });

  // The screen the user is thrown to on a wrong code is the screen they must
  // be able to retry from, with their number still on it.
  testWidgets('a rejected code keeps the user here with the error shown',
      (tester) async {
    whenListen(cubit, const Stream<PhoneState>.empty(),
        initialState: const PhoneCodeSent('+919999000001',
            error: AppStrings.otpIncorrect));
    await tester.pumpWidget(wrap());

    expect(find.text(AppStrings.otpIncorrect), findsOneWidget);
    expect(find.textContaining('+919999000001'), findsOneWidget);
  });
}
```

Add `mocktail: ^1.0.4` to `dev_dependencies` for `verify`/`verifyNever`.

- [ ] **Step 8: Run everything, then commit**

```bash
fvm flutter pub get && fvm flutter analyze && fvm flutter test
git add lib/features/onboarding test/features/onboarding lib/core/app_strings.dart pubspec.yaml
git commit -m "feat(onboarding): phone entry and OTP verification

Normalises to E.164 on the device before any request: phone_e164_hash is
a bare HMAC, so three spellings of one number are three social graphs."
```

---

## Task 8: Profile setup screen

Spec §6.1. This is an **UPDATE**, not an INSERT — `private.handle_new_user` already created the row at signup with handle `'u' || <uuid without dashes>` and `display_name = 'New user'`. There is no insert policy on `profiles` and the app does not need one.

Completing this screen is what flips `SessionCubit` from `SessionNeedsSetup` to `SessionReady`, because `birth_month` is the completion signal.

**Files:**
- Create: `lib/features/onboarding/profile_setup_cubit.dart`, `profile_setup_state.dart`, `profile_setup_screen.dart`
- Create: `test/features/onboarding/profile_setup_cubit_test.dart`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart` (drop the stub)

**Interfaces:**
- Consumes: `AuthRepository.completeProfile(...)`, `SessionCubit.onProfileCompleted()`.
- Produces: `ProfileSetupCubit(AuthRepository)` with `submit({handle, displayName, city, birthday})`; `ProfileSetupState` = `ProfileSetupIdle | ProfileSetupSaving | ProfileSetupDone | ProfileSetupError(message, {handleTaken})`.

- [ ] **Step 1: Add the strings**

Append to `lib/core/app_strings.dart`:

```dart
  // Onboarding — profile setup
  static const setupTitle = 'Tell us about you';
  static const setupName = 'Your name';
  static const setupHandle = 'Username';
  static const setupCity = 'City';
  static const setupBirthday = 'Your birthday';
  static const setupBirthdayHelp = 'The year is optional.';
  static const setupNameRequired = 'Please enter your name.';
  static const setupHandleRequired = 'Please pick a username.';
  static const setupBirthdayRequired = 'Please pick your birthday.';
  static const setupHandleTaken = 'That username is already taken.';
  static const finish = 'Finish';
```

- [ ] **Step 2: Write the failing test**

Create `test/features/onboarding/profile_setup_cubit_test.dart`:

```dart
import 'package:birthday_app/core/app_strings.dart';
import 'package:birthday_app/core/result.dart';
import 'package:birthday_app/features/onboarding/profile_setup_cubit.dart';
import 'package:birthday_app/features/onboarding/profile_setup_state.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthRepository {
  Object? error;
  Map<String, dynamic>? saved;

  @override
  Future<void> completeProfile({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    if (error != null) throw error!;
    saved = {
      'handle': handle,
      'displayName': displayName,
      'city': city,
      'birthday': birthday,
    };
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _birthday = Birthday(month: 4, day: 15, year: 1991);

void main() {
  late _FakeAuth auth;
  setUp(() => auth = _FakeAuth());

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a complete form saves and finishes',
    build: () => ProfileSetupCubit(auth),
    act: (c) => c.submit(
      handle: 'sachin',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [isA<ProfileSetupSaving>(), isA<ProfileSetupDone>()],
    verify: (_) => expect(auth.saved!['handle'], 'sachin'),
  );

  // 23505 is reachable on the first screen a user sees, because every account
  // starts with a valid placeholder handle -- this is renaming, not naming.
  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'a taken handle is its own error, not a generic failure',
    build: () => ProfileSetupCubit(
      auth..error = const ServerFailure('duplicate key', code: '23505'),
    ),
    act: (c) => c.submit(
      handle: 'taken',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [
      isA<ProfileSetupSaving>(),
      isA<ProfileSetupError>()
          .having((s) => s.handleTaken, 'handleTaken', isTrue)
          .having((s) => s.message, 'message', AppStrings.setupHandleTaken),
    ],
  );

  blocTest<ProfileSetupCubit, ProfileSetupState>(
    'any other server error is generic and not attributed to the handle',
    build: () => ProfileSetupCubit(
      auth..error = const ServerFailure('down', code: '08006'),
    ),
    act: (c) => c.submit(
      handle: 'sachin',
      displayName: 'Sachin',
      city: 'Jaipur',
      birthday: _birthday,
    ),
    expect: () => [
      isA<ProfileSetupSaving>(),
      isA<ProfileSetupError>().having((s) => s.handleTaken, 'handleTaken', isFalse),
    ],
  );
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
fvm flutter test test/features/onboarding/profile_setup_cubit_test.dart
```

Expected: FAIL — URIs do not exist.

- [ ] **Step 4: Write the state and Cubit**

`lib/features/onboarding/profile_setup_state.dart`:

```dart
sealed class ProfileSetupState {
  const ProfileSetupState();
}

final class ProfileSetupIdle extends ProfileSetupState {
  const ProfileSetupIdle();
}

final class ProfileSetupSaving extends ProfileSetupState {
  const ProfileSetupSaving();
}

final class ProfileSetupDone extends ProfileSetupState {
  const ProfileSetupDone();
}

/// [handleTaken] decides whether the message is attached to the handle field
/// or shown as a general failure. Attributing an unrelated outage to the
/// username sends the user off renaming themselves for no reason.
final class ProfileSetupError extends ProfileSetupState {
  const ProfileSetupError(this.message, {this.handleTaken = false});
  final String message;
  final bool handleTaken;
}
```

`lib/features/onboarding/profile_setup_cubit.dart`:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_strings.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../repositories/auth_repository.dart';
import 'profile_setup_state.dart';

class ProfileSetupCubit extends Cubit<ProfileSetupState> {
  ProfileSetupCubit(this._auth) : super(const ProfileSetupIdle());
  final AuthRepository _auth;

  Future<void> submit({
    required String handle,
    required String displayName,
    required String city,
    required Birthday birthday,
  }) async {
    emit(const ProfileSetupSaving());
    try {
      await _auth.completeProfile(
        handle: handle,
        displayName: displayName,
        city: city,
        birthday: birthday,
      );
      emit(const ProfileSetupDone());
    } on ServerFailure catch (f) {
      // 23505 is the unique index on profiles.handle.
      if (f.code == '23505') {
        emit(const ProfileSetupError(
          AppStrings.setupHandleTaken,
          handleTaken: true,
        ));
      } else {
        emit(ProfileSetupError(f.message));
      }
    } on AppFailure catch (f) {
      emit(ProfileSetupError(f.message));
    }
  }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
fvm flutter test test/features/onboarding/profile_setup_cubit_test.dart
```

Expected: `All tests passed!` — 3 tests.

- [ ] **Step 6: Write the screen**

`lib/features/onboarding/profile_setup_screen.dart` — a `Form` with four fields. The birthday uses `showDatePicker` seeded to 1 Jan 2000, with a checkbox for "I would rather not say the year" that nulls `birth_year`. Layout inline. On `ProfileSetupDone`, call `context.read<SessionCubit>().onProfileCompleted()`; the router then redirects to `/timeline`.

Field keys for the widget layer: `Key('setup_name')`, `Key('setup_handle')`, `Key('setup_city')`, `Key('setup_birthday')`, `Key('setup_submit')`.

Validation is client-side and minimal — non-empty name, non-empty handle, a chosen birthday — using `AppStrings.setupNameRequired`, `setupHandleRequired`, `setupBirthdayRequired`. The handle-taken error comes from the Cubit, not from local validation, and is passed as the field's `errorText` when `state.handleTaken` is true.

- [ ] **Step 7: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test
git add lib/features/onboarding test/features/onboarding lib/core/app_strings.dart
git commit -m "feat(onboarding): profile setup

An UPDATE, not an INSERT -- the signup trigger already made the row.
Completing it is what flips the router's onboarding guard."
```

---

## Task 9: `ContactsRepository` and its contract tests

Spec §6.2. The most consequential repository in the phase: it owns E.164 normalisation, the resolve pass, and the chunked commit whose contract Task 2 pinned.

**Chunking is mandatory.** Parent carry-forward #5 measured 500 sequential awaited RPCs at ~6.2s on warm loopback, so the commit reports progress across chunks rather than blocking.

**Files:**
- Create: `lib/repositories/contacts_repository.dart`, `contacts_repository_impl.dart`
- Create: `lib/models/import_outcome.dart`
- Create: `test/repositories/contacts_repository_test.dart` (imports `test/support/contract_test_harness.dart`)

**Interfaces:**
- Consumes: `ApiClient.instance`, `ApiEndpoints.resolveContacts`, `ApiEndpoints.addCelebrations`, `Birthday`.
- Produces:
  - `DeviceContact({required String name, required String phoneE164, Birthday? birthday})`
  - `ResolvedContact({required String phone, required int personId, required String displayName, required bool hasBirthday})`
  - `ImportStatus` enum: `added, duplicate, suppressed, invalidPhone, invalidName, self, failed`
  - `ImportOutcome({required String phone, required int? personId, required ImportStatus status})`
  - `ImportSummary({required int added, required int skipped, required int failed, required int duplicates, required List<ImportOutcome> results})`
  - `ContactsRepository` with `requestPermission()`, `readDeviceContacts({String isoCode})`, `resolve(List<String> phones)`, `addCelebrations(List<DeviceContact>, {void Function(int done, int total)? onProgress})`.

- [ ] **Step 1: Write the status vocabulary model**

Create `lib/models/import_outcome.dart`:

```dart
/// The exact status vocabulary the add_celebrations Edge Function returns.
/// Task 2's Deno test pins it; this enum is the client half of that contract.
/// An unrecognised string maps to [failed] rather than throwing, so a server
/// that grows a new status degrades instead of crashing an import of 500.
enum ImportStatus {
  added,
  duplicate,
  suppressed,
  invalidPhone,
  invalidName,
  self,
  failed;

  static ImportStatus fromWire(String value) => switch (value) {
        'added' => ImportStatus.added,
        'duplicate' => ImportStatus.duplicate,
        'suppressed' => ImportStatus.suppressed,
        'invalid_phone' => ImportStatus.invalidPhone,
        'invalid_name' => ImportStatus.invalidName,
        'self' => ImportStatus.self,
        _ => ImportStatus.failed,
      };
}

class ImportOutcome {
  const ImportOutcome({
    required this.phone,
    required this.personId,
    required this.status,
  });

  final String phone;
  final int? personId;
  final ImportStatus status;

  factory ImportOutcome.fromRow(Map<String, dynamic> row) => ImportOutcome(
        phone: row['phone'] as String,
        personId: row['person_id'] as int?,
        status: ImportStatus.fromWire(row['status'] as String),
      );
}

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.skipped,
    required this.failed,
    required this.duplicates,
    required this.results,
  });

  final int added;
  final int skipped;
  final int failed;
  final int duplicates;
  final List<ImportOutcome> results;

  ImportSummary merge(ImportSummary other) => ImportSummary(
        added: added + other.added,
        skipped: skipped + other.skipped,
        failed: failed + other.failed,
        duplicates: duplicates + other.duplicates,
        results: [...results, ...other.results],
      );

  static const empty = ImportSummary(
    added: 0,
    skipped: 0,
    failed: 0,
    duplicates: 0,
    results: [],
  );
}
```

- [ ] **Step 2: Write the failing contract test**

Create `test/repositories/contacts_repository_test.dart`:

```dart
@Tags(['contract'])
library;

import 'package:birthday_app/api/api_client.dart';
import 'package:birthday_app/models/birthday.dart';
import 'package:birthday_app/models/import_outcome.dart';
import 'package:birthday_app/repositories/auth_repository.dart';
import 'package:birthday_app/repositories/auth_repository_impl.dart';
import 'package:birthday_app/repositories/contacts_repository.dart';
import 'package:birthday_app/repositories/contacts_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Requires `supabase start` and `supabase functions serve`.
void main() {
  late AuthRepository auth;
  late ContactsRepository contacts;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ApiClient.init();
    auth = AuthRepositoryImpl(ApiClient.instance);
    contacts = ContactsRepositoryImpl(ApiClient.instance);
  });

  setUp(() async {
    await auth.sendOtp('+919999000001');
    await auth.verifyOtp(phoneE164: '+919999000001', token: '123456');
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
      const DeviceContact(name: 'Me', phoneE164: '+919999000001'),
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
    final resolved = await contacts.resolve(['+919999000001', '+919999999999']);
    expect(resolved.any((r) => r.phone == '+919999000001'), isTrue);
    expect(resolved.any((r) => r.phone == '+919999999999'), isFalse);
  });

  test('a supplied birthday is stored with the person', () async {
    final summary = await contacts.addCelebrations([
      const DeviceContact(
        name: 'Has Birthday',
        phoneE164: '+919999333303',
        birthday: Birthday(month: 4, day: 15),
      ),
    ]);
    expect(summary.added, 1);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
fvm flutter test test/repositories/contacts_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: FAIL — URIs do not exist.

- [ ] **Step 4: Write the interface**

Create `lib/repositories/contacts_repository.dart`:

```dart
import '../models/birthday.dart';
import '../models/import_outcome.dart';

/// A contact as it exists on the device, already normalised to E.164.
class DeviceContact {
  const DeviceContact({
    required this.name,
    required this.phoneE164,
    this.birthday,
  });

  final String name;
  final String phoneE164;
  final Birthday? birthday;

  DeviceContact withBirthday(Birthday? b) =>
      DeviceContact(name: name, phoneE164: phoneE164, birthday: b);
}

/// A number that already belongs to a person row on the server.
/// `hasBirthday` is what drives the fill-birthdays step: only contacts
/// without one need asking about.
class ResolvedContact {
  const ResolvedContact({
    required this.phone,
    required this.personId,
    required this.displayName,
    required this.hasBirthday,
  });

  final String phone;
  final int personId;
  final String displayName;
  final bool hasBirthday;
}

abstract interface class ContactsRepository {
  /// Must be called only AFTER the prominent-disclosure screen. Play requires
  /// the disclosure to precede the OS prompt.
  Future<bool> requestPermission();

  Future<List<DeviceContact>> readDeviceContacts({String isoCode = 'IN'});

  /// Match-only. Creates nothing: a person row is minted when the user picks
  /// someone, not when they import their address book.
  Future<List<ResolvedContact>> resolve(List<String> phonesE164);

  /// Commits the picked contacts, chunked. [onProgress] fires once per chunk
  /// with (done, total).
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize,
    void Function(int done, int total)? onProgress,
  });
}
```

- [ ] **Step 5: Write the implementation**

Create `lib/repositories/contacts_repository_impl.dart`:

```dart
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../core/logger.dart';
import '../models/birthday.dart';
import '../models/import_outcome.dart';
import 'contacts_repository.dart';

class ContactsRepositoryImpl implements ContactsRepository {
  const ContactsRepositoryImpl(this._client);
  final SupabaseClient _client;

  /// Both Edge Functions cap at MAX_BATCH = 500 and answer 413 above it.
  static const _maxBatch = 500;

  @override
  Future<bool> requestPermission() => fc.FlutterContacts.requestPermission();

  @override
  Future<List<DeviceContact>> readDeviceContacts({String isoCode = 'IN'}) async {
    final raw = await fc.FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );

    final out = <DeviceContact>[];
    final seen = <String>{};
    for (final c in raw) {
      final name = c.displayName.trim();
      if (name.isEmpty) continue;

      for (final phone in c.phones) {
        final e164 = _toE164(phone.number, isoCode);
        // A number that cannot be parsed is dropped here rather than sent.
        // The server would answer invalid_phone, but a device contact with a
        // landline is not a failure worth showing the user.
        if (e164 == null || !seen.add(e164)) continue;
        out.add(DeviceContact(
          name: name,
          phoneE164: e164,
          birthday: _birthdayOf(c),
        ));
      }
    }
    return out;
  }

  static String? _toE164(String raw, String isoCode) {
    try {
      final parsed = PhoneNumber.parse(
        raw,
        callerCountry: IsoCode.values.byName(isoCode),
      );
      return parsed.isValid() ? '+${parsed.countryCode}${parsed.nsn}' : null;
    } catch (_) {
      return null;
    }
  }

  /// Device address books routinely carry a birthday with no year, which is
  /// exactly why the schema splits month/day/year instead of storing a date.
  static Birthday? _birthdayOf(fc.Contact c) {
    for (final e in c.events) {
      if (e.label != fc.EventLabel.birthday) continue;
      return Birthday(month: e.month, day: e.day, year: e.year);
    }
    return null;
  }

  @override
  Future<List<ResolvedContact>> resolve(List<String> phonesE164) async {
    final out = <ResolvedContact>[];
    for (final chunk in _chunks(phonesE164, _maxBatch)) {
      try {
        final res = await _client.functions.invoke(
          ApiEndpoints.resolveContacts,
          body: {'phones': chunk},
        );
        final matches = (res.data as Map<String, dynamic>)['matches'] as List;
        out.addAll(matches.map((m) {
          final row = m as Map<String, dynamic>;
          return ResolvedContact(
            phone: row['phone'] as String,
            personId: row['person_id'] as int,
            displayName: row['display_name'] as String,
            hasBirthday: row['has_birthday'] as bool,
          );
        }));
      } catch (e) {
        throw mapError(e);
      }
    }
    return out;
  }

  @override
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize = _maxBatch,
    void Function(int done, int total)? onProgress,
  }) async {
    var summary = ImportSummary.empty;
    var done = 0;

    for (final chunk in _chunks(contacts, chunkSize)) {
      try {
        final res = await _client.functions.invoke(
          ApiEndpoints.addCelebrations,
          body: {
            'contacts': chunk
                .map((c) => {
                      'phone': c.phoneE164,
                      'name': c.name,
                      'birth_month': c.birthday?.month,
                      'birth_day': c.birthday?.day,
                      'birth_year': c.birthday?.year,
                    })
                .toList(),
          },
        );
        final body = res.data as Map<String, dynamic>;
        summary = summary.merge(ImportSummary(
          added: body['added'] as int,
          skipped: body['skipped'] as int,
          failed: body['failed'] as int,
          duplicates: body['duplicates'] as int,
          results: (body['results'] as List)
              .map((r) => ImportOutcome.fromRow(r as Map<String, dynamic>))
              .toList(),
        ));
      } catch (e) {
        // One bad chunk must not lose the chunks that already succeeded, and
        // must not silently shorten `results` -- the summary screen zips it
        // positionally against the picked list.
        Log.error('import chunk failed', e);
        summary = summary.merge(ImportSummary(
          added: 0,
          skipped: 0,
          failed: chunk.length,
          duplicates: 0,
          results: chunk
              .map((c) => ImportOutcome(
                    phone: c.phoneE164,
                    personId: null,
                    status: ImportStatus.failed,
                  ))
              .toList(),
        ));
      }
      done += chunk.length;
      onProgress?.call(done, contacts.length);
    }
    return summary;
  }

  static Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}
```

- [ ] **Step 6: Run to verify it passes**

```bash
fvm flutter test test/repositories/contacts_repository_test.dart \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: `All tests passed!` — 6 tests.

- [ ] **Step 7: Prove the chunking assertions are load-bearing**

Change `_chunks` to `yield items;` (one chunk, ignoring size). Re-run. Expected: `progress is reported per chunk` **fails** (it sees `[7]`, not `[3, 6, 7]`). Restore.

Then change `merge` to return `other` instead of the sum. Expected: `a batch larger than one chunk still returns one result per input` **fails**. Restore.

- [ ] **Step 8: Commit**

```bash
git add lib/repositories/contacts_repository.dart lib/repositories/contacts_repository_impl.dart \
        lib/models/import_outcome.dart test/repositories/contacts_repository_test.dart
git commit -m "feat(contacts): device read, E.164 normalisation and the chunked commit

500 sequential RPCs measured ~6.2s in Phase 2a, so the commit chunks and
reports progress. A failed chunk still emits one result per input, or
the summary screen's positional zip silently shifts."
```

---

## Task 10: Contacts import screens

Spec §6.2. Four screens in one flow: disclosure → pick → fill birthdays → summary. The disclosure screen **must** precede the OS permission prompt; Play requires it and permission declarations are historically where this team's releases get blocked.

**Files:**
- Create: `lib/features/contacts_import/import_cubit.dart`, `import_state.dart`, `import_disclosure_screen.dart`, `import_pick_screen.dart`, `import_fill_birthdays_screen.dart`, `import_summary_screen.dart`
- Create: `test/features/contacts_import/import_cubit_test.dart`, `test/features/contacts_import/import_pick_screen_test.dart`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart` (drop the stub)

**Interfaces:**
- Consumes: `ContactsRepository`, `ImportSummary`, `ImportStatus`, `DeviceContact`, `ResolvedContact`.
- Produces: `ImportCubit(ContactsRepository)` with `start()`, `toggle(String phoneE164)`, `setBirthday(String phoneE164, Birthday?)`, `commit()`; `ImportState` = `ImportIdle | ImportRequestingPermission | ImportPermissionDenied | ImportLoadingContacts | ImportPicking | ImportCommitting(done,total) | ImportDone(ImportSummary) | ImportFailed(message)`.

- [ ] **Step 1: Add the strings**

Append to `lib/core/app_strings.dart`:

```dart
  // Contacts import
  static const importDisclosureTitle = 'Find people you already know';
  static const importDisclosureBody =
      'Birthday reads the names and numbers in your contacts so you can pick '
      'who you want to celebrate. Your contacts are never stored on our '
      'servers and are never shared with anyone.';
  static const importDisclosureContinue = 'Continue';
  static const importDisclosureSkip = 'Not now';
  static const importPermissionDenied =
      'Birthday needs access to your contacts to find people you know. You '
      'can turn it on in Settings.';
  static const importPickTitle = 'Who do you celebrate?';
  static const importOnApp = 'On Birthday';
  static const importNoBirthday = 'No birthday';
  static const importAddSelected = 'Add selected';
  static const importFillTitle = 'Add their birthdays';
  static const importFillBody =
      'Your address book did not have a birthday for these people. You can '
      'add them now or later.';
  static const importSummaryTitle = 'Import complete';
  static const importAddedTemplate = '%s added';
  static const importSkippedTemplate = '%s skipped';
  static const importDuplicatesTemplate = '%s already in your list';
  static const importSelfSkipped = 'We skipped your own number.';
  static const importCouldNotAddTemplate = 'Could not add %s';
  static const importDone = 'Done';
```

**A rule for this screen, not a preference:** there is no string for "suppressed" and there must never be one. `suppressed` is folded into the skipped count with no reason shown. Someone who asked to be removed must not have that fact revealed to whoever imported them.

- [ ] **Step 2: Write the failing Cubit test**

Create `test/features/contacts_import/import_cubit_test.dart`. Cover, with a fake `ContactsRepository`:

```dart
// 1. Permission denied short-circuits to ImportPermissionDenied and never
//    reads contacts.
// 2. A granted permission loads contacts and lands on ImportPicking with
//    nothing selected -- opt in, never opt out, for a screen that mints rows.
// 3. toggle() adds and removes a phone from the selection.
// 4. commit() sends ONLY the selected contacts, not the whole address book.
//    This is the "create on select" decision from the parent spec §3: a
//    person row must not be minted for a non-consenting contact.
// 5. commit() emits ImportCommitting with the progress the repository
//    reports, then ImportDone carrying the summary.
// 6. setBirthday attaches a birthday to a selected contact before commit.
```

Write each as a `blocTest`, following the shape used in Tasks 6–8. Assertion 4 is the one that matters most: build the fake with 5 device contacts, select 2, commit, and assert the fake recorded exactly 2.

- [ ] **Step 3: Run to verify it fails, then write the Cubit**

`ImportCubit` holds the loaded `List<DeviceContact>`, a `Set<String>` of selected phones, and a `Map<String, Birthday>` of birthdays filled in on the fill screen. `commit()` builds the list by filtering the loaded contacts to the selected set and applying `withBirthday`, then calls `addCelebrations(..., onProgress: ...)` emitting `ImportCommitting(done, total)`.

`start()` sequence: `emit(ImportRequestingPermission)` → `requestPermission()` → on false `emit(ImportPermissionDenied)` and return → `emit(ImportLoadingContacts)` → `readDeviceContacts()` → `resolve(phones)` to badge existing users → `emit(ImportPicking(contacts, resolved, selected: {}))`.

- [ ] **Step 4: Write the four screens**

`import_disclosure_screen.dart` — static copy, a Continue button that calls `start()`, and a Not now that pops. **No permission API is touched before Continue is pressed.**

`import_pick_screen.dart` — a `ListView` of `CheckboxListTile`, each keyed `Key('contact_${phoneE164}')`, showing the name, the number, an `importOnApp` badge when the phone is in the resolved set, and an `importNoBirthday` note when neither the device nor the server has one. A bottom `FilledButton` keyed `Key('add_selected')` reading `importAddSelected`, disabled when the selection is empty.

`import_fill_birthdays_screen.dart` — shown only for selected contacts with no birthday; each row opens a date picker with a "no year" option. Skippable.

`import_summary_screen.dart` — reads the `ImportSummary`:

```dart
// added        -> importAddedTemplate
// duplicates   -> importDuplicatesTemplate
// skipped      -> importSkippedTemplate, WITH NO REASON. `suppressed` lands
//                 here and must stay indistinguishable from any other skip.
// self         -> importSelfSkipped, its own line: importing your own number
//                 is the likeliest "failure" in a real address book and is
//                 not an error.
// invalidPhone,
// invalidName  -> importCouldNotAddTemplate, naming the contact so it is
//                 fixable.
// failed       -> importCouldNotAddTemplate WITHOUT naming the contact, and
//                 offering retry: this is a server condition, not the user's.
```

- [ ] **Step 5: Write the widget test**

Create `test/features/contacts_import/import_pick_screen_test.dart`:

```dart
// 1. Nothing is selected on first render.
// 2. The Add button is disabled with an empty selection and enabled after a tap.
// 3. A contact present in the resolved set shows the importOnApp badge and one
//    absent from it does not.
// 4. Tapping a row calls toggle() with that contact's phone.
```

- [ ] **Step 6: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test
git add lib/features/contacts_import test/features/contacts_import lib/core/app_strings.dart
git commit -m "feat(import): disclosure, pick, fill birthdays and summary

Create-on-select: only picked contacts are sent, so importing an address
book mints no rows for non-consenting people. A suppressed number is
reported as a bare skip -- naming it would reveal the opt-out."
```

---

## Task 11: `GraphRepository` and its contract tests

Spec §6.3. Reads the timeline and owns the three row actions.

**Files:**
- Create: `lib/repositories/graph_repository.dart`, `graph_repository_impl.dart`
- Create: `test/repositories/graph_repository_test.dart` (imports `test/support/contract_test_harness.dart`)

**Interfaces:**
- Consumes: `ApiClient.instance`, `ApiParams`, `ApiEndpoints.rpcUpdatePersonBirthday`, `Celebration`, `Birthday`.
- Produces: `GraphRepository` with `celebrations() → Future<List<Celebration>>`, `updateBirthday(int personId, Birthday)`, `updateNickname(int celebrationId, String?)`, `stopCelebrating(int celebrationId)`.

- [ ] **Step 1: Write the failing contract test**

Create `test/repositories/graph_repository_test.dart`, signing in as `+919999000001` in `setUp` exactly as Task 9 does:

```dart
// 1. celebrations() returns the edges this user owns, with the person embedded.
// 2. updateBirthday sets a birthday on an unclaimed person the user celebrates,
//    and celebrations() reflects it.
// 3. updateBirthday on a person the user does NOT celebrate throws
//    ServerFailure with code '45002'. Build this by adding a person as a
//    second user, then asserting from the first.
// 4. updateBirthday on a CLAIMED person throws ServerFailure with code
//    '45003'. This is the assertion protecting a real user's date of birth.
// 5. An impossible date (April 31) throws ServerFailure with code '23514' --
//    security definer did not become a way around the check constraints.
// 6. stopCelebrating removes the edge and celebrations() no longer returns it.
// 7. updateNickname changes the label; celebrations() returns the nickname in
//    preference to the person's display name.
```

The select for `celebrations()`:

```dart
await _client
    .from(ApiParams.celebrations)
    .select('id, nickname, ${ApiParams.people}(id, display_name, profile_id, '
        'birth_month, birth_day, birth_year)')
    .eq(ApiParams.celebratorProfileId, userId);
```

- [ ] **Step 2: Run to verify it fails, then write interface and implementation**

Each write wraps its call in `try/catch` and rethrows `mapError(e)`, so `45002`, `45003` and `23514` reach the Cubit as `ServerFailure.code`. Nothing here swallows a SQLSTATE — the timeline branches on all three.

`stopCelebrating` is a plain delete; `celebrations_delete_own` survived Phase 2a's write lockdown, so no RPC is needed:

```dart
await _client.from(ApiParams.celebrations).delete().eq(ApiParams.id, celebrationId);
```

`updateNickname` is the only remaining `authenticated` write on `celebrations` (`grant update (nickname)`). Per parent carry-forward #7 the guard trigger rejects it if the target has since blocked you, so it too must surface its error rather than failing silently.

- [ ] **Step 3: Prove the two guard assertions are load-bearing**

Comment out the `profile_id is not null` check in `20260829000001_update_person_birthday.sql`, run `supabase db reset`, and confirm assertion 4 **fails**. Restore, then do the same for the edge check and assertion 3.

This duplicates Task 1's Step 5 deliberately: Task 1 proved the guards from SQL, this proves the client actually surfaces them rather than swallowing the SQLSTATE.

- [ ] **Step 4: Commit**

```bash
git add lib/repositories/graph_repository.dart lib/repositories/graph_repository_impl.dart \
        test/repositories/graph_repository_test.dart
git commit -m "feat(graph): timeline reads and the three row actions

45002, 45003 and 23514 all reach the Cubit as ServerFailure.code -- the
timeline branches on each, so none may be swallowed."
```

---

## Task 12: The Celebrating timeline

Spec §6.3. The payoff screen: the first thing that makes the app useful to someone with one contact.

**Files:**
- Create: `lib/features/timeline/timeline_cubit.dart`, `timeline_state.dart`, `timeline_screen.dart`
- Create: `test/features/timeline/timeline_cubit_test.dart`, `test/features/timeline/timeline_screen_test.dart`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart` (drop the stub)

**Interfaces:**
- Consumes: `GraphRepository`, `Birthday.groupFrom`, `TimelineGroup`.
- Produces: `TimelineCubit(GraphRepository, {DateTime Function() now})` with `load()`, `editBirthday(int personId, Birthday)`, `editNickname(int celebrationId, String?)`, `stopCelebrating(int celebrationId)`; `TimelineState` = `TimelineLoading | TimelineLoaded(Map<TimelineGroup, List<Celebration>>) | TimelineEmpty | TimelineError(message)`.

The injected `now` is not optional — a grouping test that depends on the real clock passes in April and fails in October.

- [ ] **Step 1: Add the strings**

```dart
  // Timeline
  static const timelineTitle = 'Celebrating';
  static const timelineToday = 'Today';
  static const timelineThisWeek = 'This week';
  static const timelineThisMonth = 'This month';
  static const timelineLater = 'Later';
  static const timelineEmptyTitle = 'Nobody yet';
  static const timelineEmptyBody =
      'Import your contacts to start celebrating the people you know.';
  static const timelineImportCta = 'Import contacts';
  static const timelineEditBirthday = 'Edit birthday';
  static const timelineEditNickname = 'Edit nickname';
  static const timelineStopCelebrating = 'Stop celebrating';
  static const timelineNoBirthdayYet = 'No birthday yet';
  static const timelineBirthdayNotEditable =
      'They are on Birthday, so only they can change their birthday.';
  static const timelineNicknameBlocked =
      'You can no longer edit this person.';
```

- [ ] **Step 2: Write the failing Cubit test**

Create `test/features/timeline/timeline_cubit_test.dart` with a fake `GraphRepository` and a fixed `now` of `DateTime(2026, 4, 15)`:

```dart
// 1. Four celebrations with birthdays on Apr 15, Apr 18, May 1 and Sep 1 group
//    into today / thisWeek / thisMonth / later respectively.
// 2. A celebration whose person has NO birthday is still returned, in its own
//    bucket -- the parent spec skips these for reminders, but hiding them here
//    would make them unfixable, and fixing them is what the edit action is for.
// 3. An empty edge list emits TimelineEmpty, not an empty TimelineLoaded.
// 4. Within a group, rows are ordered by next occurrence ascending.
// 5. editBirthday on a claimed person surfaces 45003 as
//    AppStrings.timelineBirthdayNotEditable rather than a generic error.
// 6. editNickname surfacing the guard-trigger rejection shows
//    AppStrings.timelineNicknameBlocked.
// 7. stopCelebrating removes the row from state without a full reload.
```

Assertion 1 is the whole screen. Assertion 5 is the one that carries Task 1's work all the way to the user.

- [ ] **Step 3: Write the Cubit**

Grouping is `birthday.groupFrom(_now())`; ordering within a group is by `nextOccurrence`. `editBirthday` catches `ServerFailure` and maps `45003` → `timelineBirthdayNotEditable`, `45002` → `somethingWentWrong` (it should be unreachable from this screen — the user is looking at their own edges — so it is a bug signal, not a user message).

- [ ] **Step 4: Write the screen**

A `CustomScrollView` with one `SliverList` per non-empty group under a `SliverPersistentHeader` using `AppTextStyles.sectionHeader`. Each row is a `ListTile` keyed `Key('celebration_${id}')` with a `PopupMenuButton` carrying the three actions. Layout inline; no extracted row widget unless the build method genuinely becomes unreadable.

Empty state renders `timelineEmptyTitle` / `timelineEmptyBody` and a button routing to `/import`.

- [ ] **Step 5: Write the widget test**

`test/features/timeline/timeline_screen_test.dart`:

```dart
// 1. Group headers render only for non-empty groups.
// 2. A person with no birthday shows timelineNoBirthdayYet.
// 3. The empty state shows the import CTA.
// 4. The overflow menu offers exactly the three actions.
```

- [ ] **Step 6: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test
git add lib/features/timeline test/features/timeline lib/core/app_strings.dart
git commit -m "feat(timeline): the Celebrating list, grouped by how soon

Grouping runs off an injected clock -- a grouping test on the real clock
passes in April and fails in October."
```

---

## Task 13: Settings

Spec §6.4. Three actions, two of which are irreversible.

**Files:**
- Create: `lib/repositories/settings_repository.dart`, `settings_repository_impl.dart`
- Create: `lib/features/settings/settings_cubit.dart`, `settings_state.dart`, `settings_screen.dart`
- Create: `test/repositories/settings_repository_test.dart` (imports `test/support/contract_test_harness.dart`), `test/features/settings/settings_cubit_test.dart`
- Modify: `lib/core/app_strings.dart`, `lib/router/app_router.dart` (drop the stub)

**Interfaces:**
- Consumes: `ApiClient.instance`, `AuthRepository.signOut()`, `AuthRepository.deleteAccount()`, `SessionCubit.signOut()`.
- Produces: `SettingsRepository` with `setRemindersEnabled(bool)`, `deleteThisDeviceToken()`; `SettingsCubit(SettingsRepository, AuthRepository)` with `load()`, `toggleReminders(bool)`, `signOut()`, `deleteAccount()`.

- [ ] **Step 1: Add the strings**

```dart
  // Settings
  static const settingsTitle = 'Settings';
  static const settingsReminders = 'Birthday reminders';
  static const settingsRemindersBody =
      'Get a notification before each birthday you celebrate.';
  static const settingsSignOut = 'Sign out';
  static const settingsDeleteAccount = 'Delete account';
  static const settingsDeleteTitle = 'Delete your account?';
  static const settingsDeleteBody =
      'Your profile, the people you celebrate, and your wishes are deleted. '
      'People who celebrate you will keep a "Deleted user" in their list. '
      'This cannot be undone.';
  static const settingsDeleteConfirm = 'Delete everything';
```

The delete copy states what parent carry-forward #8 makes true: deletion strands a scrubbed person row, so bystanders' edges survive as "Deleted user". Saying so is the difference between a considered trade-off and a surprise.

- [ ] **Step 2: Write the failing contract test**

`test/repositories/settings_repository_test.dart`:

```dart
// 1. setRemindersEnabled(false) persists and loadProfile() reflects it.
// 2. setRemindersEnabled(true) restores it.
// 3. deleteThisDeviceToken() on a user with no registered token is a no-op,
//    not an error. Push is stubbed in Phase 2b, so this is the ONLY path this
//    code takes until 2c -- if it throws, every sign-out breaks.
```

- [ ] **Step 3: Write the failing Cubit test**

`test/features/settings/settings_cubit_test.dart`:

```dart
// 1. toggleReminders(false) emits saving then the new value.
// 2. A failed toggle reverts the switch rather than leaving the UI showing a
//    value the server did not accept.
// 3. signOut() deletes the device token BEFORE clearing the session. Assert
//    the call order with a fake that records it: a signed-out device that
//    keeps its token keeps receiving someone else's reminders, and after the
//    session is gone the row can no longer be deleted by this client.
// 4. deleteAccount() calls the Edge Function and then signs out.
```

Assertion 3 is the one worth writing carefully. It is the failure the parent spec §6 names explicitly, and ordering is the whole of it.

- [ ] **Step 4: Write the repository, Cubit and screen**

`deleteThisDeviceToken()` deletes from `device_tokens` where the token matches this device's; with push stubbed there is no token, so it filters on nothing and returns. Implement it as a guarded no-op that is ready for Phase 2c rather than a stub that throws:

```dart
@override
Future<void> deleteThisDeviceToken() async {
  final token = _currentDeviceToken;   // null until Phase 2c registers one
  if (token == null) return;
  try {
    await _client.from(ApiParams.deviceTokens).delete().eq('token', token);
  } catch (e) {
    throw mapError(e);
  }
}
```

The screen is a `ListView` with a `SwitchListTile` keyed `Key('reminders_switch')`, a sign-out `ListTile`, and a delete `ListTile` in the error colour that opens an `AlertDialog` carrying `settingsDeleteBody` and requiring the explicit `settingsDeleteConfirm`.

- [ ] **Step 5: Verify and commit**

```bash
fvm flutter analyze && fvm flutter test
git add lib/features/settings lib/repositories/settings_repository.dart \
        lib/repositories/settings_repository_impl.dart test/features/settings \
        test/repositories/settings_repository_test.dart lib/core/app_strings.dart
git commit -m "feat(settings): reminders toggle, sign out and account deletion

Sign out deletes the device token before clearing the session -- after
the session is gone the row is unreachable, and a signed-out device
holding a token keeps receiving someone else's reminders."
```

---

## Task 14: Phase close

- [ ] **Step 1: Full cold verification**

```bash
cd ~/Desktop/Projects/birthday_app
supabase db reset && supabase test db
supabase functions serve &
./supabase/functions/test.sh
fvm flutter analyze
fvm flutter test
fvm flutter test test/repositories \
  --dart-define=SUPABASE_ANON_KEY=$(supabase status -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["ANON_KEY"])')
```

Expected: pgTAP **27 files** green from cold; Deno tests green; `No issues found.`; all Flutter tests green.

- [ ] **Step 2: Re-verify the config guard**

```bash
grep -A1 'enable_confirmations' supabase/config.toml
```

Expected: the `[auth.sms]` occurrence still reads `enable_confirmations = true`. It is guarded by nothing and `supabase init` or a CLI upgrade rewrites this file. It is the fix for total account takeover.

- [ ] **Step 3: Manual run-through on a simulator**

Sign in with `+919999000001` / `123456` → complete setup → import → timeline. Confirm the disclosure screen appears **before** the OS contacts prompt.

- [ ] **Step 4: Write the execution ledger**

Record rulings, defects found, and anything carried into Phase 2c at
`docs/superpowers/execution/2026-08-29-m1-phase2b-ledger.md`, and **commit it**. M0's ledger lived in git-ignored scratch inside a worktree and was nearly destroyed with it.

- [ ] **Step 5: Merge**

This phase runs on a branch in the main checkout, not a worktree, so this session can merge it. Fast-forward `main` and confirm `0 0`.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §4.1 birthday-edit RPC | 1 |
| §4.2 add_celebrations Deno test | 2 |
| §5 architecture, `api/`, `core/` | 3 |
| §5 models | 4 |
| §6.1 onboarding | 5, 6, 7, 8 |
| §6.2 contacts import | 9, 10 |
| §6.3 timeline | 11, 12 |
| §6.4 settings | 13 |
| §7 testing matrix | every task; closed out in 14 |
| §8 build order | task order |
| §9 risks | 14 Step 2 (the config guard); the rest are documented, not actionable in 2b |

**Known gaps, deliberate**

- Tasks 10, 11, 12 and 13 specify tests as enumerated behaviours with the reasoning attached, rather than as full source. This is the one place this plan departs from "no placeholders": the shapes are established in Tasks 4–9 and repeating three hundred lines of `blocTest` scaffolding would obscure which assertions carry weight. **The enumerated assertions are mandatory, not suggestions.**
- No end-to-end test. It requires the wish wall and profile, which are Phase 3.

**Type consistency checked:** `Birthday`, `Person`, `Celebration`, `Profile`, `ImportStatus`, `ImportOutcome`, `ImportSummary`, `DeviceContact`, `ResolvedContact`, `AppFailure` and its four subtypes, and the four repository interfaces are each defined once and referenced with the same names throughout. `ApiParams` is the single source for column names.
