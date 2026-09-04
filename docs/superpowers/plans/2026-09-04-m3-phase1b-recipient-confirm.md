# M3 Phase 1b — Recipient Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A recipient opens a token link, gives a delivery address, and the gift is confirmed — served as plain HTML by an Edge Function, with no Flutter web target.

**Architecture:** One new Edge Function (`confirm`) serving server-rendered HTML for `GET` and handling a urlencoded `POST`, calling a new `service_role`-only `public.rpc_confirm_gift` wrapper over M0's existing `private.confirm_gift`. Plus two SQL changes closing debts: the `slot_date = occasion_date` constraint moves into `private.create_gift`, and `gifts_select_participants` loses its recipient branch.

**Tech Stack:** Deno (Edge Functions, `jsr:@supabase/supabase-js@2`, `jsr:@std/assert@1`, `jsr:@db/postgres@0.19.5`), Postgres 17 + pgTAP, Supabase CLI 2.78.1, FVM Flutter 3.35.2 / Dart 3.9 (contract tests only).

**Spec:** `docs/superpowers/specs/2026-09-04-m3-phase1b-recipient-confirm-design.md`

## Global Constraints

- **`[auth.sms] enable_confirmations = true`** must remain at `supabase/config.toml:252`. It guards a reproduced total-account-takeover bug covered by no test. **Any task touching `config.toml` must run `grep -n enable_confirmations supabase/config.toml` and paste the output.**
- **Do not run the app, launch a simulator, or use any browser-automation tool.** Verification is `supabase test db`, `./supabase/functions/test.sh`, `fvm flutter analyze`, `fvm flutter test`.
- **Do not add new packages** to `pubspec.yaml`. Deno imports use `jsr:` specifiers already present in `add_celebrations/index.test.ts`.
- **No Flutter web target.** No `web/` directory, no `flutter build web`. (Spec §2.)
- **`private.confirm_gift` is not to be modified.** It is M0 code with existing pgTAP coverage; this phase wraps it.
- **Every new assertion must be watched to FAIL** with its implementation reverted, then restored byte-identically. Paste the transcript. If a revert fails for a different reason than the assertion targets, say so plainly rather than counting it as proof. Phase 1a caught thirteen tests that passed against the exact bug they were written to catch.
- **`GiftRepository` method signatures are frozen.** Task 4 of Phase 1a is closed and reviewed.
- Copy for the HTML pages lives inline in `confirm/index.ts` (it is not a Flutter surface, so `AppStrings` does not apply), but each string appears **once**, as a named `const`.
- Deno tests talk **HTTP to the served function**, never importing the handler — the contract is the HTTP one. Follow `supabase/functions/add_celebrations/index.test.ts`.
- **One phone number per test file.** `[auth.sms.test_otp]` only grants `123456` to a fixed pool; `flutter test` runs files concurrently and GoTrue's rate limit is cross-process.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260904000001_rpc_confirm_gift.sql` | Create + scope the `service_role`-only wrapper. Nothing else. |
| `supabase/migrations/20260904000002_create_gift_occasion_date.sql` | Add the `slot_date = p_occasion_date` check to `private.create_gift`. |
| `supabase/migrations/20260904000003_gifts_select_sender_only.sql` | Drop the recipient branch from `gifts_select_participants`. |
| `supabase/functions/confirm/index.ts` | The handler: routes `GET`/`POST`, renders every page, owns all copy. |
| `supabase/functions/confirm/deno.json` | Matches the five siblings. |
| `supabase/functions/confirm/index.test.ts` | Every HTTP outcome, plus the "other five still refuse" guard. |
| `supabase/config.toml` | `[functions.confirm] verify_jwt = false` — the only edit. |
| `supabase/tests/database/30_rpc_confirm_gift.test.sql` | Wrapper privileges; the R3 set unchanged. |
| `supabase/tests/database/31_create_gift_occasion_date.test.sql` | The date constraint, raised and reverted. |
| `supabase/tests/database/07_gifts.test.sql:86-92` | **Invert** the M0 recipient assertion (Task 6). |
| `test/repositories/gift_repository_test.dart` | Re-date four `createDraft` fixtures (Task 5). |
| `docs/superpowers/execution/2026-09-XX-m3-phase1b-ledger.md` | Phase close (Task 7). |

**Task order matters.** Task 5 changes `private.create_gift`, which every confirm fixture depends on for setup; doing it before the endpoint tasks would force those fixtures to be written twice. Task 6 changes RLS, which nothing in Tasks 1–5 reads as a recipient.

---

### Task 1: `rpc_confirm_gift`, the service_role-only wrapper

**Files:**
- Create: `supabase/migrations/20260904000001_rpc_confirm_gift.sql`
- Create: `supabase/tests/database/30_rpc_confirm_gift.test.sql`

**Interfaces:**
- Consumes: `private.confirm_gift(uuid, text, text, text, text, text)` returning `public.gifts` (`supabase/migrations/20260822000008_gift_lifecycle.sql:125`), revoked from `public`/`anon`/`authenticated` at `:247-248`.
- Produces: `public.rpc_confirm_gift(p_confirm_token uuid, p_line1 text, p_line2 text, p_city text, p_pincode text, p_label text default 'Home')` returning `public.gifts`. Executable by `service_role` **only**. Task 4 calls it via `admin.rpc("rpc_confirm_gift", {...})`.

- [ ] **Step 1: Confirm service_role genuinely cannot reach `private.confirm_gift` today**

This is the premise of the whole task. Do not assume it.

```bash
supabase db reset >/dev/null 2>&1
supabase test db >/dev/null 2>&1   # ensure the stack is warm
```

Then, using the DB URL from `supabase status -o json` (key `DB_URL`):

```sql
select has_function_privilege(
  'service_role',
  'private.confirm_gift(uuid,text,text,text,text,text)',
  'EXECUTE') as service_role_can_execute;
```

