# Task 6 report: `add_celebrations` Edge Function

## Files created

- `supabase/functions/add_celebrations/index.ts` — implemented verbatim from the brief.
- `supabase/functions/add_celebrations/deno.json` — implemented verbatim from the brief.

No deviations from the brief's Step 1 code were made. Points 2–8 of the parent
instructions were evaluated (see "Findings" below); none required changing
the implementation.

## Pre-work: read the sibling functions (point 7)

Read `supabase/functions/resolve_contacts/index.ts` and
`supabase/functions/claim_profile/index.ts` before writing anything.

`claim_profile`'s error branch inspects `error.code`:

```ts
if (error.code === "23505") {
  return new Response(
    JSON.stringify({ error: "profile already claimed a different number" }),
    { status: 409, headers: { "content-type": "application/json" } },
  );
}
```

It does this because `claim_profile` is a single-item operation: one RPC
call maps to one HTTP response, so a caller-state failure (already claimed
a different number) can and should become a distinct 4xx.

**Conclusion for `add_celebrations`:** no analogous per-contact status-code
mapping is warranted, and I did not add one.

- `add_celebrations` is a batch endpoint: one HTTP response covers up to 500
  independent RPC calls. The HTTP status is necessarily whole-request
  (200 on any completed batch); it cannot carry one contact's error code
  without misrepresenting the other 499 outcomes. Per-contact outcomes are
  already carried out-of-band in `results[i].status`, which is the correct
  place for this information, not the response's HTTP status.
- The one caller-state error `private.add_celebration` can raise
  (`raise exception 'you cannot celebrate yourself'`, migration
  `20260827000003_add_celebration.sql`) has no distinct SQLSTATE — it's a
  plain `raise exception`, which surfaces as generic `P0001`. Unlike
  `claim_profile`'s `23505` (unique_violation, a stable, code-based
  signal), distinguishing this case would require matching on
  `error.message` text, which is fragile (message text isn't a public
  contract) and unnecessary: the loop already puts it into
  `results[i].status = "failed"`, which is a true and sufficient signal
  for the app to skip that one contact and move on. I considered adding a
  more specific status value (e.g. `"self"`) instead of the generic
  `"failed"` so the client could show a nicer message, but the brief does
  not ask for this and it would mean parsing `error.message`, which
  point 8 already tells us to keep out of logs — I chose not to add that
  string-matching surface. `"failed"` stands.

## Step 2: refusal paths

Command run (`bash /private/tmp/.../scratchpad/step2.sh`, invoking
`supabase functions serve add_celebrations --no-verify-jwt &` then a 6s
sleep):

```bash
curl -s -X GET  http://127.0.0.1:54321/functions/v1/add_celebrations
curl -s -X POST http://127.0.0.1:54321/functions/v1/add_celebrations \
  -H 'Authorization: Bearer x' -H 'content-type: application/json' \
  -d '{"contacts":"nope"}'
```

Output:

```
{"error":"method not allowed"}
{"error":"contacts must be {phone, name}[]"}
```

Matches the brief's expectation exactly.

## Step 3: happy path with a suppressed contact

```bash
PUB=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH
curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' -H "apikey: $PUB" \
  -H 'content-type: application/json' -d '{"phone":"+919999000003"}'
# => {}

TOKEN=$(curl -s -X POST 'http://127.0.0.1:54321/auth/v1/verify' -H "apikey: $PUB" \
  -H 'content-type: application/json' \
  -d '{"phone":"+919999000003","token":"123456","type":"sms"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

docker exec supabase_db_birthday_app psql -U postgres -d postgres -c \
  "select private.suppress_person(private.upsert_person('+919240000002','Gone'));"
# =>  suppress_person
#     -----------------
#
#     (1 row)

curl -s -X POST http://127.0.0.1:54321/functions/v1/add_celebrations \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"contacts":[{"phone":"+919240000001","name":"Real Friend","birth_month":5,"birth_day":9},{"phone":"+919240000002","name":"Gone"}]}'
```

Response:

```json
{"added":1,"skipped":1,"results":[{"phone":"+919240000001","person_id":102,"status":"added"},{"phone":"+919240000002","person_id":null,"status":"suppressed"}]}
```

Matches the brief's expectation: `added: 1`, `skipped: 1`, second result
`status: "suppressed"`, `person_id: null`.

## Point 2: replacement verification query

The brief's Step 3 verification (`where pr.handle like 'u%'`) was not run
as-is — it depends on incidental handle naming, not on the actual caller.
Instead I resolved the caller's profile id from the JWT `sub` claim, cross-
checked it against `auth.users` by phone, then counted edges scoped to
exactly that profile id.

