# Final fix report — B1, B2, B3

Worktree: `/Users/admin1/Desktop/Projects/birthday_app/.claude/worktrees/m1-phase2a-backend`
Baseline HEAD: `39d6be0` — `Files=24, Tests=224, PASS`
Fix commit: `430d6bc` — `fix(db): close the celebrations enumeration leak and the recycled-number graph handover`
Final: `Files=26, Tests=254, PASS`

One commit, 7 files, +741/-15. The report itself lives under `.superpowers/`, which is not tracked.

---

## 1. Files touched, and why

| File | Change | Why |
| --- | --- | --- |
| `supabase/migrations/20260827000006_celebrations_write_lockdown.sql` | **new** | B1 behaviour change. Drops `celebrations_insert_own`, revokes table `INSERT`, revokes table `UPDATE` and grants back `update (nickname)`, recreates `celebrations_update_own`, adds `celebrations_guard_update` as a `before update` trigger. |
| `supabase/migrations/20260827000007_scrub_rotates_phone_hash.sql` | **new** | B2 + B3 behaviour change. `create or replace private.scrub_person_on_profile_delete()` — same body plus `phone_e164_hash` rotation. Preserves `returns trigger`, `security definer`, `set search_path = ''`, and repeats the `revoke execute`. |
| `supabase/migrations/20260827000005_scrub_on_delete.sql` | **comment only** | Two false claims corrected in place, each marked `CORRECTION (20260827000007)`: (a) the header listed `phone_e164_hash` among "what must survive"; (b) it claimed nulling `birth_month` "stops enqueue_reminders from ever queueing a NEW one for this person", which B3 disproved. No SQL statement in this file changed — verified with `git diff --stat` below. |
| `supabase/tests/database/03_people_graph.test.sql` | modified | Two assertions asserted the OLD behaviour. `:85` (self-celebration raises `P0001` on a direct insert) now asserts `42501` — `authenticated` has no insert path at all — aimed at the caller's OWN person id so it proves "no insert", not "no insert at someone else's row". `:101` keeps its `42501` but its comment now names the new reason. Plan count unchanged at 12; neither assertion was weakened (both still assert a hard rejection, and the one that moved got *stricter*: it now rejects the most sympathetic possible insert). |
| `supabase/tests/database/23_delete_account.test.sql` | **comment only** | Its cascade table said `phone_e164_hash unchanged`. Now says ROTATED, and points at file 25. Plan count unchanged at 27. |
| `supabase/tests/database/24_celebrations_write_lockdown.test.sql` | **new**, `plan(16)` | B1 assertions, including the reviewer's repro replicated as a test. |
| `supabase/tests/database/25_recycled_number.test.sql` | **new**, `plan(14)` | B2 + B3 assertions. |

`docs/db.md` was not changed — none of its five rules needed amending, and rule 3 ("a column-level `revoke` cannot cut back a table-level grant") is the rule 000006 follows.

```
$ git diff --stat
 .../migrations/20260827000005_scrub_on_delete.sql  | 26 ++++++++++++++++---
 supabase/tests/database/03_people_graph.test.sql   | 29 ++++++++++++++++++----
 supabase/tests/database/23_delete_account.test.sql | 18 +++++++++-----
 3 files changed, 58 insertions(+), 15 deletions(-)
```

---

## 2. The two B1 pre-checks

### Pre-check 1 — does any existing client-facing behaviour depend on `authenticated` inserting into `celebrations`?

**No.** Nothing outside the tests writes to `celebrations` as a client role at all.

```
$ grep -rn "celebrations" supabase/functions
supabase/functions/delete_account/index.ts:8:// their outgoing celebrations, the wishes they authored, their device tokens,
```

That is a comment. The only Edge Function that creates an edge is `add_celebrations`, which calls `public.rpc_add_celebration` — `security definer`, `revoke ... from public, anon, authenticated`, `grant execute ... to service_role`. It never touches the table as `authenticated`.

Fifteen test setup blocks insert into `celebrations`. I checked the role in force at each insert:

```
$ grep -n "as_user|as_postgres|as_anon|into public.celebrations|update public.celebrations" <each file>
```

| File | insert line | role at that line |
| --- | --- | --- |
| `03_people_graph` | 40 | `postgres` (`as_postgres()` at :7) |
| `03_people_graph` | **85, 101** | **`authenticated`** (`as_user(alice)` at :66) — these two are the assertions under test, not setup |
| `04_addresses` | 31 | `postgres` (:12) |
| `07_gifts` | 17 | `postgres` (:7) |
| `08_gift_lifecycle` | 16 | `postgres` (:4) |
| `09_wishes` | 14 | `postgres` (:6) |
| `10_ops` | 20 | `postgres` (:7) |
| `13_celebrate_counts` | 13 | `postgres` (:4) |
| `14_wish_history` | 10 | `postgres` (:4) |
| `15_birthday_stats` | 13, 19 | `postgres` (:4) |
| `17_reminders` | 15, 228 | `postgres` (:6, :185) |
| `19_reminder_preference` | 14 | `postgres` (:7) |

Every single setup insert runs as `postgres`, which bypasses RLS and holds its own grants. The **only** two statements in the suite that insert as `authenticated` are `03:85` and `03:101` — both of them `throws_ok` assertions, i.e. they exist to prove an insert *fails*. Zero setup blocks broke, which is why the untouched 22 files went green on the first run after the migration.

Note the `before insert` trigger still fires for the `postgres` setup inserts (`EXECUTE` on a trigger function is checked at `create trigger` time, per `docs/db.md`), so dropping the insert *policy* does not disarm `guard_celebration` for them.

### Pre-check 2 — what is `celebrations.nickname`, and should `authenticated` be able to update it?

`nickname text` on `public.celebrations` — a per-celebrator private label for a person they already celebrate. From the spec (`2026-08-22-birthday-gifting-app-design.md:78`): "a per-celebrator nickname and an import source".

Letting `authenticated` update it is **correct**, on three grounds:

1. **It is the user's own contributed data**, on a row they own, describing an edge they own. Nobody else wrote it.
2. **It cannot leak anything.** It takes no part in `private.can_see_person` or any other visibility predicate, so rewriting it changes what nobody can see. Contrast `person_id`, which *is* the visibility predicate — that is the whole of B1.
3. **It is already treated as private to the celebrator in the opposite direction.** `20260824000002_celebrations_incoming.sql` exists specifically so the *subject* of an edge never sees `nickname` or `source`. Finding F3 of the M1 Phase 1 review made that change. So nickname is not readable by the person it describes, and a user editing their own label reveals nothing to them.

`source` is the opposite call and is **not** granted: it is provenance ('contacts' / 'search' / 'manual'), written by the server to record *how* the edge was made. A client rewriting it would be falsifying an audit fact about itself. It is now unwritable, and that is asserted.

So the grant list is exactly `nickname`, and assertion 13 of file 24 pins it as *exactly* that — if someone re-grants table-level UPDATE to "fix a permission error", every column shows up there and the test fails by name.

---

## 3. B1 — the fix

`supabase/migrations/20260827000006_celebrations_write_lockdown.sql`, three independent locks:

```sql
drop policy celebrations_insert_own on public.celebrations;
revoke insert on public.celebrations from anon, authenticated;

revoke update on public.celebrations from anon, authenticated;
grant update (nickname) on public.celebrations to authenticated;

drop policy celebrations_update_own on public.celebrations;
create policy celebrations_update_own
  on public.celebrations for update to authenticated
  using (celebrator_profile_id = (select auth.uid()))
  with check (celebrator_profile_id = (select auth.uid()));

create trigger celebrations_guard_update
  before update on public.celebrations
  for each row execute function private.guard_celebration();
```

`celebrations_select_own` and `celebrations_delete_own` untouched, as instructed.