Expected: `f`. Paste the result. **If it returns `t`, stop and report** — the wrapper's justification is wrong and the task needs re-scoping, not a workaround.

- [ ] **Step 2: Write the failing pgTAP test**

Create `supabase/tests/database/30_rpc_confirm_gift.test.sql`:

```sql
begin;
select plan(4);

-- 1-3: the wrapper is reachable by service_role and by nobody else. This is the
-- whole security posture of the confirm endpoint: the token is the capability,
-- and the ONLY thing that may turn a token into an address write is the Edge
-- Function running as service_role.
select ok(
  has_function_privilege('service_role',
    'public.rpc_confirm_gift(uuid,text,text,text,text,text)', 'EXECUTE'),
  'service_role can execute rpc_confirm_gift'
);
select ok(
  not has_function_privilege('anon',
    'public.rpc_confirm_gift(uuid,text,text,text,text,text)', 'EXECUTE'),
  'anon CANNOT execute rpc_confirm_gift'
);
select ok(
  not has_function_privilege('authenticated',
    'public.rpc_confirm_gift(uuid,text,text,text,text,text)', 'EXECUTE'),
  'authenticated CANNOT execute rpc_confirm_gift'
);

-- 4: search_path is pinned. A security definer function without this is the
-- classic privilege-escalation shape: a caller-controlled search_path can
-- resolve an unqualified name to their own object.
select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rpc_confirm_gift'),
  '{search_path=""}',
  'rpc_confirm_gift pins an empty search_path'
);

select * from finish();
rollback;
```

- [ ] **Step 3: Run it and watch all four fail**

```bash
supabase test db 2>&1 | tail -20
```

Expected: `30_rpc_confirm_gift.test.sql` fails — assertions 1 and 4 because the function does not exist, 2 and 3 passing vacuously for the same reason. **Note that in the report:** assertions 2 and 3 pass against a nonexistent function, so they are not yet evidence. Step 6 is what makes them real.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20260904000001_rpc_confirm_gift.sql`:

```sql
-- The confirm endpoint's only way into the gift lifecycle (spec §4.2).
--
-- private.confirm_gift is revoked from public/anon/authenticated
-- (20260822000008_gift_lifecycle.sql:247-248), and revoking from PUBLIC strips
-- the default EXECUTE grant, so service_role has no privilege on it either --
-- verified before writing this migration, not assumed. This wrapper is the
-- grant boundary.
--
-- service_role ONLY, exactly like public.rpc_delete_own_draft_gifts
-- (20260901000001). It must never be anon-callable: anon reaching this would
-- let anyone who guessed a 122-bit token write an address directly, bypassing
-- the endpoint's own validation and its neutral-404 folding (spec §4.3).
--
-- Deliberately NOT added to the R3 allowlist in 11_rls_coverage.test.sql: R3
-- asserts the exact set of public functions executable by `authenticated`, so
-- this function's ABSENCE from that unchanged string is the proof the revoke
-- landed (spec §4.2).
create or replace function public.rpc_confirm_gift(
  p_confirm_token uuid,
  p_line1 text,
  p_line2 text,
  p_city text,
  p_pincode text,
  p_label text default 'Home'
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
begin
  return private.confirm_gift(
    p_confirm_token, p_line1, p_line2, p_city, p_pincode, p_label);
end;
$$;

revoke execute on function
  public.rpc_confirm_gift(uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function
  public.rpc_confirm_gift(uuid, text, text, text, text, text)
  to service_role;
```

- [ ] **Step 5: Run and verify green**

```bash
supabase db reset && supabase test db 2>&1 | tail -6
```

Expected: `Files=31`, all pass. The R3 assertion in `11_rls_coverage.test.sql` must **still pass with its expected string unchanged** — if R3 fails, the revoke did not land and `rpc_confirm_gift` is client-callable.

- [ ] **Step 6: Prove assertions 2 and 3 can fail**

Temporarily append to the migration:

```sql
grant execute on function
  public.rpc_confirm_gift(uuid, text, text, text, text, text) to authenticated;
```

Run `supabase db reset && supabase test db`. Expected: assertion 3 fails, **and R3 in `11_rls_coverage.test.sql` also fails** with `rpc_confirm_gift` appearing in the actual set. Two independent tests catching one mistake is the design working. Paste both failures, then remove the line and re-verify green with `md5` before/after.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260904000001_rpc_confirm_gift.sql \
        supabase/tests/database/30_rpc_confirm_gift.test.sql
git commit -m "feat(db): the service_role-only confirm wrapper

private.confirm_gift is revoked from PUBLIC, which strips service_role's
default grant too, so the Edge Function needs this wrapper to reach it.
Absent from the R3 allowlist on purpose: that unchanged string is the
proof the revoke landed."
```

---

### Task 2: `verify_jwt = false` for `confirm`, and proof the other five still refuse

**Files:**
- Modify: `supabase/config.toml` (add one `[functions.confirm]` block)
- Create: `supabase/functions/confirm/deno.json`
- Create: `supabase/functions/confirm/index.ts` (a stub only — Task 3 fills it)

**Interfaces:**
- Produces: a served function at `GET|POST /functions/v1/confirm` returning `501` from the stub, so Task 3 has a target to make real. `[functions.confirm] verify_jwt = false` in `config.toml`.

**Read this before starting.** This is the highest-risk change in the phase (spec §9 risk 5) and **no local test can verify it**, for a reason you must understand rather than work around: `./supabase/functions/test.sh` runs against `supabase functions serve --no-verify-jwt`, which bypasses the gateway entirely. So the local suite behaves identically whether `config.toml` is right or wrong. What the tests *can* prove is that the other five functions have their own handler-level `Authorization` guards, so the gateway is not their only protection. That is defence in depth, and it is what Step 4 asserts. **Do not claim the config change itself is test-covered.**

- [ ] **Step 1: Record the guard before touching the file**

```bash
grep -n "enable_confirmations" supabase/config.toml
md5 -q supabase/config.toml
```

Paste both. Line 252 must read `enable_confirmations = true`.

- [ ] **Step 2: Add the block**

Append to `supabase/config.toml`:

```toml
# The confirm endpoint is unauthenticated BY DESIGN (spec §4.5): the gift's
# confirm_token is the capability, and the recipient has no Supabase session --
# they are not a user of this app. With the platform default verify_jwt = true,
# Kong answers before the handler is reached and returns its own
# {"msg": "Error: ..."} body, so the endpoint could never work deployed.
#
# This is the project's FIRST [functions] block. Every other function is
# absent from this section deliberately and keeps verify_jwt = true.
# 30_... and confirm/index.test.ts assert the other five still refuse an
# unauthenticated caller at the HANDLER level, so this block cannot silently
# widen them.
[functions.confirm]
verify_jwt = false
```

- [ ] **Step 3: Verify the guard survived and only the intended lines changed**

```bash
grep -n "enable_confirmations" supabase/config.toml
git diff --stat supabase/config.toml
git diff supabase/config.toml
```

Expected: line 252 still `enable_confirmations = true`; the diff shows **only** the appended block. If `grep` shows anything else moved, stop and report — a CLI rewrite of this file is a known hazard.

- [ ] **Step 4: Write the "other five still refuse" test**

Create `supabase/functions/confirm/index.test.ts` with this as its first test (Task 3 appends the rest):

```ts
// Integration test. Requires the local stack:
//   supabase start
//   supabase functions serve --no-verify-jwt
//
// Run with:
//   deno test --allow-net --allow-env supabase/functions/confirm/index.test.ts
//
// NOTE ON WHAT THIS FILE CAN AND CANNOT PROVE: the harness serves with
// --no-verify-jwt, so the gateway is bypassed and config.toml's
// [functions.confirm] verify_jwt = false is NOT exercised here. What the guard
// test below proves is that the five pre-existing functions each refuse an
// unauthenticated caller in their OWN handler, so adding this project's first
// [functions] block cannot have silently widened them. The config value itself
// is verifiable only by deployment or by reading the file.
import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";

const URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const FN = `${URL}/functions/v1/confirm`;

const GUARDED = [
  "claim_profile",
  "delete_account",
  "drain_reminders",
  "resolve_contacts",
  "add_celebrations",
];

Deno.test("the five pre-existing functions still refuse an unauthenticated caller", async () => {
  for (const name of GUARDED) {
    const res = await fetch(`${URL}/functions/v1/${name}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    const body = await res.text();
    assertEquals(
      res.status,
      401,
      `${name} must reject an unauthenticated POST at the handler, got ${res.status}: ${body}`,
    );
  }
});
```

- [ ] **Step 5: Add the stub function so `confirm` is served**

Create `supabase/functions/confirm/deno.json` copying a sibling verbatim:

```bash
cp supabase/functions/claim_profile/deno.json supabase/functions/confirm/deno.json
cat supabase/functions/confirm/deno.json
```

Create `supabase/functions/confirm/index.ts`:

```ts
// Stub. Task 3 implements GET, Task 4 implements POST.
Deno.serve((): Response =>
  new Response("not implemented", { status: 501 })
);
```

- [ ] **Step 6: Run the guard test and verify it passes**

Restart the function server so it picks up the new function, then:

```bash
./supabase/functions/test.sh 2>&1 | tail -12
```

Expected: 7 passed (the 6 existing + this one), 0 failed.

- [ ] **Step 7: Prove the guard test can fail**

Temporarily add a sixth entry `"confirm"` to `GUARDED` — the stub returns `501`, not `401`, so the assertion must fail naming `confirm`. This proves the loop actually inspects each status rather than passing on an empty or short-circuited list. Paste the failure, then remove the entry and re-verify green.

- [ ] **Step 8: Commit**

```bash
git add supabase/config.toml supabase/functions/confirm/
git commit -m "feat(config): verify_jwt = false for the confirm endpoint

