# Task 7 report: the `delete_account` Edge Function

## Files created

- `supabase/functions/delete_account/index.ts` — verbatim from the brief.
- `supabase/functions/delete_account/deno.json` — verbatim from the brief.
- `supabase/tests/database/23_delete_account.test.sql` — new (my judgement call, point 6 below). `plan(16)`.

## Corrections applied per the task instructions (not from the brief itself)

- Expected suite totals corrected from the brief's stale `Files=22, Tests=182` to
  `Files=23, Tests=197` as the pre-existing baseline (00 through 22, including
  `22_phone_e164_guard.test.sql` which the brief predates), then `Files=24,
  Tests=213` after adding `23_delete_account.test.sql` (`plan(16)`).
- Used strict E.164 phone numbers everywhere (`private.assert_e164` now
  raises `22023` on anything else).

## Step 1: Write the function

Both files created exactly as specified in the brief. See file paths above.

## Step 2: Serve it and exercise the refusal paths

```
$ supabase functions serve delete_account --no-verify-jwt &
$ sleep 6
$ curl -s -X GET  http://127.0.0.1:54321/functions/v1/delete_account
{"error":"method not allowed"}
$ curl -s -X POST http://127.0.0.1:54321/functions/v1/delete_account
{"error":"missing authorization"}
```

Matches expected output exactly.

## Step 3: Prove the cascade behaves as documented

```
PUB=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' -H "apikey: $PUB" \
  -H 'content-type: application/json' -d '{"phone":"+919999000001"}' >/dev/null
TOKEN=$(curl -s -X POST 'http://127.0.0.1:54321/auth/v1/verify' -H "apikey: $PUB" \
  -H 'content-type: application/json' \
  -d '{"phone":"+919999000001","token":"123456","type":"sms"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

```
TOKEN acquired: eyJhbGciOiJFUzI1NiIs...
--- claim_profile ---
{"person_id":53}
--- add_celebrations ---
(piped to /dev/null per the brief; new response shape confirmed separately, see below)
--- before ---
before: profiles=1 edges=1 people=2
--- delete_account call ---
{"deleted":true}
--- after ---
after:  profiles=0 edges=0 people=2 unclaimed=2
```

Contrast: `profiles 1 -> 0`, `edges 1 -> 0`, `people` unchanged at `2`, and
`unclaimed` rises from (implicitly) 1 to `2` — the deleted user's own person
row plus the never-claimed "Cascade Friend" contact they had celebrated. This
matches the brief's documented cascade table exactly: profiles and outgoing
edges drop; people does not drop; the deleter's own row survives unclaimed.

(Confirmed separately: `add_celebrations`' response is now
`{"added":1,"skipped":0,"failed":0,"duplicates":0,"results":[{"phone":"+919250000001","person_id":54,"status":"added"}]}`
— consistent with point 3 of the task instructions; it did not affect this
step since the brief pipes it to `/dev/null`.)

## Extra verification (beyond the brief)

### Cannot aim deletion at anyone else

Created two users X and Y via OTP (+919999000002 / +919999000003), each
claimed their profile. X then called `delete_account` with `Authorization:
Bearer <X's token>` and a JSON body naming Y's user id under several
plausible keys (`id`, `user_id`, `target_id`, `profile_id`):

```
X id = 0bb43dad-f8f6-461a-ac31-75b0080b714f
Y id = c29926a4-e03b-4ab4-8847-6b45e6bd2bc1
--- claim profiles for X and Y ---
{"person_id":55}
{"person_id":56}
--- before: profiles table has both X and Y? ---
X exists=true Y exists=true
--- X calls delete_account, sending a body that NAMES Y's id under several plausible keys ---
{"deleted":true}
--- after: who actually got deleted? ---
X exists=false Y exists=true
```

The body is completely ignored: the caller (X, identified from the session)
was deleted; the named target (Y) survived untouched. Same class of check
that caught a real hole in `claim_profile`.

### Other people's edges survive, now pointing at an unclaimed person

