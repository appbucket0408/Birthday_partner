# Task 5 report — the `claim_profile` Edge Function

**Status:** DONE. Commit `58bed59`. Suite `Files=22, Tests=185, PASS` (adds no pgTAP).

## Provenance note

The dispatched implementer wrote both files verbatim from the brief and cleared
Steps 1-2, then died to an API rate limit partway through Step 3. The controller
finished Steps 3-4 directly rather than re-dispatching. The committed code is the
implementer's, unmodified; every verification below was run by the controller.

## Files

- `supabase/functions/claim_profile/index.ts` — brief's code, verbatim.
- `supabase/functions/claim_profile/deno.json` — brief's code, verbatim.

## Step 2 — refusal paths

```
$ curl -s -X GET  http://127.0.0.1:54321/functions/v1/claim_profile
{"error":"method not allowed"}
$ curl -s -X POST http://127.0.0.1:54321/functions/v1/claim_profile
{"error":"missing authorization"}
```

## Step 3 — happy path, two distinct sessions

```
--- +919999000002 ---
{"person_id":107}
--- +919999000003 ---
{"person_id":108}
```

Distinct ids from distinct sessions.

## Step 3 — the rows are linked to the right numbers

```
 id  | linked | is_002 | is_003 | unprefixed_002
-----+--------+--------+--------+----------------
 107 | t      | t      | f      | f
 108 | t      | f      | t      | f
```

`unprefixed_002 = f` is the load-bearing column: it proves the `+` normalisation
is doing real work. GoTrue stores `auth.users.phone` as `919999000002`; had the
function passed that through unprefixed, it would have hashed to a different
value, minted a NEW person row, and orphaned every celebration edge already
pointing at the user's real number. This assertion is what catches that.

## Step 3 — the security property, stated directly

Each claimed row must hash the phone that same session verified:

```
 id  | session_phone | row_matches_session
-----+---------------+---------------------
 107 | 919999000002  | t
 108 | 919999000003  | t
```

Joined `people.profile_id -> auth.users`, so this is the binding itself, not a
restatement of the call order.

## Extra — a body-supplied phone is ignored

Signed in as `+919999000001`, sending a body naming someone else's number:

```
attacker session = +919999000001, body claims +919999000003 (person 108)
{"person_id":109}
```

The attacker gets their OWN row (109), not 108. Had the function honoured the
body, they would have inherited every celebration edge pointing at `...003`.

## Step 4 — suite

```
$ supabase db reset && supabase test db
All tests successful.
Files=22, Tests=185,  Result: PASS
```

## Concerns

None blocking. Two observations for the final review:

1. **No pgTAP covers this function.** Edge Functions are not reachable from
   pgTAP, so the guarantee rests on the manual runs above. The same is already
   true of `resolve_contacts` and `drain_reminders`, so this is a milestone-wide
   gap, not one this task introduced — but the `+`-prefix normalisation is
   exactly the kind of one-line detail that a refactor would silently drop with
   no test to catch it.
2. **`claim_profile` is not idempotent-checked here.** `private.claim_person`
   upserts on `phone_e164_hash`, so a second call returns the same id; that
   behaviour is covered by `20_claim_person_rpc.test.sql` at the RPC layer, not
   through the HTTP surface.
