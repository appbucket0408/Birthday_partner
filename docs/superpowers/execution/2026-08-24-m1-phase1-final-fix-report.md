# Final fix wave — closing report (F6, F7 item 3, F8, F9, plan-count fix)

F1–F5 were already done and committed prior to this dispatch; not touched here.

## Item 0 — reminders plan count

`supabase/tests/database/17_reminders.test.sql` declared `plan(18)` but contained
21 assertions. On a fresh `supabase db reset`, all 21 pass, stable across two
consecutive `supabase test db` runs. Changed to `plan(21)`. The prior WIP
commit's warning against raising the count was based on a database left dirty
by a killed agent's psql fixtures (the documented "supabase test db does not
reset" hazard), not a real failure.

Commit: `31c8282` — fix(db): correct the reminders plan count to 21

## Item 1 — F6: drain_reminders authorization

`supabase/functions/drain_reminders/index.ts` handler now takes a `Request`
parameter and checks `x-drain-secret` against `Deno.env.get("DRAIN_SECRET")`
before doing any work, returning 401 `{"error":"not authorised"}` otherwise.
Matches the pattern in `resolve_contacts/index.ts`.

Verified locally with `supabase functions serve --env-file <file with
DRAIN_SECRET=test-drain-secret-123>`. Note: the local Kong gateway requires a
valid `Authorization` JWT on every function call regardless of this change
(default `verify_jwt`), so both curls below carry the local legacy anon JWT
from `supabase status -o env` in addition to testing the new header.

Without `x-drain-secret`:
```
HTTP/1.1 401 Unauthorized
{"error":"not authorised"}
```

With `x-drain-secret: test-drain-secret-123`:
```
HTTP/1.1 200 OK
{"dryRun":true,"would_send":0,"sent":0,"failed":0}
```

Commit: `94991d7` — fix(functions): require x-drain-secret on drain_reminders

## Item 2 — F7 item 3 (resolve_contacts fixture-scoped count)

Already implemented. `18_resolve_contacts.test.sql`'s "resolving unknown
numbers creates no people rows" assertion already counts only rows matching
`phone_e164_hash in (private.phone_hash('+919120000001'),
private.phone_hash('+919120000002'))` — the file's own fixture numbers — not
all of `public.people`. This was committed as part of `eb5171d` (F2). No
change made; no commit needed.

## Item 3 — F8: guard asymmetry closed

`11_rls_coverage.test.sql`: merged the two RLS-enabled assertions (public-only
and private-only) into one query using `n.nspname = any(array['public',
'private'])`, and extended the foreign-key-index assertion the same way (it
previously scanned `public` only). The merge reduced the assertion count from
4 to 3, so `plan(4)` became `plan(3)`.

Commit: `08bf924` — fix(db): extend RLS and FK-index coverage checks to private schema

## Item 4 — F9: documentation only

Expanded the comment above `register_device_token` in
`supabase/migrations/20260824000005_device_tokens.sql` to state the reachable
attack: an attacker holding a victim's device token can move it to their own
account via this function, arrange a celebrated person whose `display_name` is
arbitrary text with a birthday of today, and thereby deliver attacker-chosen
text as a trusted push notification to the victim's device, while the victim
silently stops receiving their own reminders (the token no longer points at
them). Notes Phase 2 must not place an unsanitised `display_name` in a
notification title or body. No code changes.

Commit: `7e26672` — docs(db): document the real attack path enabled by register_device_token

## Final verification

`supabase db reset && supabase test db`:
```
All tests successful.
Files=19, Tests=168,  ... 
Result: PASS
```
(169 → 168: the F8 merge removed one assertion from `11_rls_coverage.test.sql`.)

Standing guards confirmed still passing: `01_private.test.sql` (private
function allowlist) — ok; `11_rls_coverage.test.sql` (RLS, FK indexes, public
function allowlist) — ok, restructured per F8 only.

`supabase db lint --level warning`: findings present, all confined to
`extensions.*` (pgTAP's own internal functions — unused variables, dynamic-SQL
type-inference caveats, etc.). Nothing in `public` or `private`.

## Concerns

None outstanding. All five items closed; F7 item 3 required no work as it was
already correctly implemented under the F2 commit.

## Post-close mechanical fixes (2026-08-27)