carry-forward #3 since M1 Phase 2a, non-deferrable now: the confirm
endpoint is unauthenticated by design, and under the default the gateway
answers before the handler is reached.

The project's first [functions] block. No local test can verify the
config value -- the Deno harness serves with --no-verify-jwt and bypasses
the gateway -- so the accompanying test proves instead that the five
pre-existing functions each refuse an unauthenticated caller in their own
handler, and cannot have been silently widened."
```

---

### Task 3: `GET /confirm` — the form, and the neutral 404

**Files:**
- Modify: `supabase/functions/confirm/index.ts` (replace the stub)
- Modify: `supabase/functions/confirm/index.test.ts` (append)

**Interfaces:**
- Consumes: `public.gifts` columns `id, sender_profile_id, product_id, occasion_date, message, status, confirm_token, confirm_token_used_at`; `profiles.display_name` (`20260822000003_profiles.sql:4`, `not null`); `products.name`.
- Produces: `GET /functions/v1/confirm?token=<uuid>` → `200` HTML form, or `200` "already confirmed", or `404` neutral page. Exported copy constants `COPY.formHeading`, `COPY.alreadyConfirmed`, `COPY.invalidLink` used by Task 4's result pages too.

- [ ] **Step 1: Write the failing tests**

Append to `supabase/functions/confirm/index.test.ts`. Add these imports at the top of the file: `import { createClient } from "jsr:@supabase/supabase-js@2";`.

```ts
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// A gift in awaiting_confirm, built with service_role. The status machine's
// only transition INTO awaiting_confirm is from 'paid'
// (20260822000007_gifts.sql:79), and payments are M3 Phase 2, so there is no
// client-reachable way to build this fixture -- the spec sanctions service_role
// here for exactly that reason.
// deno-lint-ignore no-explicit-any
async function awaitingConfirmGift(admin: any): Promise<{
  token: string;
  senderName: string;
  productName: string;
  city: string;
}> {
  const { data, error } = await admin.rpc("tests_seed_awaiting_confirm_gift");
  if (error) throw new Error(`fixture failed: ${error.message}`);
  return data;
}

