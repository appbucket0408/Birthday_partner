# Task 4 report: mint a person and a celebration edge when the user picks a contact

## Status: DONE_WITH_CONCERNS (brief's SQL needed a correction; documented below)

## Baseline

```
supabase test db
...
All tests successful.
Files=21, Tests=176,  1 wallclock secs (...)
Result: PASS
```

Matches the expected baseline given in the task context.

## Step 1–2: failing test written and run (RED)

Created `supabase/tests/database/21_add_celebration.test.sql` verbatim from the brief.

```
supabase test db supabase/tests/database/21_add_celebration.test.sql

psql:.../21_add_celebration.test.sql:18: ERROR:  function private.add_celebration(uuid, unknown, unknown, smallint, smallint, smallint) does not exist
LINE 2:   private.add_celebration((select picker from ids), '+919230...
          ^
HINT:  No function matches the given name and argument types. You might need to add explicit type casts.
.../21_add_celebration.test.sql ..
Dubious, test returned 3 (wstat 768, 0x300)
Failed 6/6 subtests
...
Result: FAIL
```

Matches the brief's predicted RED exactly (`function private.add_celebration(...) does not exist`).

## Step 3: migration written, then corrected

Wrote `supabase/migrations/20260827000003_add_celebration.sql` verbatim from the brief first, ran `supabase db reset`, then ran the new test file in isolation. Five of six subtests passed, but subtest 6 failed:

```
# Failed test 6: "picking your own number is rejected"
#       caught: no exception
#       wanted: P0001
```

### The defect and why

The brief says: *"Your function does not need to check this itself — the trigger fires on insert and the exception propagates."* This is wrong for this code path, and it is not just a test-fixture quirk — it is a real gap in the production design.

M0's `celebrations_guard` trigger (`private.guard_celebration()`, in `20260822000004_people_graph.sql`) checks self-celebration like this:

```sql
if new.person_id = private.my_person_id() then
  raise exception 'you cannot celebrate yourself';
end if;
```

and `private.my_person_id()` resolves the caller from **session state** — `auth.uid()`, which reads `request.jwt.claims`:

```sql
select p.id from public.people p where p.profile_id = (select auth.uid());
```

That works for the two call paths that existed before this task: an `authenticated` user inserting directly (RLS lets them insert only rows where `celebrator_profile_id = auth.uid()`, and the test suite always calls `tests.as_user(...)` first so `auth.uid()` matches the row being inserted).

`private.add_celebration` and its `public.rpc_add_celebration` wrapper are different: they take `p_celebrator` as an explicit **argument**, precisely because the wrapper is `service_role`-only and reached from an Edge Function with no per-caller session JWT — `auth.uid()` is null in that context (I confirmed `tests.as_postgres()` sets `request.jwt.claims` to null, which is the same null-auth.uid() situation a service_role call would see). Under that condition `private.my_person_id()` returns null, `new.person_id = null` evaluates to `NULL` (not `TRUE`), and the trigger silently does nothing — the self-celebration insert succeeds instead of raising. In production this would mean the service-role RPC path has **no self-celebration protection at all**, for any caller, not just in the test harness.

### The fix

Added an explicit check inside `private.add_celebration`, comparing the resolved `v_person_id`'s `profile_id` against the `p_celebrator` argument directly (not via session state), before the insert:

```sql
if exists (
  select 1 from public.people
  where id = v_person_id and profile_id = p_celebrator
) then
  raise exception 'you cannot celebrate yourself';
end if;
```

This raises the same message with the same default SQLSTATE (`P0001`) as the trigger, so the test's `throws_ok(... 'P0001', 'you cannot celebrate yourself' ...)` passes for the right reason: our own guard fires, independent of session auth state. The `celebrations_guard` trigger is left untouched and still provides defense-in-depth for the direct-insert/RLS path.

After the fix, `supabase db reset` + isolated run of the new test file:

```
.../21_add_celebration.test.sql .. ok
All tests successful.
Files=1, Tests=6,  0 wallclock secs (...)
Result: PASS
```

## Step 4: full suite (GREEN)

```
supabase db reset && supabase test db
...
00_harness.test.sql .............. ok
01_private.test.sql .............. ok
02_profiles.test.sql ............. ok
03_people_graph.test.sql ......... ok
04_addresses.test.sql ............ ok
05_catalog_slots.test.sql ........ ok
06_slot_concurrency.test.sql ..... ok
07_gifts.test.sql ................ ok
08_gift_lifecycle.test.sql ....... ok
09_wishes.test.sql ............... ok
10_ops.test.sql .................. ok
11_rls_coverage.test.sql ......... ok
12_birthday_model.test.sql ....... ok
13_celebrate_counts.test.sql ..... ok
14_wish_history.test.sql ......... ok
15_birthday_stats.test.sql ....... ok
16_device_tokens.test.sql ........ ok
17_reminders.test.sql ............ ok
18_resolve_contacts.test.sql ..... ok
19_reminder_preference.test.sql .. ok
20_claim_person_rpc.test.sql ..... ok
21_add_celebration.test.sql ...... ok
All tests successful.
Files=22, Tests=182,  1 wallclock secs (...)
Result: PASS
```

Matches the expected end state exactly: `Files=22, Tests=182, PASS`.

## Guard confirmation (both mandatory allowlists)

- `01_private.test.sql` line 67 still asserts the exact string
  `'can_see_person,is_staff,my_person_id'` for the private functions `authenticated` may execute, and this test passed in the full run (`ok`). `private.add_celebration` is not in that list — confirmed via `revoke execute on function private.add_celebration(...) from public, anon, authenticated;` in the new migration.
- `11_rls_coverage.test.sql` line 48 still asserts the exact string
  `'my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token'` for the public functions `authenticated` may execute, and this test passed in the full run (`ok`). `public.rpc_add_celebration` is not in that list — confirmed via explicit revoke from `public, anon, authenticated` plus a targeted grant to `service_role` only.

I also directly queried `has_function_privilege` for both new functions across `anon`, `authenticated`, `service_role`, `postgres`:

```
       proname       |    rolname    | can_exec
----------------------+---------------+----------
 add_celebration      | anon          | f
 add_celebration      | authenticated | f
 add_celebration      | postgres      | t
 add_celebration      | service_role  | f
 rpc_add_celebration  | anon          | f
 rpc_add_celebration  | authenticated | f
 rpc_add_celebration  | postgres      | t
 rpc_add_celebration  | service_role  | t
```

`private.add_celebration` is unreachable from any client/service role (only the function owner / superuser can call it directly, which is fine — it is meant to be reached only through the `security definer` wrapper). `public.rpc_add_celebration` is service_role-only, exactly as required.

## Behaviours verified by the pinned test (all pass)

1. Suppression returns null, not an error (subtest 5).
2. Idempotency via `on conflict on constraint celebrations_unique_edge do nothing` — a second pick does not error and does not create a second edge (subtests 3–4).
3. Self-celebration is rejected with SQLSTATE `P0001` and message `you cannot celebrate yourself` (subtest 6) — via the new explicit check described above, not solely via the M0 trigger.

## Files touched

- `supabase/migrations/20260827000003_add_celebration.sql` (new)
- `supabase/tests/database/21_add_celebration.test.sql` (new, verbatim from brief)

## Commit

```
b8b8d21 feat(db): mint a person and a celebration edge in one call
```

## Concerns for follow-up (not blocking this task)