One behavioural consequence written into the migration comment: the `before update` trigger fires on *any* update, nickname edits included. If the person you celebrate has blocked you since you added them, renaming them now raises `this person has blocked you`. That is the intended reading of a block, but it is a rejection the client must expect on a path that looks purely cosmetic.

### State after `db reset`

```
$ docker exec -i supabase_db_birthday_app psql -U postgres -d postgres -qtA -c "..."
celebrations_delete_own DELETE
celebrations_select_own SELECT
celebrations_update_own UPDATE
authenticated INSERT: false
authenticated updatable columns: nickname
celebrations_guard -> CREATE TRIGGER celebrations_guard BEFORE INSERT ON public.celebrations FOR EACH ROW EXECUTE FUNCTION private.guard_celebration()
celebrations_guard_update -> CREATE TRIGGER celebrations_guard_update BEFORE UPDATE ON public.celebrations FOR EACH ROW EXECUTE FUNCTION private.guard_celebration()
```

---

## 4. B2 / B3 — the fix

`supabase/migrations/20260827000007_scrub_rotates_phone_hash.sql`. Same scrub body, one column added to the `update`:

```sql
      phone_e164_hash =
        replace(pg_catalog.gen_random_uuid()::text, '-', '') ||
        replace(pg_catalog.gen_random_uuid()::text, '-', '')
```

Column type/length confirmed compatible before writing it:

- `phone_e164_hash text not null unique`
- `constraint people_phone_hash_format check (phone_e164_hash ~ '^[0-9a-f]{64}$')`

Two dash-stripped UUIDs are exactly 64 lowercase hex characters, the same shape `private.phone_hash` produces (`encode(extensions.hmac(...,'sha256'),'hex')`).

```
$ psql -c "select n.nspname, p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='gen_random_uuid';"
  nspname   |     proname
------------+-----------------
 pg_catalog | gen_random_uuid
 extensions | gen_random_uuid
```

`pg_catalog`-qualified so it resolves under `search_path = ''`. `random()` was **not** used: it is a per-backend seeded PRNG whose output is predictable from other draws, which is not an acceptable basis for a privacy control. `gen_random_uuid()` draws from the platform CSPRNG; two of them carry ~244 bits, so collision with a real HMAC or with another rotated row is not a case that needs handling. The value is unrelated to the phone number, so unlike the hash it replaces it cannot be reversed by anyone, us included.

### The erasure claim, corrected

A peppered phone hash is **not** anonymous data. It is a deterministic function of a phone number, so anyone holding the number can re-derive it and confirm the row is that person's. Keeping it was keeping an identifier for a user who asked to be forgotten. Rotating it *strengthens* the erasure; it does not weaken the "the person row survives" guarantee, because what that guarantee was ever for is the row and its inbound edges, both of which are untouched.

### The trade-off (stated in the migration comment and here)

- The bystander's celebration edge is now **permanently stranded** on a row named `Deleted user` with no birthday. No future event can reunite that row with the human it described. The bystander keeps a dead entry in their list until they remove it.
- A later re-import of the same number mints a **second, separate** people row beside the stranded one. The two are unlinkable by design. If the original owner ever signs up again on the same number, they get the new row and none of their old inbound edges.

Both are accepted deliberately. The alternative is the B2 repro: handing a stranger's social graph, wish wall and inbound reminders to whoever next gets the recycled number. A stale row in one person's list is a cosmetic cost; the other is an unrecoverable breach against someone who already left.

---

## 5. Suite

### Baseline, at `39d6be0`

```
$ supabase db reset && supabase test db
...
All tests successful.
Files=24, Tests=224,  1 wallclock secs ( 0.03 usr  0.03 sys +  0.11 cusr  0.05 csys =  0.22 CPU)
Result: PASS
```

### After the fixes