Deno.test("GET with a valid token renders the address form, and no price", async () => {
  const admin = createClient(URL, SERVICE);
  const gift = await awaitingConfirmGift(admin);

  const res = await fetch(`${FN}?token=${gift.token}`);
  const html = await res.text();

  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type")?.includes("text/html"), true);
  // The five inputs the recipient must fill.
  for (const field of ["line1", "line2", "city", "pincode", "label"]) {
    assertEquals(
      html.includes(`name="${field}"`),
      true,
      `form is missing input name="${field}"`,
    );
  }
  // What it may show.
  assertEquals(html.includes(gift.senderName), true, "sender name missing");
  assertEquals(html.includes(gift.productName), true, "product name missing");
  // What it must NEVER show (spec §4.6). The seeded amount is 84900 paise.
  assertEquals(html.includes("84900"), false, "the page leaked amount_minor");
  assertEquals(html.includes("849"), false, "the page leaked a rupee price");
});

Deno.test("GET with an unknown token and GET for a non-awaiting gift are byte-identical", async () => {
  const admin = createClient(URL, SERVICE);

  // A real, well-formed token whose gift is still 'draft' -- confirm_token is
  // populated at CREATION (default gen_random_uuid()), not at payment, so this
  // token exists long before the gift is confirmable (spec §4.3).
  const { data: draft, error } = await admin.rpc("tests_seed_draft_gift");
  if (error) throw new Error(`fixture failed: ${error.message}`);

  const unknown = await fetch(`${FN}?token=00000000-0000-4000-8000-000000000000`);
  const wrongStatus = await fetch(`${FN}?token=${draft.token}`);

  const unknownBody = await unknown.text();
  const wrongBody = await wrongStatus.text();

  assertEquals(unknown.status, 404);
  assertEquals(wrongStatus.status, 404);
  // The point of the test: separating these would confirm to a prober that a
  // token is real but its gift unpaid -- an oracle no legitimate recipient
  // needs, because links are only sent after payment (spec §4.3).
  assertEquals(
    wrongBody,
    unknownBody,
    "a real-but-unconfirmable token must be indistinguishable from an unknown one",
  );
});

Deno.test("GET with a malformed or missing token is the same neutral 404", async () => {
  const missing = await fetch(FN);
  const malformed = await fetch(`${FN}?token=not-a-uuid`);
  assertEquals(missing.status, 404);
  assertEquals(malformed.status, 404);
  assertEquals(await malformed.text(), await missing.text());
});
```

- [ ] **Step 2: Add the two fixture helpers as pgTAP-adjacent SQL**

The tests call `tests_seed_awaiting_confirm_gift` and `tests_seed_draft_gift`. Create them in a migration `supabase/migrations/20260904000004_test_seed_helpers.sql`, `service_role`-only, and say in the header comment that they exist **only** because `awaiting_confirm` has no client-reachable path until payments ship.

Each returns `json` with the keys the tests read (`token`, `senderName`, `productName`, `city`). Build the sender via `auth.users` + `profiles`, the recipient person, a celebration edge, a service area named `Confirmville`, a product priced `84900`, a slot on the occasion date (Task 5's constraint requires the match), then `private.create_gift`, then `private.gift_transition` to `paid` and on to `awaiting_confirm`. Use a fixed handle prefix `confirmfixture_` and delete any prior rows with that prefix first, so repeated runs are idempotent.

**If a cleaner mechanism exists** — a pgTAP helper already in `supabase/tests/database/` you can reuse, or seeding over `SUPABASE_DB_URL` from the test file the way `add_celebrations/index.test.ts:20-22` does for suppressions — **prefer it and say why in your report.** Creating production-namespace functions solely for tests is a cost; the `add_celebrations` precedent of direct Postgres seeding may well be better. Make the call and justify it.

- [ ] **Step 3: Run the tests and watch them fail**

```bash
./supabase/functions/test.sh 2>&1 | tail -20
```

Expected: the three new tests fail — the stub returns `501`, so the status assertions fail first.

- [ ] **Step 4: Implement the GET handler**

Replace `supabase/functions/confirm/index.ts`. Structure it as: a `COPY` const holding every string once; a `page(title, body)` helper wrapping content in a minimal HTML document with inline `<style>`; `renderForm(gift)`; `renderNeutral404()`; and a `Deno.serve` that dispatches on `req.method`.

Requirements the tests pin, and which you must not satisfy by accident:

- Read the gift with an **explicit column list**, never `select *`, so a column added to `gifts` later cannot leak by default (spec §4.6).
- Escape every interpolated value. The sender's `display_name`, the product name and the recipient's own typed city all reach HTML; an unescaped `<` is an injection. Write a small `esc()` and use it on **every** interpolation.
- The neutral 404 must be produced by **one** code path used by all of: unknown token, malformed token, missing token, and status `<> 'awaiting_confirm'`. Do not write it four times — the byte-identity assertion is what makes that folding real, and duplicated literals drift.
- `POST` still returns `501` at this point; Task 4 replaces it.

- [ ] **Step 5: Run and verify green**

```bash
./supabase/functions/test.sh 2>&1 | tail -12
```

Expected: 10 passed, 0 failed.

- [ ] **Step 6: Prove each new assertion can fail**

Three reverts, each restored byte-identically (verify with `md5 -q`):

1. **The price leak guard** — interpolate `${gift.amount_minor}` into the form template. Expected: the "no price" assertion fails on `84900`. This proves the assertion reads the response body rather than the query.
2. **The neutral-404 folding** — make the wrong-status branch return its own message (`"this gift is not ready to confirm yet"`). Expected: the byte-identity assertion fails, and **only** that one.
3. **The form fields** — remove `name="pincode"` from the template. Expected: the field loop fails naming `pincode`, proving it checks each field rather than passing on the first.

For each, paste the actual failure output and confirm no other test changed state.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/confirm/ supabase/migrations/
git commit -m "feat(confirm): the GET form and the neutral 404

Unknown, malformed and not-yet-confirmable tokens all return one
byte-identical 404 from a single code path. Separating them would tell a
prober that a token is real but its gift unpaid -- an oracle no
legitimate recipient needs, since links are only sent after payment."
```