Re-signed up on the phone from Step 3 (+919999000001) as user Z, which
reclaimed the existing unclaimed person row (`id=53`) left behind by Step 3.
A separate user W (+919999000002, freed by the previous test) then imported
Z's phone number as a contact, creating an edge `W -> person(53)`. Z's
account was then deleted:

```
Z id = d291a7d8-f123-491d-813d-65852bcb5008 (re-signed-up on a phone from Step 3; should reclaim the existing unclaimed person row)
--- claim profile for Z ---
{"person_id":53}
--- W celebrates Z's phone number ---
{"added":1,"skipped":0,"failed":0,"duplicates":0,"results":[{"phone":"+919999000001","person_id":53,"status":"added"}]}
person_id(Z)=53   W id=1727a9a7-93f1-4386-8ba9-a88ec4083130
before: w_edge_to_z_exists=true
--- delete Z's account ---
{"deleted":true}
--- after: W's edge still exists, and person row is now unclaimed ---
after: w_edge_to_z_exists=true person_row_survives=true now_unclaimed=true
```

W's celebration edge to `person(53)` survived Z's deletion untouched, and
`person(53).profile_id` is now `null` — exactly the documented behaviour,
turned into an exact number rather than prose.

## Step 4: Stop the server, confirm the suite

```
$ kill %1   # (PID 49217, confirmed dead via ps)
$ supabase db reset
... (all 20 migrations applied cleanly) ...
Finished supabase db reset on branch main.

$ supabase test db
... all files ok ...
/Users/admin1/Desktop/Projects/birthday_app/.claude/worktrees/m1-phase2a-backend/supabase/tests/database/23_delete_account.test.sql ....... ok
All tests successful.
Files=24, Tests=213,  1 wallclock secs
Result: PASS
```

Also ran `supabase db lint --level warning` as an end-of-phase sanity check
(part of the Phase 2a DoD): every reported warning is inside
`extensions.*` functions (`extensions._get_server_privs`, etc.) —
unrelated to this task, matching the DoD's expectation.

## Point 6 — judgement call: added `23_delete_account.test.sql`

Decision: **added the pgTAP file.**

Reasoning: the cascade is pure database behaviour (FK `on delete`
actions), which pgTAP can pin exactly — unlike the HTTP layer, which
needs a running Edge Function and cannot be part of `supabase test db`.
The brief's own Step 3 proof is a shell transcript that no CI or future
migration re-checks; a regression (e.g. someone flips `people.profile_id`
off `ON DELETE SET NULL`, or adds a table with an unguarded
`ON DELETE CASCADE` from `profiles`, or forgets FK cleanup for a new
table) would only be caught by a human re-running curl by hand. The new
test simulates what `auth.admin.deleteUser` ultimately does at the SQL
level (`delete from auth.users where id = ...`, which drives every FK
below `public.profiles`) and asserts, in one transaction that rolls back:

- before: the deleter has 1 outgoing celebration, 1 authored wish, 1
  device token, 1 block row, 1 queued `notification_outbox` row, and a
  bystander already has 1 edge into the deleter's person row.
- after deletion: all six of those first counts go to 0; the deleter's
  own `people` row survives (count 1) with `profile_id` now `null`; the
  bystander's edge into that row survives untouched (count still 1); and
  an unrelated person row (a contact the deleter had imported) is
  untouched (count still 1).

New totals: `plan(16)` in the new file, suite totals now
`Files=24, Tests=213, PASS`.

One real defect surfaced while writing the test (not a defect in
`delete_account` itself): the setup originally inserted the
deleter-blocks-bystander row *before* having the bystander celebrate the
deleter's person. `private.guard_celebration` correctly rejected that
insert with "this person has blocked you" — the block row I'd created
made the subsequent celebration attempt genuinely invalid, exposing a
bug in my own test setup, not in the migrations or the function under
test. Fixed by reordering: the bystander's celebration now happens before
the block is inserted.

## Concerns / known limits (carried forward from the brief)