Decoding the JWT `sub`:

```bash
python3 -c "
import json, base64
tok = open('/private/tmp/.../scratchpad/token.txt').read().strip()
payload = tok.split('.')[1]
payload += '=' * (-len(payload) % 4)
data = json.loads(base64.urlsafe_b64decode(payload))
print(data.get('sub'))
print(data.get('phone'))
"
```

Output:

```
05f49e35-9224-454c-8628-2714aadf94ff
919999000003
```

Cross-check against `auth.users` and the count query actually run
(`docker exec -i supabase_db_birthday_app psql -U postgres -d postgres < step3_verify.sql`):

```sql
-- Cross-check: resolve the caller's profile id from auth.users by phone,
-- and confirm it matches the JWT sub claim.
select id, phone from auth.users where phone = '919999000003';

-- Count celebration edges for exactly that caller's profile id (from JWT sub).
select count(*) from public.celebrations c
 where c.celebrator_profile_id = '05f49e35-9224-454c-8628-2714aadf94ff';
```

Output:

```
                  id                  |    phone
--------------------------------------+--------------
 05f49e35-9224-454c-8628-2714aadf94ff | 919999000003
(1 row)

 count
-------
     1
(1 row)
```

`auth.users.id` matches the JWT `sub` exactly, and exactly one celebration
edge exists for that caller — the "added" contact only, not the suppressed
one. This is a stronger check than the brief's `handle like 'u%'` query
because it is scoped to the specific caller by verified identity, not by an
incidental naming convention that could coincidentally match unrelated rows.

## Extra verification: 100-contact batch timing

Generated 100 contacts with unique phone numbers (`+9193000000` ..
`+9193000099`), all unsuppressed, same caller/token from Step 3:

```bash
python3 -c "
import json
contacts = [{'phone': f'+9193{str(i).zfill(6)}', 'name': f'Contact {i}'} for i in range(100)]
print(json.dumps({'contacts': contacts}))
" > batch100.json

time curl -s -X POST http://127.0.0.1:54321/functions/v1/add_celebrations \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  --data-binary @batch100.json -o batch100_resp.json -w "\nHTTP %{time_total}s\n"
```

Output:

```
HTTP 2.078527s

real	0m2.104s
user	0m0.007s
sys	0m0.011s
```

Response body confirmed all 100 succeeded:

```
added: 100 skipped: 0 total results: 100
```

**Measured: ~2.08s wall clock for 100 contacts (~20.8ms/contact serial RPC
round trip).**

