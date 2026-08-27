# Task 2 Report: A per-user reminder preference the fan-out honours

## Summary

Followed the brief exactly, verbatim. No corrections were needed to the brief's SQL. TDD cycle:
RED confirmed before writing the migration, then GREEN after, full suite passing at the expected
count, single commit made per the brief's final step.

## Baseline

Before touching anything:

```
Files=19, Tests=168,  1 wallclock secs (...)
Result: PASS
```

This matches the expected baseline given in the task instructions.

Also inspected the existing `private.enqueue_reminders` via
`docker exec supabase_db_birthday_app psql -U postgres -d postgres -c "\sf private.enqueue_reminders"`
before writing the migration, to confirm the brief's `create or replace` body preserves the
existing logic verbatim:
- the `foreach v_offset in array array[7, 1, 0]::smallint[]` offset loop (this is what the brief's
  context note calls "the December-to-January offset loop" — date arithmetic on `p_today + v_offset`
  naturally wraps a late-December `p_today` into January targets, no special-cased branch needed)
- the Feb-29-observed-on-Feb-28 branch with its leap-year predicate, unchanged
- the `not exists` filter against `public.blocks`, unchanged

The brief's replacement adds exactly one thing: a `join public.profiles r on r.id =
c.celebrator_profile_id` and the predicate `and r.reminders_enabled`. Nothing else was simplified
or dropped. Confirmed safe to proceed.

## Step 1-2: Failing test (RED)

Created `supabase/tests/database/19_reminder_preference.test.sql` verbatim from the brief.

Ran:
```
supabase test db supabase/tests/database/19_reminder_preference.test.sql
```

Real RED output:
```
psql:.../19_reminder_preference.test.sql:28: ERROR:  column "reminders_enabled" of relation "profiles" does not exist
LINE 1: update public.profiles set reminders_enabled = false where h...
                                   ^
.../19_reminder_preference.test.sql ..
# Failed test 1: "profiles.reminders_enabled exists"
Dubious, test returned 3 (wstat 768, 0x300)
Failed 3/4 subtests

Test Summary Report
-------------------
.../19_reminder_preference.test.sql (Wstat: 768 (exited 3) Tests: 2 Failed: 1)
  Failed test:  1
  Non-zero exit status: 3
  Parse errors: Bad plan.  You planned 4 tests but ran 2.
Files=1, Tests=2,  0 wallclock secs (...)
Result: FAIL
```

Matches the brief's expectation exactly: `has_column` fails (assertion 1), and the script aborts
on the later `update ... reminders_enabled` statement because the column does not exist yet
(the `on` clause of the `where handle = 'quiet'` update in the "turned off" section — a raw SQL
error, not a pgTAP assertion failure, since the column reference is invalid at parse time).

## Step 3: Migration

Created `supabase/migrations/20260827000001_reminder_preference.sql` verbatim from the brief:
- `alter table public.profiles add column reminders_enabled boolean not null default true;`
- `grant update (reminders_enabled) on public.profiles to authenticated;` (Trap 1 — the silent
  column-grant gap. Kept exactly as given.)
- `create or replace function private.enqueue_reminders(...)` with the full preserved body
  (Trap 2 — confirmed above, nothing dropped) plus the new `join public.profiles r` and
  `and r.reminders_enabled` predicate.
- `revoke execute on function private.enqueue_reminders(date) from public, anon, authenticated;`
  repeated even though `create or replace` preserves the ACL, per the brief's own comment.

No corrections were needed — the migration applied cleanly and produced the exact expected
behavior on the first attempt.

## Step 4: Full suite (GREEN)

```
supabase db reset && supabase test db
```

`db reset` applied `20260827000001_reminder_preference.sql` cleanly along with all prior
migrations, no errors (the only NOTICE was the pre-existing, unrelated
`function tests.create_person(text,text,date) does not exist, skipping` from seed.sql, present
on this branch already and unrelated to this task).

Full suite output (tail):
```
.../04_addresses.test.sql ............ ok
.../05_catalog_slots.test.sql ........ ok
.../06_slot_concurrency.test.sql ..... ok
.../07_gifts.test.sql ................ ok
.../08_gift_lifecycle.test.sql ....... ok
.../09_wishes.test.sql ............... ok
.../10_ops.test.sql .................. ok
.../11_rls_coverage.test.sql ......... ok
.../12_birthday_model.test.sql ....... ok
.../13_celebrate_counts.test.sql ..... ok
.../14_wish_history.test.sql ......... ok
.../15_birthday_stats.test.sql ....... ok
.../16_device_tokens.test.sql ........ ok
.../17_reminders.test.sql ............ ok
.../18_resolve_contacts.test.sql ..... ok
.../19_reminder_preference.test.sql .. ok
All tests successful.
Files=20, Tests=172,  1 wallclock secs (...)
Result: PASS
```

Matches the expected end state exactly: `Files=20, Tests=172, PASS`.

### Confirmation of guards that must not break

- `17_reminders.test.sql` — passed, untouched, all 9 of its assertions green (visible as `ok` in
  the full-suite run above, dot count consistent with the file's own assertion count). Not edited.
  Its fixtures create users via `tests.create_user`, whose profiles get `reminders_enabled`
  defaulting to `true`, so the new `and r.reminders_enabled` predicate in the fan-out does not
  filter any of its expected recipients.
- `01_private.test.sql` (which private functions `authenticated` may execute) — passed. This task
  added no new private function, and `enqueue_reminders`'s `revoke execute ... from ...
  authenticated` was repeated in the migration, keeping it revoked as before.
- `11_rls_coverage.test.sql` — passed, untouched.

## Step 5: Commit

Staged the two new files by exact name (no `-A`, no `.`):
```
git add supabase/migrations/20260827000001_reminder_preference.sql \
        supabase/tests/database/19_reminder_preference.test.sql