```
$ supabase db reset && supabase test db
/…/00_harness.test.sql ...................... ok
/…/01_private.test.sql ...................... ok
/…/02_profiles.test.sql ..................... ok
/…/03_people_graph.test.sql ................. ok
/…/04_addresses.test.sql .................... ok
/…/05_catalog_slots.test.sql ................ ok
/…/06_slot_concurrency.test.sql ............. ok
/…/07_gifts.test.sql ........................ ok
/…/08_gift_lifecycle.test.sql ............... ok
/…/09_wishes.test.sql ....................... ok
/…/10_ops.test.sql .......................... ok
/…/11_rls_coverage.test.sql ................. ok
/…/12_birthday_model.test.sql ............... ok
/…/13_celebrate_counts.test.sql ............. ok
/…/14_wish_history.test.sql ................. ok
/…/15_birthday_stats.test.sql ............... ok
/…/16_device_tokens.test.sql ................ ok
/…/17_reminders.test.sql .................... ok
/…/18_resolve_contacts.test.sql ............. ok
/…/19_reminder_preference.test.sql .......... ok
/…/20_claim_person_rpc.test.sql ............. ok
/…/21_add_celebration.test.sql .............. ok
/…/22_phone_e164_guard.test.sql ............. ok
/…/23_delete_account.test.sql ............... ok
/…/24_celebrations_write_lockdown.test.sql .. ok
/…/25_recycled_number.test.sql .............. ok
All tests successful.
Files=26, Tests=254,  1 wallclock secs ( 0.06 usr  0.02 sys +  0.13 cusr  0.05 csys =  0.26 CPU)
Result: PASS
```

`24 -> 26` files, `224 -> 254` assertions (+16 in file 24, +14 in file 25; files 03 and 23 kept their existing plan counts).

---

## 6. The three repros, before and after

Command in both cases:

```
$ docker exec -i supabase_db_birthday_app psql -U postgres -d postgres \
    < /…/scratchpad/{b1_fair,b2_recycled,b3_resurrect}.sql
```

### B1 — before (at `39d6be0`)

```
 victim person id = 55, attacker = c8f3f838-…
NOTICE:  INSERT aimed at victim person 55: SUCCEEDED
NOTICE:  UPDATE redirecting an edge to victim: SUCCEEDED (t rows)
                 ?column?
------------------------------------------
 LEAKED -> VictimThree Real dob=11/7/1991
(1 row)
```

### B1 — after

```
 victim person id = 65, attacker = c8f3f838-…
NOTICE:  INSERT aimed at victim person 65: BLOCKED -> permission denied for table celebrations (42501)
NOTICE:  UPDATE redirecting an edge to victim: BLOCKED -> permission denied for table celebrations (42501)
 ?column?
----------
(0 rows)
```

Nothing leaked. **Closed.**

### B2 — before

```
 alice person id: 68
 bob claimed person id: 68
 bob inherited inbound edges: 1
 bob inherited wishes: 1
```

### B2 — after

```
 alice person id: 68
 bob claimed person id: 69
 bob inherited inbound edges: 0
 bob inherited wishes: 0
```

A different row id, and no inherited graph. **Closed.**

### B3 — before

```
 after scrub: name=Deleted user month=NULL
 after re-import: name=Deleted user month=4 day=15
 enqueue_reminders: 1
 outbox rows queued about the deleted user: 1
```

### B3 — after, running the script verbatim

```
 after scrub:
(0 rows)
 after re-import: name=Ghost From My Contacts month=4 day=15
 enqueue_reminders: 1
 outbox rows queued about the deleted user: 1
```

**This output needs reading carefully, and it is not a failure.** `b3_resurrect.sql` identifies the row by `phone_e164_hash = private.phone_hash('+919710000001')`. After the rotation that predicate no longer matches the deleted user's row at all — which is exactly why the "after scrub" query now returns **0 rows** where it used to return one. What the last three lines describe is the *new* row the re-import minted: a live contact of `friend`'s, which correctly has a birthday and correctly generates a reminder for `friend`. The script's `join public.people p on p.id = o.subject_person_id where p.phone_e164_hash = …` follows the hash to that new row, not to the stranded one.

So I re-ran it anchored on the stranded person **id**, captured before the deletion, which is the identity the finding is actually about:

```
$ docker exec -i supabase_db_birthday_app psql -U postgres -d postgres \
    < /…/scratchpad/b3_resurrect_anchored.sql

 stranded person id: 74
 after scrub (by id):   name=Deleted user month=NULL findable_by_phone=false
 the re-import minted person id: 75 (stranded was 74) -- same row? false
 after re-import (by id): name=Deleted user month=NULL day=NULL
 enqueue_reminders: 1
 outbox rows queued about the DELETED USER (stranded id): 0
```

Birthday not restored, zero reminders about the deleted user, and the re-import landed on a separate row — the documented trade-off, visible. **Closed.**

---

## 7. Discrimination proofs

Method: revert one lock **on the live database only** via `psql` (migration files untouched), run the affected test file directly through `psql` so the TAP output is per-assertion, restore, run again. Break scripts live in the scratchpad; each is a `.sql` file applied with `docker exec -i supabase_db_birthday_app psql -U postgres -d postgres -qtA < …`.

### D1 — revert the insert lockdown

```sql
grant insert on public.celebrations to authenticated;
create policy celebrations_insert_own on public.celebrations
  for insert to authenticated
  with check (celebrator_profile_id = (select auth.uid()));
```

```
===== D1 BREAK (live db only): re-create celebrations_insert_own + table INSERT grant
----- 24_celebrations_write_lockdown.test.sql
1..16
not ok 2 - authenticated cannot insert an edge aimed at a stranger's person id
not ok 8 - after all of the above the victim's person row is still invisible to the attacker
not ok 9 - the victim's real name never becomes readable
not ok 11 - authenticated holds no INSERT privilege on celebrations
not ok 12 - celebrations has no INSERT policy left for anyone to slip through
# Looks like you failed 5 tests of 16
----- 03_people_graph.test.sql
1..12
not ok 10 - authenticated cannot insert a celebration edge, not even one it would own
# Looks like you failed 1 test of 12
===== D1 RESTORE
----- 24 again
1..16
(no 'not ok' above = pass)
----- 03 again
1..12
(no 'not ok' above = pass)
```

Assertions 8 and 9 are the ones that matter: with the policy back, the victim's real name becomes readable through the test's own eyes. The test is not merely checking a catalog fact, it is checking the leak.

### D2 — revert the column lockdown (the exact `docs/db.md` mistake)

```sql
grant update on public.celebrations to authenticated;
```

```
===== D2 BREAK (live db only): grant table-level UPDATE back to authenticated
----- 24_celebrations_write_lockdown.test.sql
1..16
not ok 3 - authenticated cannot redirect an edge it owns at another person_id
not ok 4 - authenticated cannot rewrite source, the provenance of the edge
not ok 7 - that rename actually landed
not ok 8 - after all of the above the victim's person row is still invisible to the attacker
not ok 9 - the victim's real name never becomes readable
not ok 10 - the attacker still holds exactly the one edge they legitimately created
not ok 13 - nickname is the only column authenticated may update
# Looks like you failed 7 tests of 16
===== D2 RESTORE
----- 24 again
1..16
(no 'not ok' above = pass)
```

Note assertion 5 (`cannot hand an edge it owns to another profile`) stays green under this break — correctly: `celebrations_update_own`'s `with check` still catches that one on its own. The column grant and the policy cover different halves, and the test shows which.

### D3 — drop the `before update` trigger

```sql
drop trigger celebrations_guard_update on public.celebrations;
```

```
===== D3 BREAK (live db only): drop the BEFORE UPDATE trigger
----- 24_celebrations_write_lockdown.test.sql
1..16
not ok 15 - guard_celebration is wired to BEFORE UPDATE, not only BEFORE INSERT
not ok 16 - redirecting an edge into someone who blocked you is rejected on UPDATE too
# Looks like you failed 2 tests of 16
===== D3 RESTORE
----- 24 again
1..16
(no 'not ok' above = pass)
```

