# Database notes

## Running the suite

    supabase start
    supabase db reset      # applies migrations, then seed.sql
    supabase test db       # runs supabase/tests/database/*.test.sql

`seed.sql` is local-only. It creates the `tests` schema helpers
(`tests.as_user`, `tests.create_user`, `tests.create_person`,
`tests.race_last_slot`) and committed catalog fixtures. It is never applied by
`supabase db push`.

M0 ends at 12 files / 96 assertions, green from a cold database.
`supabase db lint --level warning` reports warnings only inside `extensions.*`
— that is pgTAP's own code. `public` and `private` are clean.

## Security model

- Every `public` table has RLS enabled. A table with no policy denies
  everything to `anon` and `authenticated`; that is intentional for
  `gifts`, `people` and `payment_events`, which are written only by
  server-side functions.
- Privileged logic lives in the `private` schema as `security definer`
  functions with `search_path = ''` and `execute` revoked from client roles.
- `gifts.status` changes only through `private.gift_transition`. The
  `gifts_guard_status` trigger enforces this even against the service role,
  which bypasses RLS.
- A sender can never read `addresses`. The proof is
  `supabase/tests/database/04_addresses.test.sql`, which asserts zero rows
  rather than an error.
- Ops address reads go through `public.ops_get_delivery_address`, gated on gift
  status and logged to `address_access_log`. Staff can read that log and
  nothing else — a staff `delete` affects zero rows, which is asserted.

## Rules that are easy to get wrong

These cost real debugging during M0. Read them before touching the schema.

### Every new `private` function needs its own `revoke`

A function is `EXECUTE`-able by `PUBLIC` the moment it is created, and
`alter default privileges ... revoke execute on functions from public` does
**not** prevent that on PG17 — it is a no-op there. The guard is instead an
assertion in `01_private.test.sql`: the set of `private` functions
`authenticated` may execute must equal exactly

    can_see_person, is_staff, my_person_id

Adding to that list is a security decision. Every other new `private` function
must ship with `revoke execute on function ... from public, anon, authenticated`
or the suite fails by name. It caught five leaks during M0, including three
trigger functions.

A trigger still fires when the invoking role has no `EXECUTE` on the trigger
function — `EXECUTE` is checked at `create trigger` time — so these revokes
never disarm the guards they protect.

### `revoke ... from public` also takes the privilege from `authenticated`

`authenticated` holds `EXECUTE` on a new function only through the `PUBLIC`
grant, so revoking `PUBLIC` removes it too. Any `private` helper an RLS policy
calls therefore needs an explicit
`grant execute on function ... to authenticated`, plus `usage` on the schema —
policies are evaluated as the *calling* role, not the definer. Without both, the
policy raises `permission denied` instead of filtering rows.

### A column-level `revoke` cannot cut back a table-level grant

Supabase's default privileges give `authenticated` table-level `UPDATE` on every
new `public` table, and a table-level grant permits writing every column.
`revoke update (col)` on top of that does nothing. To make a column
unwritable, revoke the table-level privilege and grant back the writable columns
by name — that is what `profiles` does to stop a user setting their own
`is_staff`. Adding a column to `profiles` means adding it to that grant list.

### Other users' profiles are invisible

`profiles_select_own` means a signed-in session sees only its own row. Public
identity lives on `public.people`. Any code — or test — that resolves another
user through `public.profiles` gets `NULL`.

### `people.birthday` is a date of birth

It must be in the past (`people_birthday_sane`). "Their birthday is in five
days" is expressed as a real DOB with that month and day, not as
`current_date + 5`.

## Function contracts worth knowing

- `private.confirm_gift` **returns** a gift whose status is `refunded` when the
  address is outside the service area. It does not raise. Raising would roll
  back the decline, the slot release and the refund in the same transaction,
  which is exactly the bug M0 found and fixed — the sender's money would never
  come back. Callers branch on the returned status.
- `private.mark_gift_paid` is idempotent on `provider_event_id`; a replayed
  webhook returns current state without double-advancing.
- `private.expire_stale_gifts` returns the number of gifts it touched. It
  releases abandoned draft holds and refunds paid-but-unconfirmed gifts past
  their occasion date. M4 schedules it; M0 only tests it.

## Things that must not change casually

- `private.config.phone_pepper`: rotating it invalidates every stored
  `people.phone_e164_hash`, orphaning the whole contact graph. There is no
  default: `private.phone_hash` raises `phone_pepper is not configured`
  until one is set (20261018000005). Local and CI get a local-only value from
  `supabase/seed.sql`; a hosted project sets its own once, before the first
  sign-up (deploy runbook, step 3). A project that already hashed data with
  the old public placeholder keeps it, with a migration WARNING, because
  removing it would orphan that data; re-keying means re-hashing every
  number from its source.
- `private.gift_transitions`: the legal state graph. Add rows; do not delete
  them without checking `gift_events` history.
