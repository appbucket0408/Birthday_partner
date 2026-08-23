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
  `people.phone_e164_hash`, orphaning the whole contact graph.
- `private.gift_transitions`: the legal state graph. Add rows; do not delete
  them without checking `gift_events` history.
- `tests.race_last_slot`'s connection string dials the container's own address
  on port 5432, not `127.0.0.1:54322`. Loopback is `trust` in `pg_hba`, so no
  password is exercised and `dblink` refuses the connection for a non-superuser.