Assertion 16 is behavioural, not a catalog read: it performs the redirect as `postgres` (the only role that can still reach an `UPDATE` of `person_id` at all, which is precisely the point of a trigger as opposed to a grant) and requires the raise.

### D4 — revert the hash rotation

`private.scrub_person_on_profile_delete()` restored to `20260827000005`'s body verbatim, on the live database only.

```
===== D4 BREAK (live db only): scrub without the phone_e164_hash rotation
----- 25_recycled_number.test.sql
1..14
not ok 4 - after: no person row can be found by alice's original phone number
not ok 6 - after: the stored hash is no longer the hash of her number
not ok 8 - B2: a recycled number mints a NEW person row, not alice's old one
not ok 9 - B2: bob inherits no inbound celebration edges
not ok 10 - B2: bob inherits no wishes -- alice's wall is not his
not ok 12 - B3: a re-import carrying their real birthday does not restore it on the scrubbed row
not ok 13 - B3: the re-import mints a second, separate row rather than reviving the stranded one
not ok 14 - B3: enqueue_reminders queues nothing about the deleted user on their old birthday
# Looks like you failed 8 tests of 14
----- 23_delete_account.test.sql (must stay green: the cascade table is unchanged)
1..27
(no 'not ok' above = pass)
===== D4 RESTORE
----- 25 again
1..14
(no 'not ok' above = pass)
----- 23 again
1..27
(no 'not ok' above = pass)
----- 01_private.test.sql (allowlist must survive the create-or-replace)
1..9
(no 'not ok' above = pass)
```

23 staying green under the break is itself informative: the cascade table 23 pins genuinely did not change, so the two new tests are carrying the new behaviour rather than 23 having been quietly rewritten.

### Assertions in file 25 that do NOT discriminate against D4 — stated rather than hidden

Three of the fourteen stayed green under the D4 break, and I am naming them rather than letting them read as proof:

- **5** `the rotated hash keeps the 64-hex shape the column constrains`
- **7** `two scrubbed rows rotate to different values`
- **11** `B2: bob's new row carries bob's own identity, not the placeholder`

5 and 7 pass without the rotation because a real HMAC is also 64 hex and is also distinct per row. 11 passes because `claim_person` overwrites `display_name` from the profile even on a conflicting row. They are shape guards on the *choice of replacement value*, not proof that a replacement happens. I verified what they do catch, with two more live-database breaks:

```
===== D5 BREAK: rotate to a CONSTANT sentinel repeat('f',64) instead of random
ERROR:  duplicate key value violates unique constraint "people_phone_e164_hash_key"
DETAIL:  Key (phone_e164_hash)=(ffffffff…ffff) already exists.
CONTEXT:  SQL statement "update public.people … phone_e164_hash = repeat('f', 64) where id = v_person_id"
PL/pgSQL function private.scrub_person_on_profile_delete() line 22 at SQL statement
SQL statement "DELETE FROM ONLY "public"."profiles" WHERE $1 OPERATOR(pg_catalog.=) "id""

===== D6 BREAK: rotate to a value that is not 64 lowercase hex
ERROR:  new row for relation "people" violates check constraint "people_phone_hash_format"
DETAIL:  Failing row contains (143, 89da1ec0-8be8-4528-b8ce-15d970d16e41, …, Deleted user, …)
CONTEXT:  SQL statement "update public.people … phone_e164_hash = pg_catalog.gen_random_uuid()::text …"
PL/pgSQL function private.scrub_person_on_profile_delete() line 22 at SQL statement
SQL statement "DELETE FROM ONLY "public"."profiles" WHERE $1 OPERATOR(pg_catalog.=) "id""

===== RESTORE the real rotation
1..14
(no 'not ok' above = pass)
```

Both bad rotations abort **account deletion itself**, loudly, via the table's own constraints — so they surface as a hard error rather than a quiet wrong answer, and assertions 5 and 7 are there to name the reason when it happens. That is documented in a comment at the top of those two assertions in the test file so no future reader mistakes them for the proof of B2/B3. What actually closes B2/B3 is assertions **4, 6, 8, 9, 10, 12, 13, 14**.