---

### Task 4: `POST /confirm` — confirmed, refunded, already used

**Files:**
- Modify: `supabase/functions/confirm/index.ts`
- Modify: `supabase/functions/confirm/index.test.ts` (append)

**Interfaces:**
- Consumes: `public.rpc_confirm_gift(uuid, text, text, text, text, text)` from Task 1, called as `admin.rpc("rpc_confirm_gift", { p_confirm_token, p_line1, p_line2, p_city, p_pincode, p_label })`. `COPY` from Task 3.
- Produces: `POST /functions/v1/confirm` accepting `application/x-www-form-urlencoded`.

- [ ] **Step 1: Write the failing tests**

Append four tests. Each posts a urlencoded body and asserts on the rendered HTML:

```ts
// deno-lint-ignore no-explicit-any
function form(fields: Record<string, string>): RequestInit {
  return {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  };
}

Deno.test("POST with an in-area address confirms the gift", async () => {
  const admin = createClient(URL, SERVICE);
  const gift = await awaitingConfirmGift(admin);

  const res = await fetch(FN, form({
    token: gift.token,
    line1: "1 Cake Street",
    line2: "",
    city: gift.city, // matches the service area name
    pincode: "122004",
    label: "Home",
  }));
  const html = await res.text();

  assertEquals(res.status, 200);
  assertEquals(html.includes(gift.city), true);

  // The DB is the real assertion: status advanced and delivery_city was
  // denormalised onto the gift, which is what the sender's gift list reads
  // instead of AppStrings.giftCityPending.
  const { data } = await admin.from("gifts")
    .select("status, delivery_city, confirm_token_used_at")
    .eq("confirm_token", gift.token).single();
  assertEquals(data.status, "confirmed");
  assertEquals(data.delivery_city, gift.city);
  assertNotEquals(data.confirm_token_used_at, null);
});

Deno.test("POST with an out-of-area city refunds instead of delivering", async () => {
  const admin = createClient(URL, SERVICE);
  const gift = await awaitingConfirmGift(admin);

  const res = await fetch(FN, form({
    token: gift.token,
    line1: "9 Far Road",
    line2: "",
    city: "Nowhere",
    pincode: "999999",
    label: "Home",
  }));
  const html = await res.text();

  assertEquals(res.status, 200);
  assertEquals(html.includes("Nowhere"), true, "the page should name the city it cannot reach");

  const { data } = await admin.from("gifts")
    .select("status").eq("confirm_token", gift.token).single();
  assertEquals(data.status, "refunded", "out of area means refund, not delivery");
});

Deno.test("POST twice with the same token reports already confirmed", async () => {
  const admin = createClient(URL, SERVICE);
  const gift = await awaitingConfirmGift(admin);
  const body = form({
    token: gift.token, line1: "1 Cake Street", line2: "",
    city: gift.city, pincode: "122004", label: "Home",
  });

  await fetch(FN, body);
  const second = await fetch(FN, form({
    token: gift.token, line1: "1 Cake Street", line2: "",
    city: gift.city, pincode: "122004", label: "Home",
  }));
  const html = await second.text();

  assertEquals(second.status, 200);
  assertEquals(html.includes(COPY_ALREADY_CONFIRMED_SUBSTRING), true);
});

Deno.test("POST with a missing required field re-renders the form, not a crash", async () => {
  const admin = createClient(URL, SERVICE);
  const gift = await awaitingConfirmGift(admin);

  const res = await fetch(FN, form({
    token: gift.token, line1: "", line2: "", city: "", pincode: "", label: "",
  }));

  assertNotEquals(res.status, 500, "a blank form must not 500");
  assertEquals(res.status, 200);
  const { data } = await admin.from("gifts")
    .select("status").eq("confirm_token", gift.token).single();
  assertEquals(data.status, "awaiting_confirm", "a rejected form must not advance the gift");
});
```

Define `COPY_ALREADY_CONFIRMED_SUBSTRING` in the test file as a literal matching the handler's copy — **not** imported from `index.ts`, so a copy change that breaks the page is caught rather than silently followed.

- [ ] **Step 2: Run and watch all four fail**

```bash
./supabase/functions/test.sh 2>&1 | tail -20
```

Expected: all four fail on `501` from the `POST` stub.

- [ ] **Step 3: Implement the POST handler**

- Parse with `await req.formData()` or `new URLSearchParams(await req.text())`.
- **Validate before calling the RPC.** `line1`, `city` and `pincode` are required; `line2` and `label` may be empty (`label` defaults to `'Home'`). A missing required field re-renders the form with an error, and must not reach the database — the last test asserts the gift is untouched.
- Map the RPC's failures onto pages by SQLSTATE and message, **not** by string-matching the driver text loosely:
  - `23514` → the gift is not awaiting confirmation → the **same neutral 404** as Task 3.
  - `'this confirmation link has already been used'` → already-confirmed page.
  - `'unknown confirmation link'` → neutral 404.
  - anything else → a generic failure page, status `500`, with the driver text **logged** via `console.error` and **not** rendered. `private.confirm_gift`'s messages name internal tables; the same rule `delete_account/index.ts:92` follows.
- The out-of-area case is **not** an error: `private.confirm_gift` refunds and returns the row normally, so read the returned `status` to decide between the confirmed and refunded pages rather than inferring from the city.
- Escape the recipient's typed city before rendering it — it reaches HTML on both the confirmed and refunded pages.

- [ ] **Step 4: Run and verify green**

Expected: 14 passed, 0 failed.

- [ ] **Step 5: Prove the assertions can fail**