**Judgment on the 500 cap:** linearly extrapolating, 500 contacts would take
roughly 5x this, ~10.4s, all on a single blocking HTTP call the import
screen awaits synchronously (per the brief: "The loop awaits one RPC round
trip per contact, serially"). This is local-loopback timing with no network
latency, no cold start, and a warm database — a real deployment (managed
Postgres + Edge Function cold starts + real network RTT) would very likely
be slower per round trip, not faster. ~10 seconds of a screen doing nothing
visible is long enough to read as "hung" or "frozen" to a user who just
tapped "Import 500 contacts," especially with no progress indicator in the
per-contact-serial design shown here. This is a plausible UX concern worth
flagging to whoever owns the import screen: either the screen needs a
progress indicator that updates as results stream in (would require
chunking the request or switching to SSE/streaming rather than one
big synchronous POST), or the batch should be chunked client-side with
incremental progress feedback. I did not change the Edge Function to
address this — the brief's shape (one request, one response) is what was
asked for, and reshaping it into a streaming/chunked design is a larger
decision than this task's scope — but it is a real finding for the next
phase or a follow-up ticket.

## Step 4: suite and commit

```bash
kill <serve pid>
supabase db reset
supabase test db
```

`db reset` output (tail): applied all migrations including
`20260827000003_add_celebration.sql`, seeded, restarted containers,
"Finished supabase db reset on branch main."

`test db` output:

```
...
/Users/admin1/.../supabase/tests/database/21_add_celebration.test.sql ...... ok
All tests successful.
Files=22, Tests=185,  3 wallclock secs (...)
Result: PASS
```

Matches the corrected expectation from the parent instructions
(`Files=22, Tests=185, PASS` — not the brief's stale `Tests=182`; this task
adds no new pgTAP tests, so the count is unchanged from before this task's
work, at 185).

Commit:

```bash
git add supabase/functions/add_celebrations/
git commit -m "feat(functions): add celebrations for picked contacts"
```

Result: commit `f900cab`, 2 files changed, 129 insertions.

## Notes on parent instructions followed

- Did not name any shell variable `UID`; used `TOKEN`, `PUB`, `PROFILE`-style
  values only where needed (decoded the profile id directly from the JWT
  rather than storing it in a variable named `UID`).
- One long compound command (heredoc + chmod + bash all in one call) was
  refused by the worktree guard as "too complex" on the first attempt at
  writing the timing script; split into separate `Write` + `chmod` + `bash`
  calls per the parent's point 4, which succeeded.
- Never logged a contact (phone/name) anywhere in this report or in any
  script's console output — only `error.message`, which the implementation
  already does not need to exercise in these successful runs.

---

# Fix round 1 (code review: request changes, 1 Critical)

## C1 (Critical) — E.164 guard closing the self-celebration bypass

New migration `supabase/migrations/20260827000004_phone_e164_guard.sql`
(existing migrations untouched). Added `private.assert_e164(p_phone text)
returns text` — `language plpgsql`, `security definer`,
`set search_path = ''`, raises `using errcode = '22023'` when
`p_phone !~ '^\+[1-9][0-9]{6,14}$'`, otherwise returns it unchanged.
Revoked from `public, anon, authenticated`.

Wired into the three write paths via `create or replace`, each carrying its
existing body across unchanged apart from one added call:

- `private.upsert_person` — `v_hash text := private.phone_hash(p_phone);`
  became `v_hash text := private.phone_hash(private.assert_e164(p_phone));`
  in the `declare` block (this validates before the hash is computed,
  ahead of every branch that uses it: suppression check, existing-row
  update, insert).
- `private.claim_person` — same one-line change to its `v_hash` initializer.
- `private.add_celebration` — added `p_phone := private.assert_e164(p_phone);`
  as the first line of the function body, ahead of its call into
  `upsert_person`. Redundant with `upsert_person`'s own guard today, kept as
  defence-in-depth per the review's explicit instruction to wire it into
  all three named functions directly, not rely on transitivity through one.

`private.resolve_contacts` was deliberately NOT touched — confirmed by test
(see below) that it still returns cleanly, no raise, on malformed input.

Every `revoke`, `security definer`, `set search_path = ''`, and return type
was hand-checked against the pre-fix definitions after the `create or
replace`; the allowlist re-verification at the end of this section confirms
none were dropped.

## I2 — self-celebration raise now carries a stable SQLSTATE

In the same migration, `private.add_celebration`'s
`raise exception 'you cannot celebrate yourself';` became
`raise exception 'you cannot celebrate yourself' using errcode = 'P0002';`
(reviewer's correction accepted — this repo already establishes the
`using errcode = '...'` pattern in three other migrations, so message-text
matching was never actually the only option; my original report's reasoning
on this point was wrong, as the review said).

Updated the existing assertion in `supabase/tests/database/21_add_celebration.test.sql`
(the only place that raise's SQLSTATE was pinned) from expecting `'P0001'`
to expecting `'P0002'`, and added a sentence to its comment explaining why.
No new assertion was added there since `throws_ok`'s second argument already
asserts the SQLSTATE — updating its expected value both fixes the test and
serves as "a pgTAP assertion that the raise carries that SQLSTATE."

## C1b — Edge Function maps the new error codes to per-contact statuses

`supabase/functions/add_celebrations/index.ts`: in the `error` branch,
before falling through to the generic `"failed"` status:

```ts
if (error.code === "22023") {
  results.push({ phone: c.phone, person_id: null, status: "invalid" });
  failed++;
  continue;
}
if (error.code === "P0002") {
  results.push({ phone: c.phone, person_id: null, status: "self" });
  failed++;
  continue;
}
```

## I3 — `added` overcounted duplicate phones within one batch

Chose **dedupe by phone before the loop** over counting distinct
`person_id`s. Reasoning: it's simpler (one RPC round trip per unique phone,
not two calls reconciled after the fact), it removes the wasted round trip
entirely for large address books with internal duplicates (relevant given
the batch's round-trip cost measured in the original report), and it makes
`added + skipped + failed == results.length` trivially true — every
processed entry lands in exactly one bucket, with no separate "this succeeded
but don't count it again" bookkeeping needed.

Consequence, stated explicitly in the code comment: `results.length` (and
therefore `added + skipped + failed`) equals the number of **unique**
phones in the request, not the raw `contacts.length`, whenever the request
itself contains a duplicate phone. This is deliberate — treating a repeated
phone as a second independent contact is the exact overcounting bug being
fixed, so the invariant is anchored to the deduped count rather than the
raw input length.

## I4 — added a `failed` counter distinct from `skipped`

`skipped` now means suppressed only (`data === null` from the RPC).
Everything from the `error` branch — the new `"invalid"` and `"self"`
per-contact statuses, and the generic `"failed"` fallback — increments a new
`failed` counter instead. All pre-existing response keys (`added`,
`skipped`, `results`) are unchanged in shape; `failed` is additive.

## M5 — bounded `display_name`

Added `MAX_NAME_LENGTH = 128`. Before calling the RPC, each contact's name
is checked: `c.name.trim().length === 0` (empty or whitespace-only) or
`c.name.length > 128` both produce `status: "invalid"` and increment
`failed`, with no RPC round trip spent on it.

## M6 — guard order

Reordered the top-of-request checks: `Array.isArray(contacts)` (cheap type
check) → `contacts.length > MAX_BATCH` (cheap size check) → the
`contacts.some(...)` per-element shape walk. A body large enough to trip
`MAX_BATCH` is now rejected before any element is inspected.

## Do not change — PII logging

Left `console.error("rpc_add_celebration failed", error.message)` exactly as
it was; added a comment on that line stating why: `error.message` is safe,
`error.details` (which does carry `display_name` for a constraint
violation) is never logged, and nobody should "simplify" this by logging the
whole `error` object.

## Verify

**Suite**, after `supabase db reset && supabase test db`:

```
.../22_phone_e164_guard.test.sql ..... ok
All tests successful.
Files=23, Tests=197,  1 wallclock secs (...)
Result: PASS
```

`185 + 12 = 197` — the new test file's `plan(12)` accounts for the whole
delta; no other file's assertion count changed (only 21's *expected value*
changed, not its count).

**Bypass repro, independently re-run** (own scenario, own phone numbers,
not copy-pasted from the review) via a `DO` block with an exception handler
so each attempt's outcome is a clean stdout row rather than raw
stderr/psql-error output (a first attempt using bare `\echo` +
per-statement `ERROR:` output showed stdout/stderr interleaving artifacts
under `docker exec ... | psql` piping and was discarded in favour of this
version):

```
     form            |                        outcome
---------------------------+-------------------------------------------------------
 E164 (+919999600003)      | blocked -> P0002 you cannot celebrate yourself
 spaced (+91 99996 00003)  | blocked -> 22023 phone number must be in E.164 format
 unprefixed (919999600003) | blocked -> 22023 phone number must be in E.164 format

                check                | value
--------------------------------------+-------
 edges owned by reprouser2           |     0
 distinct people rows for reprouser2 |     1
```

All three forms now raise; zero self-edges; the human is still exactly one
`people` row (no fork).

**Happy path re-run** (fresh OTP token for test number 3, one real contact,
one suppressed contact):

```
{"added":1,"skipped":1,"failed":0,"results":[
  {"phone":"+919240000011","person_id":56,"status":"added"},
  {"phone":"+919240000012","person_id":null,"status":"suppressed"}
]}
```

**Combined scenario** — a duplicate phone, a malformed phone, the caller's
own claimed number, a whitespace-only name, and an over-length name, sent
in one batch of 6 contacts (after first calling `claim_profile` for this
session so the self-celebration guard is armed):

```
{
  "added": 1,
  "skipped": 0,
  "failed": 4,
  "results": [
    {"phone": "+919240000021", "person_id": 58, "status": "added"},
    {"phone": "919240000022", "person_id": null, "status": "invalid"},
    {"phone": "+919999000003", "person_id": null, "status": "self"},
    {"phone": "+919240000023", "person_id": null, "status": "invalid"},
    {"phone": "+919240000024", "person_id": null, "status": "invalid"}
  ]
}
```

6 input contacts (two with the same phone `+919240000021`) produced 5
results — the duplicate collapsed into a single `"added"` entry — and
`added(1) + skipped(0) + failed(4) == 5 == results.length`.

**Allowlists**, re-run directly rather than trusted from the suite alone:

```
 schema  |                                   allowlist
---------+--------------------------------------------------------------------------------
 private | can_see_person,is_staff,my_person_id
 public  | my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token
```

Both unchanged from before this fix round — `private.assert_e164` does not
appear (its revoke held), and no public wrapper was added. This is also
independently confirmed by `01_private.test.sql` and `11_rls_coverage.test.sql`
both passing in the full suite run above.

## Disagreements

None. C1 was reproduced independently before being trusted (see the bypass
repro above), and every other finding either had a defensible single
implementation the review already pointed at (I2's `errcode` pattern, C1b's
`error.code` branch) or an explicit choice-with-reasoning point (I3, where
dedupe-before-loop was chosen and justified above). I2's original reasoning
in my first report was factually wrong, as the review demonstrated with
three counter-examples already in this codebase — noted here rather than
argued against.