git commit -m "feat(db): add a reminder preference the fan-out honours"
```

Commit SHA: `e768b7fb178d40fbb562cf75f6a0f43b336979dc`
(2 files changed, 119 insertions(+))

## Concerns

None. The brief's SQL was correct as given — both traps (the silent column-grant gap, and the
preserved fan-out logic) were exactly as described and handled by the brief's own migration text
without needing any adjustment. This is a contrast with the prior task's brief, which reportedly
had a real defect; this one did not.

One minor observation, not a defect: `supabase db reset` emits a NOTICE that
`function tests.create_person(text,text,date) does not exist, skipping` during seed.sql. This is
pre-existing on this branch (present before this task's changes) and unrelated to
`tests.create_person(text, text, smallint, smallint)`, the 4-arg overload actually used by both
`19_reminder_preference.test.sql` and other test files. Did not investigate further since it does
not affect any test outcome and is outside this task's scope.

## Fix round 1 of 5

Review came back spec-approved / quality-approved with no Critical or Important findings —
confirmed the replaced function is byte-for-byte identical to the previous migration's preserved
logic. Two Minors were raised and closed in this round.

### F1 — the grant comment's failure-mode claim was factually wrong

The migration comment (and the brief it was copied from) claimed a missing column grant fails
*silently* — "the update affects nothing and raises nothing." The coordinator verified directly
that this is false:

```
update public.profiles set is_staff = true where id = (select auth.uid());
ERROR:  permission denied for table profiles
```

The failure is loud (`permission denied for table profiles`) and aborts the whole statement, even
when a granted column shares the same `SET` list as a non-granted one. The test itself was never
wrong — `lives_ok` does catch a missing grant, because it catches the thrown exception — but the
stated *reason* was wrong, and it's the kind of wrong that would make a future maintainer write
the wrong kind of test (checking rows-affected instead of catching an error).

Fixed in `supabase/migrations/20260827000001_reminder_preference.sql` — replaced the grant comment:

```sql
-- R14: profiles has NO table-level update grant for authenticated — it was
-- revoked and specific columns granted back one at a time. A new column is
-- therefore not client-writable until it is named here. The failure is LOUD,
-- not silent: updating a non-granted column raises
-- "permission denied for table profiles", and it aborts the whole statement
-- even when a granted column appears in the same SET list.
```

Left the other "does not silently drop the product's core function" comment (on the
`reminders_enabled` default) untouched — that is a different, correct use of "silently," about
product behavior, not grant semantics.

### F2 — assertion 4 proved no exception was raised, but never checked the write landed

The original `lives_ok` on the self-update proved only that nothing was raised. It never read
`reminders_enabled` back. A hypothetical variant where the grant is present but an RLS predicate
matches zero rows would update nothing, raise nothing, and still pass `lives_ok`.

Fixed in `supabase/tests/database/19_reminder_preference.test.sql` — replaced the `lives_ok` call
with a plain `update` followed by an `is()` assertion that reads the value back:

```sql
update public.profiles set reminders_enabled = true
where id = (select auth.uid());

select is(
  (select reminders_enabled from public.profiles where id = (select auth.uid())),
  true,
  'a user can turn their own reminders back on'
);
```

`select plan(4);` was left unchanged — this swaps assertion 4's shape without changing the count.

**Non-vacuousness check (ordering):** the assertion is only meaningful if `reminders_enabled` is
genuinely `false` immediately before this update — otherwise a no-op update would still pass.
Confirmed directly in the file: line 28 (`update public.profiles set reminders_enabled = false
where handle = 'quiet';`, in the "Turned off" block) sets it false, and nothing between line 28
and the new update at line 42 touches the column — the intervening statements are
`private.enqueue_reminders()` (reads the column, doesn't write it), an `is()` assertion (read-only),
and `tests.as_user(...)` (switches session role, doesn't touch data). Independently reproduced the
same state transition against a scratch user outside the test transaction to confirm the mechanics:

```
update public.profiles set reminders_enabled = false where handle = 'quiet_check2';
...
                  id                  | reminders_enabled
--------------------------------------+-------------------
 83f3d4df-4b35-4f27-992d-0063d9eeb99b | f
(1 row)
```

So the value is genuinely `false` right before the F2 update in the real test, making the `is(...)`
assertion non-vacuous.

### Verification

```
supabase db reset && supabase test db
```

Result unchanged: `Files=20, Tests=172, PASS`, all 20 files including
`19_reminder_preference.test.sql` reporting `ok`.

### Commit

Staged by name (no `-A`, no `.`):
```
git add supabase/migrations/20260827000001_reminder_preference.sql \
        supabase/tests/database/19_reminder_preference.test.sql
git commit -m "fix(db): correct the column-grant failure mode and prove the write lands"
```

Commit SHA: `ed750b344600f6ffbb5b275cdbb789697a312fb3`
(2 files changed, 16 insertions(+), 8 deletions(-))

### Concerns

None. Both Minors were addressed exactly as specified, verified against the running database
(not just asserted), and the full suite remains green at the expected count.