- The underlying `celebrations_guard` trigger (`private.guard_celebration`, from M0) is session-auth-based and therefore provides **no** self-celebration protection on any future service_role-mediated write path that doesn't add its own explicit check, as this task had to. Worth a note for whoever writes the next service_role RPC that inserts into `public.celebrations` directly (bypassing `private.add_celebration`): they need to replicate this same explicit check, or `guard_celebration` should eventually be rewritten to compare against `NEW.celebrator_profile_id`'s own person rather than session `auth.uid()`. I left the trigger itself untouched since it wasn't in scope and other passing tests (`03_people_graph.test.sql`) depend on its current session-based behavior.

---

# Fix round 1 (code review response)

Review verdict: spec pass, quality NEEDS WORK — four Important (F1–F4), one Minor (F5). The reviewer confirmed the round-4 deviation (adding an explicit self-celebration check inside `add_celebration` instead of relying on `celebrations_guard`) was correct and necessary, not a defect.

## F2, F3, F4, F5 — implemented as specified

- **F2**: added one assertion that calls `public.rpc_add_celebration` directly (not `private.add_celebration`) with `3::smallint, 25::smallint` for month/day and checks `birth_month || '-' || birth_day` comes back `'3-25'`. Pins parameter order through the only surface production can actually reach.
- **F3**: added one assertion immediately after the suppression call, asserting `count(*) = 0` for celebration edges joined to a person named `'Opted Out'` — proves the suppressed call created nothing, not just that it returned null.
- **F4**: replaced the `lives_ok` idempotency check with an `is` comparing the retried call's return value against the first call's captured id (stored in a temporary table `picks` created right before the first assertion, so the first assertion could also reference the captured value instead of re-invoking the function). Proves the retry returns the *same person id*, not merely that it doesn't raise.
- **F5**: corrected the stale comment above the `throws_ok` self-celebration assertion — it now says the check lives in `add_celebration` because `celebrations_guard` is inert under service_role (no session for `auth.uid()`), instead of implying the M0 trigger does the rejecting.
- `select plan(6)` → `select plan(8)`, matching F2 (+1) and F3 (+1); F4 was an in-place replacement.

## F1 — reviewer's proposed fix does not close the hole; found and fixed the real gap

I did not implement F1's proposed SQL as a blind copy. Before trusting it, I reproduced the reviewer's own scenario end to end via a scratch script run against `docker exec supabase_db_birthday_app psql`, first with the reviewer's exact suggested check in place:

```sql
if exists (
  select 1 from public.people p
  where p.id = v_person_id
    and (
      p.profile_id = p_celebrator
      or p.phone_e164_hash = (
        select c.phone_e164_hash from public.people c
        where c.profile_id = p_celebrator
      )
    )
) then
  raise exception 'you cannot celebrate yourself';
end if;
```

Reproduction (celebrator has NO claimed person row yet, imports their own future number, then claims it):

```
their person row exists? | 0
add_celebration with own number -> | 1     (a new unclaimed person row was minted, no exception)
edges created: | 1
[claim_person runs]
AFTER CLAIM, is it now a self-edge? | YES - permanent self-edge
```

**This is the reviewer's own exact repro, and their proposed fix does not stop it.** The reason: the OR-clause's second branch computes "the celebrator's own phone hash" by querying `public.people` for a row where `profile_id = p_celebrator` — but in this exact scenario that row does not exist yet (that's the whole premise: signup happened, claim has not). The subquery returns `NULL`, the OR-clause is `NULL`, and the check is bypassed — identically to the original bug it was meant to fix. (The reviewer's own comment — *"the inner sub-select returns NULL when the celebrator has no person row at all, which is correct — there is then no own-hash to collide with"* — is the mistaken part: that is precisely the case their reproduction demonstrates is unsafe, not safe.)

I also checked whether the second OR-branch adds any coverage beyond the first in the cases where it *does* return non-null: `public.people.phone_e164_hash` is `unique`, so if the branch's subquery finds a hash match, `v_person_id`'s row must be the *same row* as the celebrator's already-claimed row — meaning `profile_id = p_celebrator` (the first branch) was already true. So the second branch is logically subsumed by the first everywhere it can fire, and does not fire at all in the one case it was written for (the unclaimed case). I left it in (it's harmless and it's literally what the review asked for), but it is not doing the job F1 asked it to do.