- `gifts.sender_profile_id` is `ON DELETE RESTRICT`. No gifts exist in M1
  so deletion succeeds today; M3 must decide whether a sender's gifts are
  reassigned, anonymised, or deletion is refused. Comment preserved
  verbatim in `index.ts` as the record of this.

---

# Review round 2 response

Findings F1-F6 evaluated against the codebase. All accepted; F2's "known limit"
list and F3's address-survival note were genuine gaps, F4's vacuous assertion
was a real bug in my own test, F5's catalog pins and blocks.blocked_profile_id
behavioural test were worth adding, F6's documentation gaps were real.

## F1 (Important) — accepted, fixed with a new migration

Verified the premise directly: `private.claim_person`'s upsert does
`display_name = coalesce(v_name, public.people.display_name)` and the
equivalent for the three birth columns, where `v_name`/`v_month`/`v_day`/
`v_year` come from `select ... from public.profiles where id = p_profile_id`
— i.e. the PROFILE's own values win whenever they are non-null, not merely
fill blanks. `profiles_sync_person` (20260824000001, `birthday_parts.sql`)
re-syncs the same columns on every profile edit thereafter. And
`private.enqueue_reminders` (20260824000006) gates only on
`p.birth_month is not null` with no `profile_id` check. The finding is
correct: a claimed person row surviving deletion carries the deleted user's
own real name and real birthday, and keeps generating reminders forever.

New migration `supabase/migrations/20260827000005_scrub_on_delete.sql`:
`private.scrub_person_on_profile_delete()`, a `before delete on
public.profiles` `security definer` trigger that, for the profile's linked
`people` row: deletes any `private.notification_outbox` row where that
person is the *subject* (not just cascading rows where the deleted user was
the *recipient*, which the existing FK already handled), deletes the
person's `public.addresses` rows (F3), and updates the row to
`display_name = 'Deleted user'`, `birth_month/day/year = null`. Row id and
`phone_e164_hash` are untouched, so every inbound celebration edge survives.

