# Task 3 Report: Let a signed-up user claim their person row

## Summary

Implemented `public.rpc_claim_person(uuid, text)` as a `service_role`-only wrapper
around `private.claim_person(uuid, text)`, following the brief exactly (no SQL
corrections needed this time). TDD sequence followed as prescribed: baseline
confirmed, failing test written and observed RED, migration written, full
suite run GREEN, RLS allowlist confirmed unchanged, single commit made.

## Baseline

Before touching anything:

```
supabase test db
...
All tests successful.
Files=20, Tests=172,  1 wallclock secs (...)
Result: PASS
```

Matches the expected baseline stated in the task instructions.

## RED — test written first, observed failing

Created `supabase/tests/database/20_claim_person_rpc.test.sql` verbatim from the
brief's Step 1. Ran it in isolation (per the CLI-2.78.1 workaround — positional
path, no `--file` flag):

```
supabase test db supabase/tests/database/20_claim_person_rpc.test.sql
```

Actual output:

```
psql:.../20_claim_person_rpc.test.sql:22: ERROR:  function public.rpc_claim_person(uuid, unknown) does not exist
LINE 1: select public.rpc_claim_person((select claimer from ids), '+...
               ^
HINT:  No function matches the given name and argument types. You might need to add explicit type casts.
/Users/admin1/.../20_claim_person_rpc.test.sql ..
Dubious, test returned 3 (wstat 768, 0x300)
Failed 3/4 subtests
Test Summary Report
-------------------
.../20_claim_person_rpc.test.sql (Wstat: 768 (exited 3) Tests: 1 Failed: 0)
  Non-zero exit status: 3
  Parse errors: Bad plan.  You planned 4 tests but ran 1.
Files=1, Tests=1,  0 wallclock secs (...)
Result: FAIL
```

This matches the brief's expected failure mode (`function public.rpc_claim_person(uuid, text) does not exist`,
modulo Postgres reporting the untyped string literal as `unknown` before an
overload is found — same underlying cause: the function does not exist yet).

No stray test directory was created by this run (the path existed as a file
already, so the CLI's directory-creation footgun for nonexistent paths did not
trigger).

## GREEN — migration added, full suite passing

Created `supabase/migrations/20260827000002_claim_person_rpc.sql` verbatim from
the brief's Step 3: a `security definer` SQL wrapper with `search_path = ''`
delegating to `private.claim_person`, with `revoke ... from public, anon,
authenticated` immediately followed by `grant ... to service_role`.

Ran, per the brief and the task-specific instructions (never skip the reset,
since fixture probing wasn't done here but the instruction is unconditional
before any suite run following a migration change):

```
supabase db reset
```

Migration `20260827000002_claim_person_rpc.sql` applied cleanly with no errors
(only a pre-existing, unrelated seed NOTICE about `tests.create_person`, present
before this change too).

```
supabase test db
...
.../11_rls_coverage.test.sql ......... ok
...
.../20_claim_person_rpc.test.sql ..... ok
All tests successful.
Files=21, Tests=176,  1 wallclock secs (...)
Result: PASS
```

Exact match to the expected end state: `Files=21, Tests=176, PASS`.

## RLS allowlist confirmation

`supabase/tests/database/11_rls_coverage.test.sql` line 48 still reads:

```
'my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token'
```

Unedited, and the file passed (`ok`) in the full suite run above — confirming
`authenticated` cannot execute `rpc_claim_person` and the set of `public`
functions it can execute is exactly the same four as before this task. The
`revoke ... from public, anon, authenticated` in the migration is what keeps
the new function off that list; it was applied as the very next statement
after `create or replace function`, closing the window during which a newly
created function is `PUBLIC`-executable by default.

## Deviations from the brief

None. Both the test SQL and the migration SQL in the brief were used verbatim
and worked on the first attempt — no defects found in this brief's SQL.

## Commit

```
980fd928faad9421dc871f9ce826e9d6a7ee4f9f feat(db): expose person claiming to the onboarding function
 2 files changed, 77 insertions(+)
 create mode 100644 supabase/migrations/20260827000002_claim_person_rpc.sql
 create mode 100644 supabase/tests/database/20_claim_person_rpc.test.sql
```

Only the two files named in the brief's Step 5 were staged (by explicit name,
not `git add -A`/`.`) and committed once, with the exact message from the
brief.

## Concerns

None identified. The fourth assertion (service_role-only enforcement via
`throws_ok` expecting SQLSTATE `42501`) passed as written, confirming a
signed-in `authenticated` user is rejected with insufficient-privilege when
calling the wrapper directly with an arbitrary phone number — the core
security property this task exists to establish.