### Why the hole cannot be closed inside `add_celebration` alone

At `add_celebration` time, for a celebrator who has not yet claimed, there is no in-schema record anywhere of "this profile's own phone number" to compare `p_phone` against. `public.profiles` has no phone column; `auth.users.phone` exists in principle (Supabase Auth's verified-phone column) but nothing in this codebase populates or reads it — `claim_person`'s `p_phone` argument is passed in explicitly by the caller, not sourced from `auth.users`, and the test harness's `tests.create_user` only ever sets `email`. Relying on `auth.users.phone` would be introducing an undocumented, unverified assumption about this app's phone-auth wiring — not a safe correction to make silently.

The fact that *is* knowable, and becomes knowable at exactly one point, is: "this profile is being attached to this person row" — and that happens in `claim_person`, not `add_celebration`. `celebrations_guard` is `BEFORE INSERT` only and never re-fires on the `UPDATE` inside `claim_person`'s `ON CONFLICT ... DO UPDATE`, which is exactly why a pre-existing edge can turn into a self-edge with nothing to catch it.

### The actual fix

Re-created `private.claim_person` (via `create or replace function`, in the same new migration file — the original definition in `20260824000001_birthday_parts.sql` was not touched) with one addition: after attaching `profile_id` to the claimed row, delete any celebration edge where this profile is now celebrating that same row.

```sql
  -- Close the retroactive self-edge hole: if this profile imported their own
  -- number as a contact before claiming it, the edge became a self-edge the
  -- instant profile_id was attached above. Remove it now — a self-edge is
  -- never valid regardless of when it was created.
  delete from public.celebrations
  where celebrator_profile_id = p_profile_id and person_id = v_id;
```

Re-ran the identical reproduction against the corrected migration:

```
their person row exists? | 0
add_celebration with own number -> | 1
edges created: | 1
[claim_person runs]
AFTER CLAIM, is it now a self-edge? | no
```

Hole closed. I did not add a permanent pgTAP assertion for this scenario in `21_add_celebration.test.sql` — the reviewer's plan-count arithmetic (`plan(8)`, suite total 184) only accounts for F2/F3/F4, and adding a ninth assertion there would have broken that expected count. The claim-time fix was verified via the scratch reproduction above instead. (Flagging this for the reviewer's awareness in case they want a permanent regression test for it in a follow-up round — I judged staying inside the given plan-count contract to be the safer default for this round.)

### Note on scope

This fix touches `private.claim_person`'s *behavior* (via `create or replace function` in the new migration — no existing migration file was edited), which is one function beyond what F1's literal ask implied ("replace the self-check" inside `add_celebration`). I made this call because the alternative — implementing only what was asked, knowing it does not close the reported hole — seemed worse than a scoped, explained deviation. Grants on `claim_person` are unchanged (still revoked from `anon, authenticated`, not granted to `service_role` directly — reached only through the pre-existing `public.rpc_claim_person` wrapper from Task 3, which was not touched and still passes its own test file `20_claim_person_rpc.test.sql`).

## Verification

```
supabase db reset && supabase test db
...
Files=22, Tests=184,  ...
Result: PASS
```

Matches the reviewer's expected `Files=22, Tests=184, PASS` exactly.

### Guard confirmation (both allowlists, unchanged)

- `01_private.test.sql` line 67: still asserts `'can_see_person,is_staff,my_person_id'` — passed (`ok`).
- `11_rls_coverage.test.sql` line 48: still asserts `'my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token'` — passed (`ok`).

Directly queried `has_function_privilege` across `anon`, `authenticated`, `service_role` for all three touched functions:

```
       proname       |    rolname    | can_exec
----------------------+---------------+----------
 add_celebration      | anon          | f
 add_celebration      | authenticated | f
 add_celebration      | service_role  | f
 claim_person         | anon          | f
 claim_person         | authenticated | f
 claim_person         | service_role  | f
 rpc_add_celebration  | anon          | f
 rpc_add_celebration  | authenticated | f
 rpc_add_celebration  | service_role  | t
```

Unchanged from before this round — no new client-facing surface was opened.

## Commit

```
c5b5cbb fix(db): reject self-celebration before the person row is claimed
```

## Concerns carried forward

- The retroactive self-edge fix lives in `claim_person`'s `ON CONFLICT ... DO UPDATE` path and is not covered by a permanent pgTAP assertion (see note above) — only by the manual reproduction in this report. Recommend adding one in a follow-up if the reviewer wants it locked in the suite.
- Same standing concern as the original report: any *other* future write path that inserts into `public.celebrations` directly (bypassing `private.add_celebration`) still needs its own explicit self-celebration check, since `celebrations_guard` remains session-based and inert under `service_role`.

---

# Fix round 2 (code review response)

Coordinator confirmed round 1's judgement was correct: the reviewer's original F1 SQL could not have worked, and moving the cleanup into `claim_person` was the right call — that is the first point where both the profile and the phone number are known together.

## F6 — pin the claim-time cleanup with a permanent assertion

Added one assertion to `supabase/tests/database/21_add_celebration.test.sql`, placed at the end before `select * from finish();`, verbatim from the coordinator's message. Checked for fixture collisions first: existing phone numbers in the file are `+919230000001` through `...004`; the new fixture `+919230000009` does not collide.

`select plan(8);` → `select plan(9);`.

### Proof the assertion discriminates

Per instruction, I did **not** edit the migration file to test this — I applied a stripped-down `private.claim_person` (identical except the `delete from public.celebrations ...` cleanup line removed) directly against the running database via `docker exec supabase_db_birthday_app psql`, from a scratch file, then reran the test file, then restored via `supabase db reset`.

**RED (cleanup stripped, applied live via psql, migration file untouched):**

```
supabase test db supabase/tests/database/21_add_celebration.test.sql

.../21_add_celebration.test.sql ..
# Failed test 9: "claiming a number removes an edge that just became a self-edge"
#         have: 1
#         want: 0
# Looks like you failed 1 test of 9
Failed 1/9 subtests

Test Summary Report
-------------------
.../21_add_celebration.test.sql (Wstat: 0 Tests: 9 Failed: 1)
  Failed test:  9
Files=1, Tests=9, ...
Result: FAIL
```

Exactly one test failed — test 9, the new assertion — with `have: 1, want: 0`, confirming the self-edge survived when the cleanup was absent.

**GREEN (restored via `supabase db reset`, which reapplies the migration with the real cleanup intact):**

```
supabase db reset
...
Finished supabase db reset on branch main.

supabase test db
...
21_add_celebration.test.sql ...... ok
All tests successful.
Files=22, Tests=185,  1 wallclock secs (...)
Result: PASS
```

`Files=22, Tests=185, PASS` — matches the coordinator's expected end state exactly.

### Guard confirmation (both allowlists, unchanged)

- `01_private.test.sql` line 67: still asserts `'can_see_person,is_staff,my_person_id'` — passed (`ok`) in the full run.
- `11_rls_coverage.test.sql` line 48: still asserts `'my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token'` — passed (`ok`) in the full run.

No grants changed in this round (test-only change).

## Commit

```
a0a28c8 test(db): pin the claim-time self-edge cleanup
```

Staged only `supabase/tests/database/21_add_celebration.test.sql`, as instructed.

## Concerns carried forward

- Same standing concern as prior rounds: any future write path that inserts into `public.celebrations` directly (bypassing `private.add_celebration`) still needs its own explicit self-celebration check, since `celebrations_guard` remains session-based and inert under `service_role`.