**Ordering, verified rather than assumed**: Postgres enforces FK `ON DELETE`
actions (including `people.profile_id`'s `SET NULL`) via system RI triggers
that always fire `AFTER ROW` on the referenced table. A user-defined `BEFORE
DELETE` trigger on `profiles` therefore runs strictly first, while
`people.profile_id` still equals `OLD.id`. Confirmed by direct repro against
the live database (see "Verify" below) — the lookup by `profile_id = old.id`
inside the trigger worked correctly.

Also updated `index.ts`'s header comment to describe the scrub and its
consequences for the app's own documentation.

## F2 (Important) — accepted

Queried `pg_constraint` for every FK into `public.profiles`; confirmed exactly
two `ON DELETE RESTRICT`: `gifts_sender_profile_id_fkey` and
`address_access_log_staff_profile_id_fkey`. Added the second to the KNOWN
LIMIT comment in `index.ts`, including the reviewer's point that it is worse
than the gifts case because `address_access_log` is deliberately immutable —
no reassign/anonymise escape exists for it the way one might for gifts.

## F3 (Important) — accepted

Confirmed `addresses.owner_person_id references public.people(id) on delete
cascade` — zero rows in M1 (addresses is M3), but the surviving person row
means a deleted user's own delivery address would survive too, once it
exists. Took the reviewer's ruling: the scrub trigger deletes
`public.addresses` rows for that person id in the same transaction as the
name/birthday scrub. Documented in both the migration and `index.ts`.

One correction to the finding's premise: `notification_outbox` does **not**
denormalise `subject_name` — `private.next_reminder_batch` joins
`public.people` live and reads `display_name` at drain time, there is no
copied column. So an already-queued reminder cannot leak the deleted user's
*real* name even without deleting it (it would render with whatever
`display_name` the row holds at drain time, which the scrub sets to the
placeholder anyway). The reviewer's fix — delete those rows — is still
correct on separate grounds: a "Deleted user's birthday is today" push about
nobody's actual birthday is exactly the harm the migration exists to stop,
so those rows are deleted regardless of the denormalisation question being
moot.

## F4 (Minor) — accepted, fixed

Rewrote the vacuous `is(profile_id, null)` assertion as
`is((select count(*)::int from people where id = X and profile_id is null), 1)`,
which cannot pass on a missing row. Confirmed this discriminates in the same
live-mutation pass used for F1 (see "Verify").

## F5 (Minor) — accepted

`pg_constraint.confdeltype` for all ten FKs into `profiles`:

```
address_access_log.staff_profile_id_fkey        r
blocks.blocked_profile_id_fkey                   c
blocks.blocker_profile_id_fkey                   c
celebrations.celebrator_profile_id_fkey          c
device_tokens.profile_id_fkey                    c
gift_events.actor_profile_id_fkey                n
gifts.sender_profile_id_fkey                     r
people.profile_id_fkey                           n
notification_outbox.recipient_profile_id_fkey    c
wishes.author_profile_id_fkey                    c
```

Added three catalog assertions (`confdeltype` = `'r'`, `'r'`, `'n'`) for the
three FKs that need a gift to exercise behaviourally: `gifts`,
`address_access_log`, `gift_events`. Also added the behavioural
`blocks.blocked_profile_id` test the reviewer suggested: a second block row
with the deleter as the *blocked* party (not just as blocker, already
covered) — before/after count confirms it cascades away too.

## F6 (Minor) — accepted, documented only

Added both notes verbatim to `index.ts`'s header comment: the JWT-validity
window (signature-valid until `jwt_expiry`, practically inert because
`auth.sessions` cascades and every RLS policy keys off a now-missing
profile, but unfixable with signed JWTs), and the concurrent-double-call
race (loser gets `500 "delete failed"` from a 404 on an already-deleted
user, even though the account IS gone — a client must treat that 500 as
"re-check", not "assume failure").

## Verify

```
$ supabase db reset && supabase test db
...
Files=24, Tests=224
Result: PASS
```

(197 baseline + 27 in the rewritten `23_delete_account.test.sql`, up from
`plan(16)` to `plan(27)`.)

**Residue repro, before/after the fix** (direct psql, mirrors a real
claim-then-delete flow: profile gets a self-entered name/birthday, claims a
number, a bystander celebrates it, account is deleted):

```
--- BEFORE deletion ---
 people row: name=Self Entered Name month=4 day=15 year=1990
--- AFTER deletion ---
 people row: name=Deleted user month=NULL day=NULL year=NULL | profile_id null? true
 bystander edge survives: 1
```

**Proof the new no-reminder assertion (and the scrub assertions) actually
discriminate** — dropped the trigger live via psql, migration file
untouched:

```
$ docker exec supabase_db_birthday_app psql -U postgres -d postgres \
    -c "drop trigger profiles_scrub_person_before_delete on public.profiles;"
DROP TRIGGER

$ docker exec -i supabase_db_birthday_app psql -U postgres -d postgres \
    < supabase/tests/database/23_delete_account.test.sql
...
not ok 17 - after: the reminder someone else had queued about them is gone too
#         have: 1
#         want: 0
not ok 20 - after: the surviving person row is scrubbed to a placeholder name with no birthday
#         have: Self Entered Name|4|15|1990
#         want: Deleted user|NULL|NULL|NULL
 enqueue_reminders
-------------------
                 1
not ok 21 - after: enqueue_reminders queues nothing for the scrubbed person even on their old birthday
#         have: 2
#         want: 0
# Looks like you failed 3 tests of 27
```

`enqueue_reminders` actually inserting rows once the birthday was live again
is the harm F1 describes, caught live. Restored via `supabase db reset`
(migration file was never touched) and reran:

```
$ supabase db reset && supabase test db
...
Files=24, Tests=224
Result: PASS
```

**Standing allowlists, unchanged:**

```
private: can_see_person,is_staff,my_person_id
public:  my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token
```

**`supabase db lint --level warning`**: 27 function groups reported warnings,
0 outside `extensions.*` (checked programmatically against the JSON output).