Four reverts, each restored byte-identically:

1. **The refund branch** — render the confirmed page regardless of returned `status`. Expected: the out-of-area test fails on the page content while its DB assertion still passes, proving the page and the DB are asserted independently.
2. **The validation guard** — call the RPC with blank fields. Expected: the blank-form test fails on the gift's status having advanced (or on a `500`), proving it checks the database and not just the HTTP code.
3. **The already-used mapping** — let that error fall to the generic `500`. Expected: the double-POST test fails.
4. **The `23514` folding** — give it its own message. Expected: Task 3's byte-identity test fails, showing the two tasks' folding is one shared path.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/confirm/
git commit -m "feat(confirm): the POST handler and its four outcomes

Out of area is not an error: confirm_gift refunds and returns the row, so
the page is chosen from the returned status. Driver text is logged, never
rendered -- confirm_gift's messages name internal tables."
```

---

### Task 5: F3 — the date constraint moves into `private.create_gift`

**Files:**
- Create: `supabase/migrations/20260904000002_create_gift_occasion_date.sql`
- Create: `supabase/tests/database/31_create_gift_occasion_date.test.sql`
- Modify: `test/repositories/gift_repository_test.dart` (re-date four fixtures)

**Interfaces:**
- Consumes: `private.create_gift(p_sender uuid, p_recipient_person_id bigint, p_product_id bigint, p_slot_id bigint, p_occasion_date date, p_message text, p_hold_minutes int)` (`20260822000008_gift_lifecycle.sql:20`).
- Produces: no signature change. A new failure mode: SQLSTATE `23514` when the chosen slot's `slot_date <> p_occasion_date`.

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/database/31_create_gift_occasion_date.test.sql` with `plan(3)`:

1. A gift whose slot date **equals** the occasion date is created successfully (the happy path must keep working — without this, deleting the whole feature would pass).
2. A gift whose slot is one day **after** the occasion date raises `23514`. Use `throws_ok` pinned to the SQLSTATE.
3. A gift whose slot is one day **before** raises `23514`. Both directions, because a `>=` or `<=` typo passes one and fails the other.

Seed two slots on different dates in one service area so assertions 2 and 3 do not depend on each other's leftovers, and give each ample capacity so a failure is never a capacity collision masquerading as a date rejection — the exact confusion Phase 1a's Task 2 hit with `23514`.

- [ ] **Step 2: Run and watch assertions 2 and 3 fail**

```bash
supabase test db 2>&1 | tail -20
```

Expected: assertion 1 passes, 2 and 3 fail with "no exception thrown". **That specific failure text matters** — if they fail with a different SQLSTATE, the fixture is colliding with another constraint and the test is not yet measuring the date.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260904000002_create_gift_occasion_date.sql`. Recreate `private.create_gift` in full (it is `create or replace`; copy the existing body from `20260822000008_gift_lifecycle.sql:20-85` and add the check) so the file is self-contained and reviewable.

Fold the date check into the **existing** slot lookup rather than adding a second query — the current block is:

```sql
  if not exists (
    select 1 from public.delivery_slots s
    where s.id = p_slot_id and s.service_area_id = v_area
  ) then
    raise exception 'slot % is not in the product''s service area', p_slot_id
      using errcode = '23514';
  end if;
```

Extend it to select the slot's date and check both facts, raising a **distinct message** for the date case (same SQLSTATE `23514`, since the client maps that to "pick another window", but a different message so an operator reading logs can tell the two apart).

Head the migration with a comment explaining that Phase 1a enforced this **only** in the slot picker's client-side filter, that the picker's filter stays as defence in depth, and that this closes ruling F3.

- [ ] **Step 4: Run pgTAP and verify green**

```bash
supabase db reset && supabase test db 2>&1 | tail -6
```

Expected: `Files=32`, all pass.

- [ ] **Step 5: Re-date the four contract fixtures**

`test/repositories/gift_repository_test.dart` currently pairs `occasionDate: DateTime.now().add(const Duration(days: 10))` with slots on `current_date + 1` (`roomySlotId`) and `current_date + 2` (`tightSlotId`). Assertions 4, 5, 6 and 7 will now fail with `23514`.

Change each `createDraft` call's `occasionDate` to match its slot's date — **not** the constraint. Compute it from the same offset the fixture uses so the two cannot drift: if `roomySlotId` is seeded at `current_date + 1`, its callers pass `DateTime.now().add(const Duration(days: 1))`.

Also re-date the raw-SQL seeded gift at `:232` (`current_date + 60` against `roomySlotId`). It bypasses `create_gift` so the constraint does not reject it, but leaving it would model a row the system can no longer produce.

- [ ] **Step 6: Run the contract suite**

The stack and the function server must both be running.

```bash
KEY=$(supabase status 2>/dev/null | grep -i "publishable" | awk -F'│' '{print $3}' | tr -d ' ')
fvm flutter test test/repositories test/e2e --dart-define=SUPABASE_ANON_KEY="$KEY" 2>&1 | tr '\r' '\n' | tail -3
```

Expected: 47 passed. **If you see a mass failure (30+), check `supabase functions serve` is running before debugging anything else** — the contract suite calls Edge Functions, and a stopped edge runtime presents as a broad regression rather than a config problem.

- [ ] **Step 7: Prove the constraint is load-bearing**

Comment out the date check, `supabase db reset`, re-run pgTAP. Expected: assertions 2 and 3 fail with "no exception thrown". Restore, verify `md5` matches, re-run green. Then confirm the client-side picker filter is **untouched** by this task:

```bash
git diff --stat lib/
```

Expected: empty. The client filter stays; this is defence in depth, not a replacement.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260904000002_create_gift_occasion_date.sql \
        supabase/tests/database/31_create_gift_occasion_date.test.sql \
        test/repositories/gift_repository_test.dart
git commit -m "feat(db): the slot must fall on the occasion date (F3)

Phase 1a enforced this only in the picker's client-side filter, so
anything creating a gift outside the UI could write a row whose van
arrives on a different day than the occasion it records. The picker's
filter stays -- this is defence in depth.

Re-dates the four contract fixtures that deliberately mis-dated."
```