- `tests.race_last_slot`'s connection string dials the container's own address
  on port 5432, not `127.0.0.1:54322`. Loopback is `trust` in `pg_hba`, so no
  password is exercised and `dblink` refuses the connection for a non-superuser.

## Rules M1 Phase 2a paid for

These cost real debugging or real security holes. Each one shipped a bug first.

- **Every `auth.uid()`-based trigger is INERT under `service_role`.** M0's
  `celebrations_guard` compares `new.person_id = private.my_person_id()`, which
  reads `auth.uid()`. Under `service_role` there is no session, so the
  comparison yields NULL and the guard silently never fires. Any code path that
  reaches a table through a `security definer` RPC needs its OWN explicit check
  — you cannot rely on a session-based trigger to defend it. Phase 2a shipped a
  self-celebration bug this way and spent two fix rounds on it.

- **Every phone write path must go through `private.assert_e164`.**
  `private.phone_hash` is a bare HMAC with no normalisation, so `+919999000002`,
  `919999000002` and `+91 99990 00002` produce three DIFFERENT hashes and
  therefore three different `people` rows for one human. Consequences that
  actually occurred: the self-celebration guard was bypassable with an
  unnormalised spelling of your own number, and one person imported from two
  address books forked into rows whose inbound edges were orphaned invisibly.
  The guard is per-call-site, not central — adding a new writer means adding the
  call. `resolve_contacts` is deliberately exempt: a lookup over a whole address
  book must fail to match on junk, not raise and kill the batch.

- **SQLSTATE choice is a public API decision.** PostgREST maps the code to an
  HTTP status. Measured on this stack: `P0001` → 400, `P0002` → 500,
  `22023` → 400, `45001` → 400. Never borrow an assigned PL/pgSQL code for an
  application condition — `P0002` is `no_data_found`, so using it turned a
  routine "that number is you" into an HTTP 500 that every retry and alerting
  layer would read as an outage. Use an unassigned class; this repo uses
  `45001`. Raise with `using errcode = ...` — a bare `raise exception` is
  `P0001`, which every other unhandled error also carries, so it cannot be
  branched on.

- **`[auth.sms] enable_confirmations` must stay `true`.** When false, GoTrue runs
  with `SMS_AUTOCONFIRM=true`, and `PUT /auth/v1/user {"phone": ...}` rewrites
  `auth.users.phone` AND stamps `phone_confirmed_at` with no OTP at all. Since
  `claim_profile` trusts the session phone, that let any signed-in user point
  their session at a stranger's number and claim their person row, inheriting
  every celebration edge aimed at it. Checking `phone_confirmed_at` in code does
  NOT help — autoconfirm sets it. **`config.toml` is not applied by
  `supabase db push`; this must be set separately in the hosted dashboard**, or
  the hole ships to production while local looks correct. Nothing tests this.

- **Deleting an account rotates `people.phone_e164_hash`.** The row survives so
  inbound edges do not break, but if the hash survived too, `claim_person`'s
  `on conflict (phone_e164_hash)` would hand the row — with its inbound edges
  and wish wall — to whoever next verifies that recycled number, and
  `upsert_person` would refill the scrubbed birthday on any re-import, queueing
  real reminders about a deleted user. Accepted trade-off: a bystander's edge is
  permanently stranded on a "Deleted user" row, and re-importing that number
  mints a second row beside it.

- **Writes to `public.celebrations` go through `rpc_add_celebration` only.**
  `authenticated` holds no INSERT and no table-level UPDATE — only
  `update (nickname)`. The reason is that a `with check` on
  `celebrator_profile_id` constrains who owns an edge but not who it points at,
  and `private.can_see_person` grants sight of a `people` row to anyone holding
  an edge to it. Since `people.id` is a sequential bigint, a free `person_id`
  let any signed-in user enumerate every user's real name and full date of
  birth. The RPC takes a PHONE NUMBER, not a person id, which is what closes it.

## Rules M1 Phase 3 paid for

- **`private.can_see_person` returns NULL, not false, for an unclaimed caller
  — a bare `if not` never branches on that.** Its first clause is
  `p_person_id = private.my_person_id()`; for a caller who has not claimed a
  person row, `my_person_id()` is NULL, so that comparison is NULL, and
  `NULL or false or false` is NULL. plpgsql's `if not <NULL> then` takes the
  false branch, so `if not can_see_person(...)` silently lets an unclaimed,
  unconnected caller straight through — exactly the outsider case the check
  exists to reject. Every RLS `using` clause built on this function is safe
  regardless: Postgres treats a NULL `using` result as "exclude the row", so
  the gap never shows up there. It only bites imperative code that calls the
  function directly — `if not coalesce(private.can_see_person(p_id), false)`
  is the required form. `public.person_celebrator_count` was caught using the
  bare form while it was still being proven, before it ever reached a commit.