Four small fixes closing out the phase before merge: three test-assertion
fixes and two documentation corrections against spec/plan drift.

1. `18_resolve_contacts.test.sql` (~line 63-69): the "resolving unknown
   numbers creates no people rows" count scoped only the two known fixture
   hashes, omitting the unknown number's own hash (`+919120000099`), making
   it vacuous. Added the third hash to the `in (...)` list. Expected count
   unchanged at `1` — `+919120000001` (Known Friend) has a people row,
   `+919120000002` (Opted Out) was suppressed and its people row
   hard-deleted by `private.suppress_person` (confirmed in
   `supabase/migrations/20260822000004_people_graph.sql:203`), and
   `+919120000099` has no people row yet at that point in the test.

2. `17_reminders.test.sql` (~line 159-164): the `lives_ok` on
   `public.rpc_next_reminder_batch(1)` ran immediately after the lease-expiry
   assertion had claimed the outbox's only row, so the call returned zero
   rows and the assertion proved only that the function exists. Its comment
   also falsely claimed return-type drift "fails at runtime, not at DDL
   time" — false for a `language sql` function, whose body is checked at
   `CREATE OR REPLACE FUNCTION` time, which `supabase db reset` already
   exercises. Replaced the comment with an accurate one, seeded a fresh
   eligible outbox row (recipient `remindme`, subject `Leap Friend`, offset
   7, occasion `2027-02-28` — a distinct key so it cannot collide with the
   already-claimed row under `notification_outbox_once`), and changed the
   assertion to `isnt_empty` on `select outbox_id from
   public.rpc_next_reminder_batch(1)`. The very next block unconditionally
   `delete from private.notification_outbox;` before its own enqueue, so no
   extra cleanup was needed.

3. `17_reminders.test.sql` (~line 182-189, wording only): reworded the
   leap-year T-1 assertion's comment and description. The old text claimed
   it proved "nothing double-fires" and the birthday is "queued once," but
   the plain-birthday and Feb-28-fallback match arms are OR'ed inside one
   predicate, so a single row can never falsify double-firing. Reworded to
   state what the assertion actually proves: that in a leap year, T-1
   (2028-02-28) matches the real Feb 29 via the plain arm rather than the
   Feb-28 fallback arm. SQL and expected value (`'1 row(s)'`) unchanged.

4. Documentation drift: `docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md`
   §4.3 item 1 still described a `celebrations_select_incoming` RLS policy
   that was replaced during the review wave by `public.my_celebrates()` (a
   `security definer` function returning only `celebrator_profile_id` /
   `celebrator_person_id`) — confirmed against
   `supabase/migrations/20260824000002_celebrations_incoming.sql`, whose
   header comment states the rejection reason: RLS is row-level, so a policy
   exposing incoming edges would also have exposed the celebrator's private
   `nickname` and the `source` revealing how they were found. Rewrote item 1
   to describe the function and the rejection reason, and updated the
   testing-section bullet (~line 215) that referenced the policy by name.
   `docs/superpowers/plans/2026-08-24-m1-phase1-data-and-backend.md`'s Phase 1
   Definition of Done said `Tests=162`; corrected to the verified `168`
   (other in-progress `Expected:` figures earlier in the plan were left
   alone — they are historical checkpoints from earlier tasks, not the final
   gate, and were out of scope for this fix).

### Verification

```
supabase db reset && supabase test db
...
All tests successful.
Files=19, Tests=168,  1 wallclock secs (...)
Result: PASS
```

Targeted re-runs: `17_reminders.test.sql` alone → `Files=1, Tests=21, PASS`;
`18_resolve_contacts.test.sql` alone → `Files=1, Tests=9, PASS` (both
unchanged assertion counts, confirming no assertions were added or removed).

Standing guards re-confirmed individually: `01_private.test.sql` →
`Files=1, Tests=9, PASS`; `11_rls_coverage.test.sql` → `Files=1, Tests=3,
PASS`.

`supabase db lint --level warning`: all findings confined to `extensions.*`
(pgTAP's own internal functions); nothing in `public` or `private`.

Commits:
- `2332c11` — fix(tests): strengthen three weak reminder/contact assertions
- `fafd61c` — docs(m1): fix spec/plan drift from the review-wave redesign

### Concerns

None outstanding. All four fixes applied as specified; none required
deviating from the brief's instructions.