---

## 8. Standing guards

### `private` allowlist — unchanged

```
$ psql -qtA -c "select coalesce(string_agg(p.proname, ',' order by p.proname), '') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and has_function_privilege('authenticated', p.oid, 'EXECUTE');"
can_see_person,is_staff,my_person_id
```

### `public` allowlist — unchanged

```
$ psql -qtA -c "select coalesce(string_agg(p.proname, ',' order by p.proname), '') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and has_function_privilege('authenticated', p.oid, 'EXECUTE');"
my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token
```

`20260827000007` uses `create or replace` on `private.scrub_person_on_profile_delete()` and repeats its `revoke execute … from public, anon, authenticated`, so it stays off both lists — pinned by `01_private.test.sql` (green above, including under the D4 break/restore cycle). `20260827000006` creates no functions at all.

### `supabase db lint --level warning` — warnings only inside `extensions.*`

```
$ supabase db lint --level warning | grep '"function"' | sort -u
    "function": "extensions._constraint",
    "function": "extensions._currtest",
    "function": "extensions._def_is",
    "function": "extensions._do_ne",
    "function": "extensions._docomp",
    "function": "extensions._get_ac_privs",
    "function": "extensions._get_col_privs",
    "function": "extensions._get_db_privs",
    "function": "extensions._get_fdw_privs",
    "function": "extensions._get_func_privs",
    "function": "extensions._get_lang_privs",
    "function": "extensions._get_schema_privs",
    "function": "extensions._get_sequence_privs",
    "function": "extensions._get_server_privs",
    "function": "extensions._get_table_privs",
    "function": "extensions._get_tablespaceprivs",
    "function": "extensions._prokind",
    "function": "extensions._relcomp",
    "function": "extensions._time_trials",
    "function": "extensions.add_result",
    "function": "extensions.check_test",
    "function": "extensions.format_type_string",
    "function": "extensions.has_tablespace",
    "function": "extensions.is_empty",
    "function": "extensions.isnt_empty",
    "function": "extensions.plan",
    "function": "extensions.row_eq",
```

Every entry is `extensions.*` — pgTAP's own code, as `docs/db.md` records. `public` and `private` produce nothing. The lint run itself walks `extensions, private, public, tests`.

---

## 9. Disagreements and residual risk

I do not disagree with any of the three fixes. Four things the next reader should know:

1. **B1 is inherited from M0, and one part of the old proof moved rather than survived.** `03:85` used to prove `guard_celebration`'s self-celebration branch from a client session. That branch is now unreachable from a client session, because clients have no insert path and cannot write `person_id` on update. The branch is still proved — through `private.add_celebration` in `21_add_celebration.test.sql:96` (`45001`) — but if a future migration reopens client inserts, the self-check will be running on a path nothing exercises end-to-end from a client any more. `24`'s assertion 16 covers the block branch on update; the self branch on update stays uncovered because it reads `auth.uid()`, which is null under every role that can still reach that update.

2. **`celebrations_guard_update` fires on nickname edits.** A user whose target has blocked them since they added them will get `this person has blocked you` when they try to rename them. Deliberate, commented in the migration, but it is a rejection on a cosmetic path and the client needs an error branch for it.

3. **The stranded-edge trade-off is real and will generate support traffic.** After a deletion, a bystander sees `Deleted user` in their list forever, and if the original person ever returns on the same number they appear as a *new* entry that must be added again. That is the correct trade against B2, but it is a product-visible behaviour that nothing in the client currently explains to the user. Worth a line in the Celebrates list UI in Phase 2b.

4. **`suppress_person` still hard-deletes.** `private.suppress_person` (the "not me / remove me" path) deletes the people row outright and records the hash in `private.suppressions`, which is a different and stronger erasure than account deletion's. The two paths now differ in kind — one strands edges, the other cascades them away — and that asymmetry is not documented anywhere. Not a defect for this gate; flagging it because someone will eventually ask why.
