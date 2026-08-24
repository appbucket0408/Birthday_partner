# Final review fix wave — 9 findings

One dispatch covers all of them. There will be no second fix wave.

The `20260824*` migrations are THIS phase's own — edit them in place. Nothing is
deployed and every database is rebuilt from scratch by `supabase db reset`. Never
touch a `20260822*` file.

---

## F1 (BLOCKING) — the sync trigger can synthesise an illegal birthday

`supabase/migrations/20260824000001_birthday_parts.sql`, function
`private.sync_person_from_profile`.

It coalesces `birth_month`, `birth_day` and `birth_year` INDEPENDENTLY against
the existing `people` row, but the CHECK constraints validate them as a triple.
So it can build a row nobody asked for and no constraint permits.

REPRODUCE IT FIRST and capture the output: create a user, claim a person, set the
person's birthday to (3,15,1985), then update the profile to (2,29,null). The
trigger synthesises (2,29,1985) and aborts on `people_birth_leap_valid`, rolling
back the user's own legal edit.

Fix — treat the birthday as ONE value. Replace the update body with:

```sql
begin
  update public.people
  set display_name = new.display_name,
      -- The three parts are ONE value, validated as a triple by the check
      -- constraints. Coalescing them independently can synthesise a combination
      -- nobody wrote — (2,29) from the profile against a stale 1985 from the
      -- person — which then aborts the user's own legal edit. So the profile's
      -- birthday replaces the person's wholesale, or not at all.
      birth_month = case when new.birth_month is not null then new.birth_month else birth_month end,
      birth_day   = case when new.birth_month is not null then new.birth_day   else birth_day   end,
      birth_year  = case when new.birth_month is not null then new.birth_year  else birth_year  end
  where profile_id = new.id;
  return new;
end;
```

Add ONE assertion to `supabase/tests/database/12_birthday_model.test.sql`
reproducing that exact case and asserting the person row ends year-less Feb 29
with no error. Raise `plan(17)` to `plan(18)`.

---

## F2 (BLOCKING) — contact resolution leaks a stranger's birthday

`supabase/migrations/20260824000007_resolve_contacts.sql`.

`private.resolve_contacts` is `security definer` with no relationship check, no
block check and no `can_see_person`. Any signed-in user POSTs up to 500 arbitrary
numbers, repeatedly, and harvests `display_name` plus `birth_month`/`birth_day`
for every match. That breaks the invariant M0 states in its own comment: a person
is visible only if they are you, you celebrate them, or they celebrate you —
"this is what keeps a stranger's birthday undiscoverable."

The import screen needs to know only WHETHER a birthday is missing, so it can
prompt. Change BOTH `private.resolve_contacts` and `public.rpc_resolve_contacts`
to return:

    phone text, person_id bigint, display_name text, has_birthday boolean

where `has_birthday` is `(p.birth_month is not null)`. Drop `birth_month` and
`birth_day` from both signatures.

Update `supabase/tests/database/18_resolve_contacts.test.sql` for the new shape
and add ONE assertion proving a resolved match reports `has_birthday = true` for
a person created with a birthday. Adjust `plan(...)`.

Also update `supabase/functions/resolve_contacts/index.ts` if it names those
fields (it may just pass rows through).

---

## F3 (BLOCKING) — the Celebrates list exposes the celebrator's private nickname

`supabase/migrations/20260824000002_celebrations_incoming.sql`.

RLS is row-level, so `celebrations_select_incoming` hands the subject the whole
row — including `nickname`, the celebrator's private label for them, and
`source`, which reveals HOW they were found. The spec explicitly refuses to
reveal an import to its subject. Column grants cannot fix it: they are role-wide
and would blind celebrators to their own nicknames.

1. Remove the `create policy celebrations_select_incoming` statement entirely.
2. Add:

```sql
-- RLS is row-level, so a policy exposing incoming edges would also hand the
-- subject the celebrator's private `nickname` and the `source` that reveals how
-- they were found. Column grants are role-wide and would blind celebrators to
-- their own nicknames, so the incoming list is a function returning only the
-- celebrator's identity. Display names come from public.people, which
-- private.can_see_person already makes visible in this direction.
create or replace function public.my_celebrates()
returns table (celebrator_profile_id uuid, celebrator_person_id bigint)
language sql
security definer
set search_path = ''
stable
as $$
  select c.celebrator_profile_id, p.id
  from public.celebrations c
  left join public.people p on p.profile_id = c.celebrator_profile_id
  where c.person_id = (select private.my_person_id())
    and not exists (
      select 1 from public.blocks b
      where b.blocker_profile_id = (select auth.uid())
        and b.blocked_profile_id = c.celebrator_profile_id
    );
$$;

revoke execute on function public.my_celebrates() from public, anon;
grant execute on function public.my_celebrates() to authenticated;
```

3. `public.my_celebrates` is client-callable, so it joins the guarded allowlist in
`supabase/tests/database/11_rls_coverage.test.sql`. Change the expected string to
(alphabetical — the query sorts by name):

    'my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token'

4. Rewrite `supabase/tests/database/13_celebrate_counts.test.sql` to exercise
`public.my_celebrates()`. Keep the same four properties: the subject sees both
celebrators; a celebrator sees only their own outgoing edge (that still uses the
untouched `celebrations_select_own`, so keep it a direct select); a blocked
celebrator drops out; the survivor is the unblocked one. ADD one assertion that a
subject selecting from `public.celebrations` now sees ZERO rows, proving
`nickname` is unreachable. Adjust `plan(...)`.

---

## F4 (BLOCKING, cheap) — assert the lease actually expires

`supabase/tests/database/17_reminders.test.sql`. The "a sent reminder never comes
back" block sets `claimed_at = null`, so the `claimed_at < now() - interval
'10 minutes'` branch is never exercised. Changing the lease to `'10 years'`
currently passes all 162 assertions, which would strand every crashed drain's
rows forever.

Add ONE assertion AFTER the existing retry-cap assertion:

```sql
-- The lease is what stops a crashed drain stranding rows forever. Age a claim
-- past it rather than clearing it, or the expiry branch is never exercised and
-- the interval could be changed to anything without failing a test.
update private.notification_outbox
set sent_at = null, claimed_at = now() - interval '11 minutes', attempts = 0;
select isnt_empty(
  $$ select outbox_id from private.next_reminder_batch() $$,
  'a claim older than the lease is reclaimable'
);
```

Raise the plan count.

---

## F5 (BLOCKING) — bound the fan-out, and count attempts at claim time

`supabase/migrations/20260824000006_reminders.sql`. Two linked problems:

(a) `next_reminder_batch`'s final join emits one row PER DEVICE TOKEN, and
`device_tokens_all_own` lets a user insert unlimited tokens — so any
authenticated user can multiply their own reminders into an arbitrary number of
FCM calls. `p_limit` bounds claimed outbox rows, not returned rows.

(b) The claim stamps `claimed_at` but not `attempts`. A drain that dies — or
today's dry-run path, which claims a batch and returns without marking — leaves
`attempts` at 0, so those rows recycle every ten minutes forever and
`attempts < 5` never engages.

Fix (a) with a lateral bound:

```sql
  select cl.id, d.token, d.platform, p.display_name, cl.offset_days, cl.occasion_date
  from claimed cl
  join public.people p on p.id = cl.subject_person_id
  -- At most five devices per reminder. A user may register unlimited tokens and
  -- this join is per-token, so without a bound one reminder becomes an unbounded
  -- number of FCM calls at the user's own discretion.
  cross join lateral (
    select d2.token, d2.platform
    from public.device_tokens d2
    where d2.profile_id = cl.recipient_profile_id
    order by d2.last_seen_at desc, d2.id desc
    limit 5
  ) d
  order by cl.id;
