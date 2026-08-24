# Handoff — completing the final fix wave

A previous implementer completed F1, F2 and F3 (committed) and got most of the
way through F4 and F5 before its process stalled. Nothing is broken; the work is
simply unfinished, and the suite is RED on a plan-count mismatch.

Read `final-fix-brief.md` in this directory for the original nine findings.

## Already DONE and committed — do not redo

- **F1** (commit e7add52) — `private.sync_person_from_profile` now replaces the
  birthday triple wholesale instead of coalescing parts independently.
- **F2** (commit eb5171d) — `resolve_contacts` and `rpc_resolve_contacts` return
  `has_birthday boolean` instead of `birth_month`/`birth_day`.
- **F3** (commit f588076) — the incoming-edges policy is replaced by
  `public.my_celebrates()`, and the allowlist was widened.

## In the working tree, UNCOMMITTED and unfinished

`supabase/migrations/20260824000006_reminders.sql` and
`supabase/tests/database/17_reminders.test.sql` both carry edits:

- F4's lease-expiry assertion is present (it ages `claimed_at` by 11 minutes).
- F5's `cross join lateral ... limit 5` device bound is present.
- F5's claim-time `attempts = o.attempts + 1` is present, and the increment has
  been removed from `mark_reminder_failed`.

## What is left

### 1. The suite is RED — plan count

`17_reminders.test.sql` declares `plan(18)` but now runs 19 assertions:
`# Looks like you planned 18 tests but ran 19`. Count the assertions and set the
plan to the real number. It changes again if you add one below, so do this last.

### 2. F5's judgement call — the attempts assertion is now hollow

At `17_reminders.test.sql:100-107`:

```sql
-- Failure increments attempts, and the cap excludes a row that keeps failing.
select private.mark_reminder_failed(
  (select id from private.notification_outbox order by id limit 1), 'fcm 500');
select is(
  (select attempts from private.notification_outbox order by id limit 1),
  1,
  'a failed delivery increments attempts'
);
```

`attempts` now advances at CLAIM time, and `mark_reminder_failed` no longer
touches it. So this assertion may still pass — but it would be proving that an
earlier claim incremented the counter, not that the failure was recorded. Its
description would be a lie.

Rewrite it so it proves what `mark_reminder_failed` actually does now, which is
record the error:

```sql
-- attempts advances at CLAIM time now, so a failure's observable effect is
-- last_error. Assert that, or this proves only that some earlier claim
-- incremented a counter.
select private.mark_reminder_failed(
  (select id from private.notification_outbox order by id limit 1), 'fcm 500');
select is(
  (select last_error from private.notification_outbox order by id limit 1),
  'fcm 500',
  'a failed delivery records why'
);
```

Then, because the retry cap still needs the counter to mean something, ADD one
assertion proving the claim is what advances it:

```sql
-- The counter has to advance somewhere or the retry cap never engages. It is the
-- claim that does it, which is what bounds a drain that dies mid-send.
update private.notification_outbox
set sent_at = null, claimed_at = null, attempts = 0;
select private.next_reminder_batch();
select is(
  (select max(attempts) from private.notification_outbox),
  1,
  'claiming a reminder counts an attempt'
);
```

Verify both empirically before trusting them — if the real values differ from
what I have written, use the real ones and say so in your report. Do NOT weaken
an assertion to make it pass.

### 3. F5's device-bound assertion

The brief asks for an assertion that a user with six registered devices gets at
most 5 rows. Check whether the previous implementer added it (the `limit 5` code
is in place). If it is missing, add it.

### 4. F6, F7, F8, F9 — not started

All four are specified in `final-fix-brief.md`. Do them as written:

- **F6** — `DRAIN_SECRET` header check in `drain_reminders/index.ts`, with a curl
  proof that a call without the header is 401 and one with it proceeds.
- **F7** — three assertions that read stronger than they are: the near-vacuous
  `rpc_next_reminder_batch` `lives_ok` (seed a fresh eligible reminder before it
  so it actually returns a row, and drop the false comment about runtime drift),
  the leap-year assertion's unfalsifiable "no double-fire" wording, and
  `18_resolve_contacts.test.sql`'s global `public.people` count.
- **F8** — merge the two RLS queries in `11_rls_coverage.test.sql` with
  `n.nspname = any(array['public','private'])` and extend the FK-index query the
  same way.
- **F9** — comment only, in `20260824000005_device_tokens.sql`.

## Finish with

`supabase db reset && supabase test db` — report the exact figures rather than
aiming at a number. Then `supabase db lint --level warning`, confirming warnings
stay inside `extensions.*`, and confirm the three standing guards pass.