---

### Task 6: §11.2 — the recipient can no longer read the price

**Files:**
- Create: `supabase/migrations/20260904000003_gifts_select_sender_only.sql`
- Modify: `supabase/tests/database/07_gifts.test.sql:86-92` (**invert** an M0 assertion)

**Interfaces:**
- Consumes: `gifts_select_participants` (`20260822000007_gifts.sql:176-184`), `private.my_person_id()`, `private.is_staff()`.
- Produces: no new interface. `public.gifts` becomes readable by the sender and staff only.

**This task changes an existing M0 guarantee.** Treat the assertion change as a behaviour change, not a test fix.

- [ ] **Step 1: Read the assertion you are about to invert**

```bash
sed -n '80,100p' supabase/tests/database/07_gifts.test.sql
```

It asserts `count(*) = 1` as the honoree: *"the recipient sees the gift addressed to them."* Confirm the surrounding test's fixture so you know which user is the honoree and which is the sender.

- [ ] **Step 2: Invert it, and add the price assertion**

Replace the assertion with one asserting **zero** rows, carrying a comment that names this spec (§6.4), states that it inverts an M0 guarantee deliberately, and explains why: `gifts_select_participants` had no column restriction, so a claimed recipient could read `amount_minor` — what the sender paid for their present — directly through PostgREST, with no app screen involved.

Add a second assertion in the same test proving the **sender still can** read their own row including `amount_minor`. Without it, dropping the policy entirely would pass.

- [ ] **Step 3: Run and watch the inverted assertion fail**

```bash
supabase test db 2>&1 | tail -20
```

Expected: the new zero-rows assertion fails (`have: 1, want: 0`) against the **old** policy, and the sender assertion passes. This is the proof that the assertion tests the policy rather than the fixture — the step that matters most in this task.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20260904000003_gifts_select_sender_only.sql`: drop and recreate `gifts_select_participants` without the recipient branch.

```sql
drop policy gifts_select_participants on public.gifts;

create policy gifts_select_participants
  on public.gifts
  for select
  to authenticated
  using (
    sender_profile_id = (select auth.uid())
    or (select private.is_staff())
  );
```

Head it with a comment covering: what the exposure was; that Postgres column privileges are per-role, not per-row, so a column revoke would hide the price from the **sender** too and would have to be undone for Phase 2 receipts; that `myGifts()` issues a bare `.select()` (`gift_repository_impl.dart:122`) which a column revoke would turn into a permission error; that no in-app recipient surface exists today, so this costs nothing now; and that when one ships, access returns through a narrow `security definer` function exposing safe columns, never by restoring this branch.

- [ ] **Step 5: Run everything and verify green**

```bash
supabase db reset && supabase test db 2>&1 | tail -6
```

Expected: `Files=32`, all pass — including `11_rls_coverage.test.sql`, which asserts every table's policy coverage and must not have been disturbed.

Then the Flutter suites, because `myGifts()` reads this table:

```bash
fvm flutter analyze 2>&1 | tail -2
KEY=$(supabase status 2>/dev/null | grep -i "publishable" | awk -F'│' '{print $3}' | tr -d ' ')
fvm flutter test test/repositories test/e2e --dart-define=SUPABASE_ANON_KEY="$KEY" 2>&1 | tr '\r' '\n' | tail -3
fvm flutter test --exclude-tags=contract 2>&1 | tr '\r' '\n' | tail -1
```

Expected: analyze clean, 47 contract passing, 207 non-contract passing.

- [ ] **Step 6: Repair contract assertion 7, which this task makes vacuous**

**This is not optional, and it is this task's responsibility because this task is what breaks it.**

Contract assertion 7 (`test/repositories/gift_repository_test.dart:379-401`) proves `myGifts()` filters on the sender rather than trusting RLS. Its fixture is a gift **received** by the primary caller — Phase 1a's own re-review established that RLS *admits* that row via the recipient branch and **only** the client's `.eq(ApiParams.senderProfileId, userId)` excludes it. That is precisely the branch Step 4 removes. After this migration RLS excludes the row by itself, the assertion passes for a reason unrelated to the filter, and it becomes the fourteenth test on this project to pass against the exact bug it was written to catch.

The fixture must become a **staff** caller. `private.is_staff()` survives in the policy, so for a staff user RLS admits *every* gift and the client-side sender filter is the only thing narrowing `myGifts()` to their own — which is now the real risk the filter guards, and a sharper one than before: a staff user calling `myGifts()` without it would receive the whole table.

Do this:

1. Seed a staff profile (find how `private.is_staff()` resolves staff — grep for `is_staff` in `supabase/migrations/` — and follow whatever mechanism the existing pgTAP staff tests use).
2. Point assertion 7 at that caller, with a gift sent by someone else still present.
3. Remove `.eq(ApiParams.senderProfileId, userId)` from `gift_repository_impl.dart:107` and confirm the amended assertion **fails**, showing the other sender's gift in the result.
4. Restore it, verify `md5` matches, and re-run the contract suite green.

Paste the pre-fix failure transcript. If seeding a staff profile turns out to need machinery this task should not own, **stop and report** rather than leaving the assertion vacuous or silently weakening it — a knowingly-hollow assertion is worse than a failing one, and the controller will re-scope.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260904000003_gifts_select_sender_only.sql \
        supabase/tests/database/07_gifts.test.sql \
        test/repositories/gift_repository_test.dart
git commit -m "feat(db): a recipient can no longer read what the sender paid

gifts_select_participants granted select with no column restriction, so a
claimed recipient could read amount_minor through PostgREST with no app
screen involved. Column privileges are per-role, not per-row, so a revoke
would hide the price from the sender too and break myGifts()'s bare
select().

Inverts an M0 assertion deliberately: 07_gifts.test.sql asserted the
recipient sees their gift. When a recipient surface ships, access returns
through a narrow function exposing safe columns."
```