```

Fix (b): in the claiming UPDATE use `set claimed_at = now(), attempts = o.attempts + 1`,
and REMOVE the increment from `private.mark_reminder_failed` so it only records
`last_error` — otherwise a failure double-counts. Comment there that the counter
now advances at claim time.

Add ONE assertion that a reminder for a user with six registered devices returns
at most 5 rows.

CAREFUL: existing assertions depend on `attempts`. The retry-cap assertion sets
`attempts = 5` directly and still works. The "a failed delivery increments
attempts" assertion will now see the CLAIM advance it — check it, adjust its
expected value to the new correct semantics, keep it meaningful (a failing
delivery must still be counted), and explain the change in your report.

---

## F6 (BLOCKING) — drain_reminders has no authorization

`supabase/functions/drain_reminders/index.ts` never inspects its request. The
publishable key is itself a valid JWT, so anyone who unpacks the app can invoke
it — burning ten-minute leases now, FCM quota once credentials exist. Compare
`resolve_contacts/index.ts`, which validates its caller.

The handler currently takes no request parameter — change its signature to accept
one, and add at the top:

```ts
  // This is a machine endpoint — cron calls it, never a user. The publishable
  // key is a valid JWT, so JWT verification alone would let anyone who unpacks
  // the app trigger a drain: burning claim leases now, and FCM quota later.
  const expected = Deno.env.get("DRAIN_SECRET");
  if (!expected || req.headers.get("x-drain-secret") !== expected) {
    return new Response(JSON.stringify({ error: "not authorised" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
```

Verify with curl that a call WITHOUT the header returns 401 and one WITH it
proceeds. `supabase functions serve` needs `--env-file` to receive env vars;
prefixed shell vars are silently ignored.

---

## F7 — three assertions weaker than they read

1. `17_reminders.test.sql` — the `lives_ok(select * from
   public.rpc_next_reminder_batch(1))` assertion. Its justification is FALSE: for
   a `language sql` function, return-type drift raises at CREATE, so
   `supabase db reset` already guards it. By the time it runs every row is at
   `attempts = 5`, so it returns nothing and checks only that the function
   exists. Seed a fresh eligible reminder immediately before it and assert the
   wrapper RETURNS A ROW, so it exercises the real pass-through. Fix the comment
   — remove the false runtime-drift claim.
2. Same file — the leap-year assertion claims "no double-fire", but the two match
   arms are OR-ed in one predicate so a single edge can never produce two rows.
   Reword the description to what it actually proves (the leap-year T-1 uses the
   real Feb 29) rather than an unfalsifiable claim.
3. `18_resolve_contacts.test.sql` — the "creates nothing" proof counts ALL rows in
   `public.people`, so any future `seed.sql` addition breaks it for an unrelated
   reason. Count only rows matching this file's own fixture.

---

## F8 — close the guard asymmetry

`supabase/tests/database/11_rls_coverage.test.sql`: the RLS assertions cover
`public` and `private`, but the foreign-key-index assertion still scans `public`
only. Merge the two RLS queries into one using
`n.nspname = any(array['public','private'])` and extend the FK-index query the
same way. Keep the assertion count unchanged if the merge allows; if it changes,
adjust the plan and say so.

---

## F9 — documentation only, no code

In `supabase/migrations/20260824000005_device_tokens.sql`, expand the comment
above `register_device_token` to state the real reachable consequence: an
attacker who obtains a victim's device token can move it to their own account,
arrange a celebrated person whose `display_name` is arbitrary text with a
birthday of today, and thereby deliver attacker-chosen text as a trusted push
notification to the victim's device — while the victim silently stops receiving
their own reminders. Note that Phase 2 must not place an unsanitised
`display_name` in a notification title or body.

---

## Final verification

`supabase db reset && supabase test db` — report the exact figures. The count
WILL have moved; report what it is rather than trying to hit a number.

Confirm the three standing guards still pass, and run
`supabase db lint --level warning`, confirming warnings stay confined to
`extensions.*`.