---

### Task 7: Phase close — cold verification and the ledger

**Files:**
- Create: `docs/superpowers/execution/2026-09-XX-m3-phase1b-ledger.md` (use the actual date)

- [ ] **Step 1: Cold verification, every suite**

From a stopped state, bring everything up and run all five:

```bash
supabase db reset
supabase test db 2>&1 | tail -6
# with `supabase functions serve --no-verify-jwt` running:
./supabase/functions/test.sh 2>&1 | tail -6
fvm flutter analyze 2>&1 | tail -2
fvm flutter test --exclude-tags=contract 2>&1 | tr '\r' '\n' | tail -1
KEY=$(supabase status 2>/dev/null | grep -i "publishable" | awk -F'│' '{print $3}' | tr -d ' ')
fvm flutter test test/repositories test/e2e --dart-define=SUPABASE_ANON_KEY="$KEY" 2>&1 | tr '\r' '\n' | tail -1
```

Record counts before (pgTAP 30 files / 287 assertions, Deno 6, analyze clean, 207 non-contract, 47 contract) and after.

- [ ] **Step 2: Re-verify the config guard one last time**

```bash
grep -n "enable_confirmations" supabase/config.toml
git diff main -- supabase/config.toml
```

Line 252 must still read `enable_confirmations = true`, and the whole-phase diff of that file must show **only** the `[functions.confirm]` block.

- [ ] **Step 3: Write the ledger**

Follow `docs/superpowers/execution/2026-08-31-m3-phase1a-ledger.md`'s structure: final verification numbers; the config guard; per-task commit range; **what is not verified**; carried forward; and every ruling with its cost-if-wrong.

State plainly in a "Not verified" section:

- **The `verify_jwt = false` config value is not covered by any test.** The Deno harness serves with `--no-verify-jwt` and bypasses the gateway, so the suite behaves identically whether the config is right or wrong. It is verifiable only by deployment. This is the same shape as the iOS App Transport Security defect that survived 96 passing tests in Phase 2b.
- **No device or simulator run has ever happened, in any phase.** This phase adds no Flutter screens, so it adds no new exposure, but it does not reduce the standing risk.
- **No user can reach the confirm page.** `awaiting_confirm` requires `paid` (Phase 2, blocked on a provider account) and the link needs SMS (M1 Phase 2c, blocked on an SMS account).

Carry forward: spec §9's race row (still unwritten, waiver corrected in Phase 1a); the paid-gift deletion policy for Phase 2; `address_access_log.staff_profile_id` for M4; `seed.sql`'s non-idempotent `products` insert; whether a sender may hold two slots at once.

- [ ] **Step 4: Commit and STOP**

```bash
git add docs/superpowers/execution/
git commit -m "docs(ledger): M3 Phase 1b cold-verification record and carry-forwards"
```

**Do not merge. Do not touch `main`.** A whole-branch review comes first, then the merge decision is the user's.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §2 no Flutter web target | Global Constraints; no task creates `web/` |
| §3 what M0 built | Task 1 Step 1 verifies the premise rather than trusting it |
| §4.1 two methods | Tasks 3 (GET), 4 (POST) |
| §4.2 the RPC wrapper, R3 unchanged | Task 1 |
| §4.3 five outcomes, neutral folding | Task 3 (404 folding), Task 4 (confirmed / refunded / already used) |
| §4.4 token strength | Recorded in the spec; no task — nothing to build, and Task 7's ledger repeats it |
| §4.5 `verify_jwt` | Task 2 |
| §4.6 what the page must not show | Task 3 Step 1 (price assertions), Step 6 revert 1 |
| §5 F3 date constraint | Task 5 |
| §6 §11.2 recipient branch | Task 6 |
| §7 testing | Every task's own steps |
| §8 not reachable | Task 7 Step 3 |
| §9 risks | Task 2's preamble (risk 5), Task 7 Step 3 |
| §10 carried forward | Task 7 Step 3 |
| §11 open questions | Q1 (show the message) resolved as "show it" — Task 3's interface lists `gifts.message` among the four values read |

**Placeholder scan:** One deliberate deferral, flagged rather than hidden — Task 3 Step 2 does not dictate the fixture mechanism, instead naming two viable options (`service_role` seed functions, or direct Postgres seeding as `add_celebrations/index.test.ts` does) and requiring the implementer to choose and justify. Every other step carries its actual content. The ledger filename uses `2026-09-XX` because the close date is unknown at planning time; Task 7 says to use the actual date.

**Type consistency:** `rpc_confirm_gift`'s six parameters are spelled identically in Task 1's migration, Task 1's four pgTAP assertions, and Task 4's `admin.rpc` call. `private.create_gift`'s signature is unchanged by Task 5. The `COPY` const is produced in Task 3 and consumed in Task 4; Task 4 deliberately duplicates the already-confirmed substring in its test rather than importing it, and says why.

**A cross-task interaction caught at planning time, and fixed rather than deferred:** Task 6 removes the RLS branch that contract assertion 7's fixture depends on. Phase 1a's re-review established that the fixture is a gift *received* by the caller, admitted by RLS and excluded **only** by the client's sender filter — so removing that branch would leave the assertion passing for an unrelated reason, the fourteenth such test on this project. Task 6 Step 6 therefore repairs it in the same task that breaks it, re-pointing the fixture at a **staff** caller, for whom `private.is_staff()` still admits every gift and the client filter is the only thing narrowing the result. That is a sharper test than the original: without the filter, a staff user's `myGifts()` would return the whole table.

An earlier draft of this plan deferred that repair with "report it, do not fix it." That was wrong — the defect is introduced here, its cause is known here, and leaving a knowingly-hollow assertion for a later phase to discover is the failure mode this project's whole review discipline exists to prevent.
