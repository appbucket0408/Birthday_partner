# M1 Phase 1 — Data and Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and prove every database and server-side surface M1 needs — the month/day birthday model, the reminder pipeline, the two policy changes the Instagram-style profile requires, and the contact-resolution function — with no UI.

**Architecture:** All business logic lives in Postgres as `security definer` functions in the `private` schema, tested with pgTAP. Edge Functions are thin wrappers that do only what Postgres cannot: talk HTTP to FCM and accept a request body. `pg_cron` writes reminder work into an outbox table whose unique constraint is the no-double-send guarantee, and a drain function ships it.

**Tech Stack:** Postgres 17, Supabase CLI 2.78.1, pgTAP, pg_cron 1.6.4, pg_net 0.20.0, Deno (Edge Functions), Docker via colima.

**Spec:** `docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md`

## Global Constraints

Every task's requirements implicitly include this section. These are M0's hard-won rules; ignoring one costs a debugging session.

- **Migrations are append-only.** Never edit a `20260822*` migration. New migrations only, named `20260824NNNNNN_<topic>.sql`.
- **Every new `private` function ships with `revoke execute on function ... from public, anon, authenticated;`.** A function is `PUBLIC`-executable the moment it is created, and `alter default privileges ... revoke execute on functions from public` is a **no-op on PG17**. This is not optional — `01_private.test.sql` fails by name otherwise.
- **`revoke ... from public` also strips `authenticated`.** It held EXECUTE only through the `PUBLIC` grant. Any `private` function an RLS policy calls needs an explicit `grant execute on function ... to authenticated;` *and* the schema `usage` grant that already exists. Policies are evaluated as the calling role, not the definer.
- **If a task adds a `private` function that a policy calls, it must extend the allowlist string in `01_private.test.sql` in the same task.** Current value: `'can_see_person,is_staff,my_person_id'`.
- **A column-level `revoke` cannot cut back a table-level grant.** To make a column unwritable, revoke the table privilege and grant back writable columns by name. Conversely, **adding a column to `public.profiles` requires adding it to that grant list**, or clients silently cannot write it.
- **Other users' profiles are invisible.** `profiles_select_own` means a signed-in session sees only its own row. In tests, resolve other users' ids **as `postgres`** (into a temp table with `grant select ... to authenticated` if needed) before switching role. A lookup through `public.profiles` from an authenticated session returns `NULL`.
- **Observe RED before implementing.** Run the new test and see it fail for the right reason. A test that cannot fail is a defect.
- **CLI 2.78.1 has no `--file` flag.** Use `supabase test db supabase/tests/database/NN_name.test.sql` positionally. Passing a path that does not exist makes Docker create a *directory* at that path — if that happens, `rmdir` it.
- **Every `public` table needs RLS enabled and every FK's first column indexed.** `11_rls_coverage.test.sql` enforces this.
- Identifiers lowercase with underscores. `text`, never `varchar`. `timestamptz`, never `timestamp`.
- **Bringing the stack up:** `colima start` must run with the sandbox disabled (its VM image is a GitHub release asset and github.com times out sandboxed), then `supabase start`. Verify with `supabase test db` → `Files=12, Tests=96, PASS` before starting work.

## File Structure

**Migrations** (all new):

| File | Responsibility |
|---|---|
| `20260824000001_birthday_parts.sql` | Replace the `date` birthday columns with month/day/year on `people` and `profiles`; rewire the three functions and the sync trigger; fix the R14 grant list |
| `20260824000002_celebrations_incoming.sql` | `celebrations_select_incoming` policy |
| `20260824000003_wishes_author_visibility.sql` | Replace `wishes_select_visible` so an author always sees their own wish |
| `20260824000004_birthday_stats.sql` | `public.my_birthday_stats()` |
| `20260824000005_device_tokens.sql` | `public.device_tokens` + owner-only RLS |
| `20260824000006_reminders.sql` | `private.notification_outbox`, the fan-out function, and the two drain helpers |
| `20260824000007_resolve_contacts.sql` | `private.resolve_contacts(text[])` — match-only contact resolution |
| `20260824000008_cron.sql` | `pg_cron` extension and the daily fan-out schedule |

**Tests** (all new except where noted):

| File | Responsibility |
|---|---|
`11_rls_coverage.test.sql` | *(modify)* extend the RLS guard to the `private` schema |
| `12_birthday_model.test.sql` | Birthday constraint matrix |
| `13_celebrate_counts.test.sql` | Incoming celebration edges, blocks excluded |
| `14_wish_history.test.sql` | Author keeps their own wish after un-celebrating |
| `15_birthday_stats.test.sql` | `my_birthday_stats()` under RLS |
| `16_device_tokens.test.sql` | Owner-only token rows |
| `17_reminders.test.sql` | Fan-out matching, wraparound, leap day, idempotency, drain |
| `18_resolve_contacts.test.sql` | Match-only resolution, suppressions honoured |
| `02_profiles.test.sql` | *(modify)* extend the R14 assertion to the new birthday columns |
| `03_people_graph.test.sql`, `08_gift_lifecycle.test.sql`, `10_ops.test.sql`, `seed.sql` | *(modify)* `tests.create_person` signature change |

**Edge Functions:**

| File | Responsibility |
|---|---|
| `supabase/functions/resolve_contacts/index.ts` | Accept `{phones: string[]}`, call `private.resolve_contacts`, return matches |
| `supabase/functions/drain_reminders/index.ts` | Claim a batch from the outbox, POST to FCM, stamp the result |

---

### Task 1: Extend the RLS coverage guard to the private schema

`11_rls_coverage.test.sql` scans only `public`. Task 7 adds `private.notification_outbox`, which could ship with RLS off and nothing would complain. Doing this first means every table added later is guarded on arrival.

**Files:**
- Modify: `supabase/tests/database/11_rls_coverage.test.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing callable. Adds one assertion that later tasks must keep green.

- [ ] **Step 1: Write the failing assertion**

In `supabase/tests/database/11_rls_coverage.test.sql`, change `select plan(2);` to `select plan(4);` and insert these assertions immediately before `select * from finish();`:

```sql
-- Private tables are server-only, but "server-only" is a schema property, not a
-- row property — service_role bypasses RLS and Edge Functions run as
-- service_role. RLS stays on so that a future policy is additive rather than a
-- retrofit, and so nothing is reachable if the schema is ever exposed.
select is_empty(
  $$ select c.relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'private'
       and c.relkind = 'r'
       and not c.relrowsecurity $$,
  'every private table has row level security enabled'
);

-- R3: the same PUBLIC-executable-by-default trap as R13, but in `public`, where
-- the private allowlist does not look. Later tasks add server-side wrapper
-- functions in public that must be callable by service_role and nobody else; a
-- forgotten revoke would hand every signed-in user a server-side entry point.
-- This is an ALLOWLIST: extend it only for a function clients are meant to call.
select is(
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'ops_get_delivery_address',
  'only intentionally client-callable public functions are executable'
);
```

- [ ] **Step 2: Prove the assertion can fail**

All three existing private tables already have RLS, so this passes immediately. That means it must be proved to discriminate, or it is an R8-class test that cannot fail.

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -c \
  "create table private.probe_no_rls (id bigint primary key);"
supabase test db supabase/tests/database/11_rls_coverage.test.sql
```

Expected: FAIL, naming `probe_no_rls` under "every private table has row level security enabled".

- [ ] **Step 3: Remove the probe and confirm green**

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -c \
  "drop table private.probe_no_rls;"
supabase test db
```

Expected: `Files=12, Tests=98, PASS`.

- [ ] **Step 4: Commit**

```bash
git add supabase/tests/database/11_rls_coverage.test.sql
git commit -m "test(db): guard RLS on private tables and public function grants"
```

---

### Task 2: Split the birthday model into month, day and optional year

The largest task in Phase 1 and the only one that rewrites working M0 code. It is atomic: the columns, the three functions, the sync trigger, the grant list and the fixtures must all move together or the suite is red in between.

**Files:**
- Create: `supabase/migrations/20260824000001_birthday_parts.sql`
- Create: `supabase/tests/database/12_birthday_model.test.sql`
- Modify: `supabase/seed.sql` (the `tests.create_person` helper)
- Modify: `supabase/tests/database/03_people_graph.test.sql` (4 `create_person` calls)
- Modify: `supabase/tests/database/08_gift_lifecycle.test.sql` (1 call, lines 9–15)
- Modify: `supabase/tests/database/10_ops.test.sql` (1 call, lines 15–18)
- Modify: `supabase/tests/database/02_profiles.test.sql` (extend the R14 assertion)

**Interfaces:**
- Consumes: `private.phone_hash(text)`, `public.profiles`, `public.people`.
- Produces:
  - `public.people.birth_month smallint`, `birth_day smallint`, `birth_year smallint`
  - `public.profiles.birth_month smallint`, `birth_day smallint`, `birth_year smallint`
  - `private.upsert_person(p_phone text, p_display_name text, p_birth_month smallint default null, p_birth_day smallint default null, p_birth_year smallint default null) returns bigint`
  - `private.claim_person(p_profile_id uuid, p_phone text) returns bigint` — signature unchanged
  - `tests.create_person(p_phone text, p_name text, p_birth_month smallint default null, p_birth_day smallint default null, p_birth_year smallint default null) returns bigint`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/12_birthday_model.test.sql`:

```sql
begin;
select plan(13);

select has_column('public', 'people', 'birth_month', 'people.birth_month exists');
select has_column('public', 'people', 'birth_day', 'people.birth_day exists');
select has_column('public', 'people', 'birth_year', 'people.birth_year exists');
select hasnt_column('public', 'people', 'birthday', 'the old people.birthday is gone');
select hasnt_column('public', 'profiles', 'date_of_birth', 'the old profiles.date_of_birth is gone');

select tests.as_postgres();

-- A year-less birthday is the common case from a device address book.
select lives_ok(
  $$ select tests.create_person('+919600000001', 'No Year', 3::smallint, 15::smallint) $$,
  'a birthday with no year is accepted'
);

select is(
  (select birth_month || '-' || birth_day || ' year=' || coalesce(birth_year::text, 'null')
     from public.people where display_name = 'No Year'),
  '3-15 year=null',
  'month and day are stored without a year'
);

-- Feb 29 must be storable with no year: it is a real birthday.
select lives_ok(
  $$ select tests.create_person('+919600000002', 'Leap Baby', 2::smallint, 29::smallint) $$,
  'Feb 29 is accepted with no year'
);

-- ...but not paired with a non-leap year.
select throws_ok(
  $$ select tests.create_person('+919600000003', 'Bad Leap', 2::smallint, 29::smallint, 2001::smallint) $$,
  '23514',
  null,
  'Feb 29 with a non-leap year is rejected'
);

-- Days must be valid for their month.
select throws_ok(
  $$ select tests.create_person('+919600000004', 'No Such Day', 4::smallint, 31::smallint) $$,
  '23514',
  null,
  'April 31 is rejected'
);

-- Month and day travel together.
select throws_ok(
  $$ insert into public.people (phone_e164_hash, display_name, birth_month)
     values (repeat('b', 64), 'Half A Date', 5::smallint) $$,
  '23514',
  null,
  'a month without a day is rejected at the table'
);

select throws_ok(
  $$ select tests.create_person('+919600000005', 'Half Again', 5::smallint) $$,
  '23514',
  'a birthday needs both a month and a day, or neither',
  'upsert_person rejects a half-known date with a readable message'
);

-- R14 recurs: dropping date_of_birth drops its column grant with it, so the new
-- columns need their own. Without this a user cannot edit their own birthday.
select is(
  (select has_column_privilege('authenticated', 'public.profiles', 'birth_month', 'UPDATE')::text
       || has_column_privilege('authenticated', 'public.profiles', 'birth_day', 'UPDATE')::text
       || has_column_privilege('authenticated', 'public.profiles', 'birth_year', 'UPDATE')::text),
  'truetruetrue',
  'a user may update their own birthday columns'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/12_birthday_model.test.sql
```

Expected: FAIL — `has_column` assertions fail because `birth_month` does not exist, and `tests.create_person` still has its old `date` signature.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000001_birthday_parts.sql`:

```sql
-- Reminders need a month and a day. A year is a bonus that device address books
-- frequently do not carry, and a `date` column cannot represent "March 15, year
-- unknown" at all. Splitting the column removes that whole class of problem.

-- ---------------------------------------------------------------- people

alter table public.people
  add column birth_month smallint,
  add column birth_day smallint,
  add column birth_year smallint;

update public.people
set birth_month = extract(month from birthday)::smallint,
    birth_day   = extract(day from birthday)::smallint,
    birth_year  = extract(year from birthday)::smallint
where birthday is not null;

alter table public.people drop constraint people_birthday_sane;
alter table public.people drop column birthday;

alter table public.people
  add constraint people_birth_parts_together
    check ((birth_month is null) = (birth_day is null)),
  add constraint people_birth_month_valid
    check (birth_month is null or birth_month between 1 and 12),
  add constraint people_birth_day_valid
    check (birth_day is null or birth_day between 1 and 31),
  add constraint people_birth_day_in_month
    check (
      birth_month is null or birth_day is null
      or birth_day <= case birth_month
           when 2 then 29
           when 4 then 30 when 6 then 30 when 9 then 30 when 11 then 30
           else 31 end
    ),
  add constraint people_birth_year_needs_parts
    check (birth_year is null or birth_month is not null),
  add constraint people_birth_year_sane
    check (birth_year is null
           or birth_year between 1900 and extract(year from current_date)::int),
  add constraint people_birth_leap_valid
    check (
      birth_year is null or birth_month is null
      or not (birth_month = 2 and birth_day = 29)
      or (birth_year % 4 = 0 and (birth_year % 100 <> 0 or birth_year % 400 = 0))
    );

-- The reminder fan-out matches month and day for an exact target date, so this
-- is an equality lookup. No date arithmetic, no December-to-January wraparound.
create index people_birth_parts_idx on public.people (birth_month, birth_day);

-- ---------------------------------------------------------------- profiles

-- The trigger is declared `after update of display_name, date_of_birth`, so it
-- depends on the column and the drop fails without removing it first. Verified:
-- "cannot drop column date_of_birth ... trigger profiles_sync_person depends on
-- column date_of_birth".
drop trigger profiles_sync_person on public.profiles;

alter table public.profiles
  add column birth_month smallint,
  add column birth_day smallint,
  add column birth_year smallint;

update public.profiles
set birth_month = extract(month from date_of_birth)::smallint,
    birth_day   = extract(day from date_of_birth)::smallint,
    birth_year  = extract(year from date_of_birth)::smallint
where date_of_birth is not null;

alter table public.profiles drop constraint profiles_dob_sane;
alter table public.profiles drop column date_of_birth;

alter table public.profiles
  add constraint profiles_birth_parts_together
    check ((birth_month is null) = (birth_day is null)),
  add constraint profiles_birth_month_valid
    check (birth_month is null or birth_month between 1 and 12),
  add constraint profiles_birth_day_valid
    check (birth_day is null or birth_day between 1 and 31),
  add constraint profiles_birth_day_in_month
    check (
      birth_month is null or birth_day is null
      or birth_day <= case birth_month
           when 2 then 29
           when 4 then 30 when 6 then 30 when 9 then 30 when 11 then 30
           else 31 end
    ),
  add constraint profiles_birth_year_needs_parts
    check (birth_year is null or birth_month is not null),
  add constraint profiles_birth_year_sane
    check (birth_year is null
           or birth_year between 1900 and extract(year from current_date)::int),
  add constraint profiles_birth_leap_valid
    check (
      birth_year is null or birth_month is null
      or not (birth_month = 2 and birth_day = 29)
      or (birth_year % 4 = 0 and (birth_year % 100 <> 0 or birth_year % 400 = 0))
    );

-- R14: date_of_birth carried `authenticated=w` and that grant died with the
-- column. Without these three the app cannot write a birthday and there is no
-- error to trace — the update simply affects nothing it was not granted.
grant update (birth_month, birth_day, birth_year) on public.profiles to authenticated;

-- ---------------------------------------------------------------- functions

create or replace function private.upsert_person(
  p_phone text,
  p_display_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := private.phone_hash(p_phone);
  v_id bigint;
begin
  -- A half-known date is a caller bug, and the table constraint would reject it
  -- with a message about a constraint rather than about the argument. Fail here
  -- where the reason is obvious.
  if (p_birth_month is null) <> (p_birth_day is null) then
    raise exception 'a birthday needs both a month and a day, or neither'
      using errcode = '23514';
  end if;

  if exists (select 1 from private.suppressions s where s.phone_e164_hash = v_hash) then
    return null;
  end if;

  select p.id into v_id from public.people p where p.phone_e164_hash = v_hash;

  if v_id is not null then
    -- Never overwrite a name or birthday the person set themselves; only fill
    -- blanks left by earlier imports.
    update public.people
    set birth_month = coalesce(birth_month, p_birth_month),
        birth_day   = coalesce(birth_day, p_birth_day),
        birth_year  = coalesce(birth_year, p_birth_year)
    where id = v_id and profile_id is null;
    return v_id;
  end if;

  insert into public.people (
    phone_e164_hash, display_name, birth_month, birth_day, birth_year
  )
  values (v_hash, p_display_name, p_birth_month, p_birth_day, p_birth_year)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function private.upsert_person(text, text, smallint, smallint, smallint)
  from public, anon, authenticated;

-- The old three-argument form would otherwise linger as a callable overload
-- taking a date, and callers would silently keep using it.
drop function if exists private.upsert_person(text, text, date);

create or replace function private.claim_person(
  p_profile_id uuid,
  p_phone text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := private.phone_hash(p_phone);
  v_id bigint;
  v_name text;
  v_month smallint;
  v_day smallint;
  v_year smallint;
begin
  select p.display_name, p.birth_month, p.birth_day, p.birth_year
    into v_name, v_month, v_day, v_year
  from public.profiles p where p.id = p_profile_id;

  insert into public.people (
    phone_e164_hash, display_name, birth_month, birth_day, birth_year, profile_id
  )
  values (v_hash, coalesce(v_name, 'New user'), v_month, v_day, v_year, p_profile_id)
  on conflict (phone_e164_hash) do update
    set profile_id  = p_profile_id,
        display_name = coalesce(v_name, public.people.display_name),
        birth_month = coalesce(v_month, public.people.birth_month),
        birth_day   = coalesce(v_day, public.people.birth_day),
        birth_year  = coalesce(v_year, public.people.birth_year)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function private.claim_person(uuid, text)
  from public, anon, authenticated;

create or replace function private.sync_person_from_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.people
  set display_name = new.display_name,
      birth_month = coalesce(new.birth_month, birth_month),
      birth_day   = coalesce(new.birth_day, birth_day),
      birth_year  = coalesce(new.birth_year, birth_year)
  where profile_id = new.id;
  return new;
end;
$$;

revoke execute on function private.sync_person_from_profile()
  from public, anon, authenticated;

create trigger profiles_sync_person
  after update of display_name, birth_month, birth_day, birth_year
  on public.profiles
  for each row execute function private.sync_person_from_profile();
```

- [ ] **Step 4: Update the seed helper**

In `supabase/seed.sql`, replace the whole `tests.create_person` function with:

```sql
create or replace function tests.create_person(
  p_phone text,
  p_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language sql
as $$
  select private.upsert_person(
    p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);
$$;
```

Keep it **above** the `grant usage on schema tests` block at the bottom of the file — `grant execute on all functions` is point-in-time, and a helper defined below it is unreachable from `authenticated`.

- [ ] **Step 5: Update the three M0 test files**

`03_people_graph.test.sql` — replace the four `create_person` calls:

```sql
select is(
  tests.create_person('+919000000001', 'Cousin Meera', 4::smallint, 12::smallint, 1995::smallint),
  tests.create_person('+919000000001', 'Meera', 4::smallint, 12::smallint, 1995::smallint),
  'the same phone number resolves to the same person row'
);
```

and

```sql
select private.suppress_person(
  tests.create_person('+919000000002', 'Nope')
);
select is(
  tests.create_person('+919000000002', 'Nope Again'),
  null,
  'a suppressed number returns null instead of a new person'
);
```

`08_gift_lifecycle.test.sql` — replace the R21 fixture block (lines 9–15) with:

```sql
-- Their birthday falls in five days. Month and day are all a reminder needs;
-- the year is optional and omitted here.
select tests.create_person(
  '+919300000002', 'Unregistered Friend',
  extract(month from current_date + 5)::smallint,
  extract(day from current_date + 5)::smallint);
```

`10_ops.test.sql` — replace the R21 fixture block (lines 15–18) with:

```sql
select tests.create_person(
  '+919500000002', 'Recipient Rita',
  extract(month from current_date + 2)::smallint,
  extract(day from current_date + 2)::smallint);
```

- [ ] **Step 6: Extend the R14 assertion in 02_profiles**

In `supabase/tests/database/02_profiles.test.sql`, change `select plan(9);` to `select plan(10);` and add this immediately before `select * from finish();`:

```sql
-- The birthday columns are new and R14's grant list had to be extended for
-- them. Prove the ordinary path works, because a missing column grant fails
-- silently rather than erroring.
select lives_ok(
  $$ update public.profiles
     set birth_month = 7::smallint, birth_day = 4::smallint
     where id = (select auth.uid()) $$,
  'a user can set their own birthday'
);
```

- [ ] **Step 7: Run the whole suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=13, Tests=112, PASS` — M0's 96 plus Task 1's private-RLS assertion, plus 12 birthday-model assertions and the new profiles assertion. If `03_people_graph`, `08_gift_lifecycle` or `10_ops` fails, a `create_person` call was missed; the error names the file and line.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260824000001_birthday_parts.sql \
        supabase/tests/database/12_birthday_model.test.sql \
        supabase/tests/database/02_profiles.test.sql \
        supabase/tests/database/03_people_graph.test.sql \
        supabase/tests/database/08_gift_lifecycle.test.sql \
        supabase/tests/database/10_ops.test.sql \
        supabase/seed.sql
git commit -m "feat(db): split birthday into month, day and optional year"
```

---

### Task 3: Expose incoming celebration edges

`celebrations_select_own` exposes only outgoing edges, so the Celebrates count — the "followers" half of the profile — is unreadable. This adds the reverse direction, minus anyone the viewer has blocked.

**Files:**
- Create: `supabase/migrations/20260824000002_celebrations_incoming.sql`
- Create: `supabase/tests/database/13_celebrate_counts.test.sql`

**Interfaces:**
- Consumes: `private.my_person_id()`, `public.blocks`, `private.claim_person(uuid, text)`.
- Produces: policy `celebrations_select_incoming` on `public.celebrations`. No new functions, so the `01_private.test.sql` allowlist is unchanged.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/13_celebrate_counts.test.sql`:

```sql
begin;
select plan(4);

select tests.as_postgres();
select tests.create_user('starkid');
select tests.create_user('fanone');
select tests.create_user('fantwo');
select private.claim_person((select id from public.profiles where handle = 'starkid'), '+919700000001');
select private.claim_person((select id from public.profiles where handle = 'fanone'), '+919700000002');
select private.claim_person((select id from public.profiles where handle = 'fantwo'), '+919700000003');

-- Both fans celebrate the star. The star celebrates nobody.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select p.id,
       (select id from public.people where profile_id =
          (select id from public.profiles where handle = 'starkid')),
       'contacts'
from public.profiles p where p.handle in ('fanone', 'fantwo');

-- R22: resolve ids while still postgres. profiles_select_own hides other
-- users' rows from an authenticated session, so a lookup by handle from inside
-- one returns NULL.
create temporary table ids as
select
  (select id from public.profiles where handle = 'starkid') as star,
  (select id from public.profiles where handle = 'fanone')  as fan_one,
  (select id from public.profiles where handle = 'fantwo')  as fan_two;
grant select on ids to authenticated;

select tests.as_user((select star from ids));

select is(
  (select count(*)::int from public.celebrations),
  2,
  'the star sees both people who celebrate them'
);

-- A fan sees only their own outgoing edge, never the other fan's.
select tests.as_postgres();
select tests.as_user((select fan_one from ids));
select is(
  (select count(*)::int from public.celebrations),
  1,
  'a fan sees only their own outgoing edge'
);

-- Blocking removes a celebrator from the list.
select tests.as_postgres();
insert into public.blocks (blocker_profile_id, blocked_profile_id)
values ((select star from ids), (select fan_two from ids));

select tests.as_user((select star from ids));
select is(
  (select count(*)::int from public.celebrations),
  1,
  'a blocked celebrator drops out of the Celebrates list'
);

-- And the surviving row is the one that was not blocked.
select is(
  (select celebrator_profile_id from public.celebrations),
  (select fan_one from ids),
  'the remaining celebrator is the unblocked fan'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/13_celebrate_counts.test.sql
```

Expected: FAIL on "the star sees both people who celebrate them" — `have: 0, want: 2`, because only outgoing edges are visible.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000002_celebrations_incoming.sql`:

```sql
-- The Celebrates count and list — the "followers" half of the profile — needs
-- the reverse direction of the edge. celebrations_select_own covers only the
-- outgoing direction, so a user could not see who celebrates them at all.
--
-- This is additive: it grants sight of edges pointing AT the viewer's person,
-- and nothing about edges between two other people.
create policy celebrations_select_incoming
  on public.celebrations
  for select
  to authenticated
  using (
    person_id = (select private.my_person_id())
    and not exists (
      select 1 from public.blocks b
      where b.blocker_profile_id = (select auth.uid())
        and b.blocked_profile_id = celebrations.celebrator_profile_id
    )
  );
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=14, Tests=116, PASS`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260824000002_celebrations_incoming.sql \
        supabase/tests/database/13_celebrate_counts.test.sql
git commit -m "feat(db): let a user see who celebrates them"
```

---

### Task 4: Stop the track record from forgetting

`wishes_select_visible` gates on `can_see_person(subject)`. Un-celebrating someone therefore erases your own past wish to them from your history — which contradicts the whole point of a per-year track record.

**Files:**
- Create: `supabase/migrations/20260824000003_wishes_author_visibility.sql`
- Create: `supabase/tests/database/14_wish_history.test.sql`

**Interfaces:**
- Consumes: `private.can_see_person(bigint)`, `public.wishes`.
- Produces: replaced policy `wishes_select_visible` on `public.wishes`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/14_wish_history.test.sql`:

```sql
begin;
select plan(3);

select tests.as_postgres();
select tests.create_user('wellwisher');
select tests.create_user('recipient');
select private.claim_person((select id from public.profiles where handle = 'wellwisher'), '+919800000001');
select private.claim_person((select id from public.profiles where handle = 'recipient'), '+919800000002');

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'wellwisher'),
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'recipient')),
  'contacts'
);

create temporary table ids as
select
  (select id from public.profiles where handle = 'wellwisher') as author,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'recipient')) as subject;
grant select on ids to authenticated;

select tests.as_user((select author from ids));

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select auth.uid()), (select subject from ids), 'Have a good one',
        extract(year from current_date)::int);

select is(
  (select count(*)::int from public.wishes),
  1,
  'an author sees the wish they just posted'
);

-- Now stop celebrating them. The edge is what can_see_person depends on.
delete from public.celebrations where celebrator_profile_id = (select auth.uid());

select is(
  (select count(*)::int from public.people),
  1,
  'after un-celebrating, the subject is no longer visible as a person'
);

-- The wish is history. It must survive the graph changing under it.
select is(
  (select count(*)::int from public.wishes),
  1,
  'an author still sees their own wish after un-celebrating the subject'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/14_wish_history.test.sql
```

Expected: FAIL on the third assertion — `have: 0, want: 1`. The first two pass, which is what proves the failure is about authorship and not about the fixture.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000003_wishes_author_visibility.sql`:

```sql
-- A wish is a record of something you did. Its visibility to its own author
-- must not depend on whether the celebration edge still exists, or the per-year
-- track record silently loses rows every time someone tidies their list.
--
-- The subject-side branch is unchanged: everyone who can see the person can
-- still see the wishes on their wall.
drop policy wishes_select_visible on public.wishes;

create policy wishes_select_visible
  on public.wishes
  for select
  to authenticated
  using (
    author_profile_id = (select auth.uid())
    or (select private.can_see_person(wishes.subject_person_id))
  );
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=15, Tests=119, PASS`. `09_wishes.test.sql` must still pass — its assertions cover the subject-side branch this migration leaves alone.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260824000003_wishes_author_visibility.sql \
        supabase/tests/database/14_wish_history.test.sql
git commit -m "fix(db): an author keeps sight of their own wishes"
```

---

### Task 5: Per-year statistics function

The profile's track record needs a per-year rollup. PostgREST's aggregate support is inconsistent across versions, and a function is testable as a real user.

**Files:**
- Create: `supabase/migrations/20260824000004_birthday_stats.sql`
- Create: `supabase/tests/database/15_birthday_stats.test.sql`

**Interfaces:**
- Consumes: `public.wishes`, `private.my_person_id()`.
- Produces: `public.my_birthday_stats() returns table (stat_year int, wishes_sent int, wishes_received int, birthdays_celebrated int)`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/15_birthday_stats.test.sql`:

```sql
begin;
select plan(4);

select tests.as_postgres();
select tests.create_user('counter');
select tests.create_user('friendone');
select tests.create_user('friendtwo');
select private.claim_person((select id from public.profiles where handle = 'counter'), '+919900000001');
select private.claim_person((select id from public.profiles where handle = 'friendone'), '+919900000002');
select private.claim_person((select id from public.profiles where handle = 'friendtwo'), '+919900000003');

-- counter celebrates both friends; friendone celebrates counter back.
insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select id from public.profiles where handle = 'counter'), p.id, 'contacts'
from public.people p
where p.profile_id in (
  select id from public.profiles where handle in ('friendone', 'friendtwo'));

insert into public.celebrations (celebrator_profile_id, person_id, source)
values (
  (select id from public.profiles where handle = 'friendone'),
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'counter')),
  'contacts'
);

create temporary table ids as
select
  (select id from public.profiles where handle = 'counter') as me,
  (select id from public.profiles where handle = 'friendone') as f_one,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'friendone')) as p_one,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'friendtwo')) as p_two,
  (select id from public.people where profile_id =
     (select id from public.profiles where handle = 'counter')) as p_me,
  extract(year from current_date)::int as this_year;
grant select on ids to authenticated;

-- counter wishes both friends; friendone wishes counter.
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values
  ((select me from ids),    (select p_one from ids), 'Happy day one', (select this_year from ids)),
  ((select me from ids),    (select p_two from ids), 'Happy day two', (select this_year from ids)),
  ((select f_one from ids), (select p_me from ids),  'You too',       (select this_year from ids));

select tests.as_user((select me from ids));

select is(
  (select wishes_sent from public.my_birthday_stats()
    where stat_year = (select this_year from ids)),
  2,
  'wishes sent counts both wishes I wrote'
);

select is(
  (select wishes_received from public.my_birthday_stats()
    where stat_year = (select this_year from ids)),
  1,
  'wishes received counts the wish written to me'
);

select is(
  (select birthdays_celebrated from public.my_birthday_stats()
    where stat_year = (select this_year from ids)),
  2,
  'birthdays celebrated counts distinct people I wished'
);

-- A second wish to the same person in a later year must not inflate this year.
select tests.as_postgres();
insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
values ((select me from ids), (select p_one from ids), 'Next year',
        (select this_year from ids) + 1);

select tests.as_user((select me from ids));
select is(
  (select count(*)::int from public.my_birthday_stats()),
  2,
  'stats are grouped per year, one row each'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/15_birthday_stats.test.sql
```

Expected: FAIL with `function public.my_birthday_stats() does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000004_birthday_stats.sql`:

```sql
-- The profile's per-year track record. `security invoker` on purpose: RLS still
-- applies, so this function cannot see a wish the caller could not already read
-- directly, and it is testable as a real signed-in user rather than as postgres.
--
-- birthdays_celebrated is DISTINCT subject people, which diverges from
-- wishes_sent once a cake post and a typed message can both land on the same
-- person in the same year.
create or replace function public.my_birthday_stats()
returns table (
  stat_year int,
  wishes_sent int,
  wishes_received int,
  birthdays_celebrated int
)
language sql
stable
security invoker
set search_path = ''
as $$
  with mine as (
    select w.occasion_year, w.author_profile_id, w.subject_person_id
    from public.wishes w
  ),
  me as (
    select (select auth.uid()) as profile_id,
           (select private.my_person_id()) as person_id
  )
  select
    m.occasion_year as stat_year,
    count(*) filter (where m.author_profile_id = (select profile_id from me))::int,
    count(*) filter (where m.subject_person_id = (select person_id from me))::int,
    count(distinct m.subject_person_id)
      filter (where m.author_profile_id = (select profile_id from me))::int
  from mine m
  group by m.occasion_year
  order by m.occasion_year desc;
$$;

-- Lives in public and is called by the app, so authenticated keeps execute.
-- It is security invoker, so that grant confers no privilege of its own.
revoke execute on function public.my_birthday_stats() from public, anon;
grant execute on function public.my_birthday_stats() to authenticated;
```

- [ ] **Step 4: Extend the public-function allowlist**

This task grants `authenticated` execute on a new `public` function, so Task 1's
allowlist must be widened deliberately. In `supabase/tests/database/11_rls_coverage.test.sql`,
change the expected string:

```sql
  'my_birthday_stats,ops_get_delivery_address',
```

Alphabetical order matters — the query sorts by `proname`.

- [ ] **Step 5: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=16, Tests=123, PASS`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260824000004_birthday_stats.sql \
        supabase/tests/database/15_birthday_stats.test.sql \
        supabase/tests/database/11_rls_coverage.test.sql
git commit -m "feat(db): add per-year birthday stats for the profile"
```

---

### Task 6: Device tokens

Push needs somewhere to record a device. A user's own token needs no server mediation, so the app writes it directly under owner-only RLS.

**Files:**
- Create: `supabase/migrations/20260824000005_device_tokens.sql`
- Create: `supabase/tests/database/16_device_tokens.test.sql`

**Interfaces:**
- Consumes: `public.profiles`.
- Produces: `public.device_tokens(id bigint, profile_id uuid, token text unique, platform text, created_at timestamptz, last_seen_at timestamptz)`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/16_device_tokens.test.sql`:

```sql
begin;
select plan(5);

select has_table('public', 'device_tokens', 'device_tokens exists');

select tests.as_postgres();
select tests.create_user('phoneowner');
select tests.create_user('nosyuser');

create temporary table ids as
select
  (select id from public.profiles where handle = 'phoneowner') as owner,
  (select id from public.profiles where handle = 'nosyuser')   as nosy;
grant select on ids to authenticated;

select tests.as_user((select owner from ids));

select lives_ok(
  $$ insert into public.device_tokens (profile_id, token, platform)
     values ((select auth.uid()), 'fcm-token-owner', 'android') $$,
  'a user registers their own device token'
);

-- Another user must not be able to read it.
select tests.as_postgres();
select tests.as_user((select nosy from ids));
select is(
  (select count(*)::int from public.device_tokens),
  0,
  'another user cannot read my device token'
);

-- Nor forge one in my name.
select throws_ok(
  $$ insert into public.device_tokens (profile_id, token, platform)
     values ((select owner from ids), 'fcm-token-forged', 'ios') $$,
  '42501',
  null,
  'another user cannot register a token in my name'
);

-- Platform is constrained: a typo must not reach the FCM drain.
select tests.as_postgres();
select tests.as_user((select owner from ids));
select throws_ok(
  $$ insert into public.device_tokens (profile_id, token, platform)
     values ((select auth.uid()), 'fcm-token-bad-platform', 'windowsphone') $$,
  '23514',
  null,
  'an unknown platform is rejected'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/16_device_tokens.test.sql
```

Expected: FAIL — `relation "public.device_tokens" does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000005_device_tokens.sql`:

```sql
-- One row per device per user. The token is the user's own property, so the app
-- writes it directly rather than through an Edge Function; RLS is the boundary.
create table public.device_tokens (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_tokens_platform_valid check (platform in ('ios', 'android'))
);

create index device_tokens_profile_id_idx on public.device_tokens (profile_id);

alter table public.device_tokens enable row level security;

-- for all: the app inserts on sign-in, updates last_seen_at, and deletes on
-- sign-out. A signed-out device that keeps its row keeps receiving someone
-- else's reminders.
create policy device_tokens_all_own
  on public.device_tokens
  for all
  to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=17, Tests=128, PASS`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260824000005_device_tokens.sql \
        supabase/tests/database/16_device_tokens.test.sql
git commit -m "feat(db): add device_tokens with owner-only access"
```

---

### Task 7: Reminder outbox, fan-out and drain helpers

The heart of Phase 1. All scheduling logic lives here so it is pgTAP-testable; the Edge Function in Task 11 only makes an HTTP call.

**Files:**
- Create: `supabase/migrations/20260824000006_reminders.sql`
- Create: `supabase/tests/database/17_reminders.test.sql`

**Interfaces:**
- Consumes: `public.celebrations`, `public.people`, `public.device_tokens`.
- Produces:
  - `private.notification_outbox` table
  - `private.enqueue_reminders(p_today date default current_date) returns int`
  - `private.next_reminder_batch(p_limit int default 100) returns table (outbox_id bigint, token text, platform text, subject_name text, offset_days smallint, occasion_date date)`
  - `private.mark_reminder_sent(p_outbox_id bigint) returns void`
  - `private.mark_reminder_failed(p_outbox_id bigint, p_error text) returns void`
  - `public.rpc_next_reminder_batch(int)`, `public.rpc_mark_reminder_sent(bigint)`,
    `public.rpc_mark_reminder_failed(bigint, text)` — service_role-only wrappers,
    because PostgREST cannot reach the `private` schema (R2)

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/17_reminders.test.sql`:

```sql
begin;
select plan(8);

select has_table('private', 'notification_outbox', 'the outbox exists');

select tests.as_postgres();
select tests.create_user('remindme');
select private.claim_person((select id from public.profiles where handle = 'remindme'), '+919110000001');

-- A friend whose birthday is exactly seven days from a fixed reference date.
-- The reference date is passed in, so these assertions never depend on today.
select tests.create_person('+919110000002', 'Week Away', 1::smallint, 8::smallint);
select tests.create_person('+919110000003', 'Leap Friend', 2::smallint, 29::smallint);

insert into public.celebrations (celebrator_profile_id, person_id, source)
select (select id from public.profiles where handle = 'remindme'), p.id, 'contacts'
from public.people p where p.display_name in ('Week Away', 'Leap Friend');

-- December-to-January wraparound: reference 2027-01-01, T-7 lands on 2027-01-08.
select is(
  private.enqueue_reminders(date '2027-01-01'),
  1,
  'a birthday seven days ahead across the new year is queued'
);

select is(
  (select offset_days || ' on ' || occasion_date
     from private.notification_outbox
     order by id desc limit 1),
  '7 on 2027-01-08',
  'the queued row carries the T-7 offset and the occasion date'
);

-- Running the same day twice must not double-send. The unique constraint is the
-- guarantee; this asserts it is actually doing the work.
select is(
  private.enqueue_reminders(date '2027-01-01'),
  0,
  'a second run on the same day queues nothing'
);

select is(
  (select count(*)::int from private.notification_outbox),
  1,
  'and the outbox still holds exactly one row'
);

-- Feb 29 in a non-leap year fires on Feb 28, so a T-0 run on 2027-02-28 finds it.
select is(
  private.enqueue_reminders(date '2027-02-28'),
  1,
  'a Feb 29 birthday is reminded on Feb 28 in a non-leap year'
);

-- ...and in a leap year it fires on the real date, not twice.
select is(
  private.enqueue_reminders(date '2028-02-29'),
  1,
  'in a leap year the Feb 29 birthday fires on Feb 29'
);

-- The drain sees only rows with a device to send to.
select tests.as_postgres();
select is(
  (select count(*)::int from private.next_reminder_batch()),
  0,
  'a user with no registered device yields nothing to send'
);

insert into public.device_tokens (profile_id, token, platform)
values ((select id from public.profiles where handle = 'remindme'), 'fcm-remind', 'android');

select isnt_empty(
  $$ select outbox_id from private.next_reminder_batch() $$,
  'once a device is registered the batch has work'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/17_reminders.test.sql
```

Expected: FAIL — `has_table` fails and `private.enqueue_reminders(date) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000006_reminders.sql`:

```sql
-- Scheduling lives in the database so it is testable without deploying
-- anything. The Edge Function that drains this table does only the HTTP call.
--
-- private, not public: nothing client-side reads it, and PostgREST cannot see
-- the private schema at all, so the API surface stays closed by construction.
create table private.notification_outbox (
  id bigint generated always as identity primary key,
  recipient_profile_id uuid not null references public.profiles (id) on delete cascade,
  subject_person_id bigint not null references public.people (id) on delete cascade,
  kind text not null default 'reminder',
  offset_days smallint not null,
  occasion_date date not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts int not null default 0,
  last_error text,
  constraint notification_outbox_kind_valid check (kind in ('reminder')),
  constraint notification_outbox_offset_valid check (offset_days in (7, 1, 0)),
  -- THE no-double-send guarantee. A cron re-run, a retry, or two overlapping
  -- schedules cannot produce a second notification for the same person, day and
  -- offset. Idempotency is a constraint here, not a convention.
  constraint notification_outbox_once
    unique (recipient_profile_id, subject_person_id, occasion_date, offset_days)
);

create index notification_outbox_unsent_idx
  on private.notification_outbox (sent_at, id)
  where sent_at is null;

create index notification_outbox_subject_idx
  on private.notification_outbox (subject_person_id);

alter table private.notification_outbox enable row level security;
-- No policies: service_role only, which is what the drain runs as.

-- Queue every reminder due relative to p_today. Returns the number of rows
-- actually inserted, so "0" is a meaningful answer meaning "nothing new".
create or replace function private.enqueue_reminders(p_today date default current_date)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted int := 0;
  v_offset smallint;
  v_target date;
  v_match_month smallint;
  v_match_day smallint;
begin
  foreach v_offset in array array[7, 1, 0]::smallint[]
  loop
    v_target := p_today + v_offset;
    v_match_month := extract(month from v_target)::smallint;
    v_match_day := extract(day from v_target)::smallint;

    -- A Feb 29 birthday has no Feb 29 to land on in a common year, so it is
    -- observed on Feb 28 — inside February, rather than sliding into March.
    -- On Feb 28 of a common year we therefore match both 28 and 29.
    with due as (
      insert into private.notification_outbox (
        recipient_profile_id, subject_person_id, offset_days, occasion_date
      )
      select c.celebrator_profile_id, p.id, v_offset, v_target
      from public.celebrations c
      join public.people p on p.id = c.person_id
      where p.birth_month is not null
        and p.birth_month = v_match_month
        and (
          p.birth_day = v_match_day
          or (
            v_match_month = 2 and v_match_day = 28
            and p.birth_day = 29
            and not (
              extract(year from v_target)::int % 4 = 0
              and (extract(year from v_target)::int % 100 <> 0
                   or extract(year from v_target)::int % 400 = 0)
            )
          )
        )
      on conflict on constraint notification_outbox_once do nothing
      returning 1
    )
    select v_inserted + count(*)::int into v_inserted from due;
  end loop;

  return v_inserted;
end;
$$;

revoke execute on function private.enqueue_reminders(date)
  from public, anon, authenticated;

-- What the drain reads. Joins to device_tokens so a user with no device yields
-- no work, and exposes only what a push notification needs.
create or replace function private.next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  select o.id, d.token, d.platform, p.display_name, o.offset_days, o.occasion_date
  from private.notification_outbox o
  join public.device_tokens d on d.profile_id = o.recipient_profile_id
  join public.people p on p.id = o.subject_person_id
  where o.sent_at is null
    and o.attempts < 5
  order by o.id
  limit p_limit;
$$;

revoke execute on function private.next_reminder_batch(int)
  from public, anon, authenticated;

create or replace function private.mark_reminder_sent(p_outbox_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.notification_outbox
  set sent_at = now(), last_error = null
  where id = p_outbox_id;
$$;

revoke execute on function private.mark_reminder_sent(bigint)
  from public, anon, authenticated;

create or replace function private.mark_reminder_failed(
  p_outbox_id bigint,
  p_error text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.notification_outbox
  set attempts = attempts + 1, last_error = p_error
  where id = p_outbox_id;
$$;

revoke execute on function private.mark_reminder_failed(bigint, text)
  from public, anon, authenticated;

-- ------------------------------------------------------------- rpc surface

-- R2: PostgREST exposes only the schemas in config.toml's `[api] schemas`,
-- which is ["public", "graphql_public"]. An Edge Function therefore CANNOT call
-- a private function directly — verified against the running stack, a request
-- with `Content-Profile: private` returns PGRST106 "Invalid schema: private".
--
-- Adding `private` to that list was rejected: the point of the private schema is
-- that it is unreachable through the API by construction, not merely by grant.
-- Instead each function the drain needs gets a thin public wrapper granted to
-- service_role and nobody else. Task 1's public allowlist assertion is what
-- catches a forgotten revoke here.
create or replace function public.rpc_next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  select * from private.next_reminder_batch(p_limit);
$$;

revoke execute on function public.rpc_next_reminder_batch(int)
  from public, anon, authenticated;
grant execute on function public.rpc_next_reminder_batch(int) to service_role;

create or replace function public.rpc_mark_reminder_sent(p_outbox_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.mark_reminder_sent(p_outbox_id);
$$;

revoke execute on function public.rpc_mark_reminder_sent(bigint)
  from public, anon, authenticated;
grant execute on function public.rpc_mark_reminder_sent(bigint) to service_role;

create or replace function public.rpc_mark_reminder_failed(
  p_outbox_id bigint,
  p_error text
)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.mark_reminder_failed(p_outbox_id, p_error);
$$;

revoke execute on function public.rpc_mark_reminder_failed(bigint, text)
  from public, anon, authenticated;
grant execute on function public.rpc_mark_reminder_failed(bigint, text) to service_role;
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=18, Tests=136, PASS`. `01_private.test.sql`'s allowlist must still read `'can_see_person,is_staff,my_person_id'` — none of the four new functions is called by a policy, so all four are revoked from `authenticated` and the allowlist does not change. If it fails, a `revoke` was missed and the failure names the function.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260824000006_reminders.sql \
        supabase/tests/database/17_reminders.test.sql
git commit -m "feat(db): add reminder outbox with idempotent fan-out"
```

---

### Task 8: Match-only contact resolution

Importing must not mint a `people` row for every contact in an address book. This resolves phone numbers to existing people and creates nothing, so the caller can show a picker and only then commit.

**Files:**
- Create: `supabase/migrations/20260824000007_resolve_contacts.sql`
- Create: `supabase/tests/database/18_resolve_contacts.test.sql`

**Interfaces:**
- Consumes: `private.phone_hash(text)`, `private.suppressions`, `public.people`.
- Produces:
  - `private.resolve_contacts(p_phones text[]) returns table (phone text, person_id bigint, display_name text, birth_month smallint, birth_day smallint)`
  - `public.rpc_resolve_contacts(text[])` — an identical service_role-only wrapper, because PostgREST cannot reach the `private` schema (R2)

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/database/18_resolve_contacts.test.sql`:

```sql
begin;
select plan(5);

select tests.as_postgres();

-- One number already known to the app, one never seen, one suppressed.
select tests.create_person('+919120000001', 'Known Friend', 6::smallint, 10::smallint);
select private.suppress_person(
  tests.create_person('+919120000002', 'Opted Out')
);

select is(
  (select person_id from private.resolve_contacts(array['+919120000001'])),
  (select id from public.people where display_name = 'Known Friend'),
  'a known number resolves to its existing person'
);

select is(
  (select display_name from private.resolve_contacts(array['+919120000001'])),
  'Known Friend',
  'the match carries the name the app needs to show'
);

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000099']) $$,
  'an unknown number resolves to nothing'
);

select is_empty(
  $$ select phone from private.resolve_contacts(array['+919120000002']) $$,
  'a suppressed number never resolves, even though a hash once existed'
);

-- The whole point: resolving is read-only.
select is(
  (select count(*)::int from public.people),
  1,
  'resolving unknown numbers creates no people rows'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/18_resolve_contacts.test.sql
```

Expected: FAIL with `function private.resolve_contacts(text[]) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000007_resolve_contacts.sql`:

```sql
-- Match an address book against people the app already knows, and create
-- nothing. A bulk import that upserted would mint a row for every contact of
-- every user — thousands of people who never consented to anything — so the
-- row is minted later, by upsert_person, only when the user picks someone.
--
-- Hashing happens here because the pepper lives in private.config and must
-- never leave the database. That is why raw numbers reach the server at all.
create or replace function private.resolve_contacts(p_phones text[])
returns table (
  phone text,
  person_id bigint,
  display_name text,
  birth_month smallint,
  birth_day smallint
)
language sql
security definer
set search_path = ''
stable
as $$
  select c.phone, p.id, p.display_name, p.birth_month, p.birth_day
  from unnest(p_phones) as c(phone)
  join public.people p
    on p.phone_e164_hash = private.phone_hash(c.phone)
  where not exists (
    select 1 from private.suppressions s
    where s.phone_e164_hash = p.phone_e164_hash
  );
$$;

revoke execute on function private.resolve_contacts(text[])
  from public, anon, authenticated;

-- R2: the Edge Function reaches this through a public wrapper, because
-- PostgREST exposes only public and graphql_public. service_role only.
create or replace function public.rpc_resolve_contacts(p_phones text[])
returns table (
  phone text,
  person_id bigint,
  display_name text,
  birth_month smallint,
  birth_day smallint
)
language sql
security definer
set search_path = ''
stable
as $$
  select * from private.resolve_contacts(p_phones);
$$;

revoke execute on function public.rpc_resolve_contacts(text[])
  from public, anon, authenticated;
grant execute on function public.rpc_resolve_contacts(text[]) to service_role;
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=19, Tests=141, PASS`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260824000007_resolve_contacts.sql \
        supabase/tests/database/18_resolve_contacts.test.sql
git commit -m "feat(db): resolve contacts to known people without creating any"
```

---

### Task 9: Schedule the daily fan-out

`private.enqueue_reminders` is proven; this makes it run.

**Files:**
- Create: `supabase/migrations/20260824000008_cron.sql`
- Modify: `supabase/tests/database/17_reminders.test.sql` (one assertion)

**Interfaces:**
- Consumes: `private.enqueue_reminders(date)`.
- Produces: a `cron.job` row named `birthday-reminder-fanout`.

- [ ] **Step 1: Write the failing assertion**

In `supabase/tests/database/17_reminders.test.sql`, change `select plan(8);` to `select plan(9);` and add before `select * from finish();`:

```sql
-- The fan-out is useless unless something runs it. pg_cron stores schedules as
-- rows, so the schedule itself is assertable.
select is(
  (select schedule from cron.job where jobname = 'birthday-reminder-fanout'),
  '0 3 * * *',
  'the reminder fan-out is scheduled daily'
);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
supabase test db supabase/tests/database/17_reminders.test.sql
```

Expected: FAIL — `relation "cron.job" does not exist`, because the extension is not created yet.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260824000008_cron.sql`:

```sql
-- pg_cron is already in shared_preload_libraries on both local and hosted
-- Supabase, so creating the extension is all that is required.
--
-- No `with schema` clause: pg_cron's control file pins it to pg_catalog and it
-- creates its own `cron` schema for cron.job regardless. Verified on this
-- database as the non-superuser `postgres` role: cron.job is reachable and
-- cron.schedule returns a job id.
create extension if not exists pg_cron;

-- 03:00 UTC. Reminders are day-granular, so the exact hour only needs to be
-- early enough that a T-0 reminder arrives on the morning of the day itself.
-- unschedule first so re-running a reset does not accumulate duplicate jobs.
select cron.unschedule('birthday-reminder-fanout')
where exists (select 1 from cron.job where jobname = 'birthday-reminder-fanout');

select cron.schedule(
  'birthday-reminder-fanout',
  '0 3 * * *',
  $$ select private.enqueue_reminders(); $$
);
```

- [ ] **Step 4: Run the suite**

```bash
supabase db reset && supabase test db
```

Expected: `Files=19, Tests=142, PASS`.

If `create extension pg_cron` fails with a message about the database, note that pg_cron can only be installed in one database per cluster; on local Supabase that database is `postgres`, which is where migrations run, so this should succeed. Do not work around a failure here by dropping the assertion — stop and report.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260824000008_cron.sql \
        supabase/tests/database/17_reminders.test.sql
git commit -m "feat(db): schedule the daily reminder fan-out"
```

---

### Task 10: `resolve_contacts` Edge Function

A thin wrapper. It exists only because the app cannot reach a `private` function directly.

**Files:**
- Create: `supabase/functions/resolve_contacts/index.ts`
- Create: `supabase/functions/resolve_contacts/deno.json`

**Interfaces:**
- Consumes: `public.rpc_resolve_contacts(text[])` — the service_role-only wrapper from Task 8 (R2).
- Produces: `POST /functions/v1/resolve_contacts` with body `{"phones": string[]}` returning `{"matches": [{phone, person_id, display_name, birth_month, birth_day}]}`.

- [ ] **Step 1: Write the function**

Create `supabase/functions/resolve_contacts/index.ts`:

```ts
// Thin wrapper. All matching logic is private.resolve_contacts, which is
// covered by 18_resolve_contacts.test.sql. This adds only the HTTP shape.
//
// Raw phone numbers arrive here and are passed straight to Postgres, which
// hashes them with a pepper that never leaves the database. Nothing raw is
// stored or logged.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BATCH = 500;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return new Response(JSON.stringify({ error: "missing authorization" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  let phones: unknown;
  try {
    ({ phones } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (!Array.isArray(phones) || phones.some((p) => typeof p !== "string")) {
    return new Response(JSON.stringify({ error: "phones must be string[]" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (phones.length > MAX_BATCH) {
    return new Response(
      JSON.stringify({ error: `at most ${MAX_BATCH} phones per request` }),
      { status: 413, headers: { "content-type": "application/json" } },
    );
  }

  // service_role: private.resolve_contacts is revoked from every client role,
  // and the caller's own identity is not needed — resolution is the same for
  // everyone, and it creates nothing.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Confirm the caller is a real signed-in user before doing any work.
  const caller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  // R2: no .schema("private") — PostgREST exposes only public and
  // graphql_public, so the private function is reached through its
  // service_role-only public wrapper.
  const { data, error } = await admin
    .rpc("rpc_resolve_contacts", { p_phones: phones });

  if (error) {
    console.error("resolve_contacts failed", error.message);
    return new Response(JSON.stringify({ error: "resolution failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ matches: data ?? [] }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
```

Create `supabase/functions/resolve_contacts/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

- [ ] **Step 2: Serve the function and exercise the error paths**

```bash
supabase functions serve resolve_contacts --no-verify-jwt &
sleep 5
curl -s -X GET  http://127.0.0.1:54321/functions/v1/resolve_contacts
curl -s -X POST http://127.0.0.1:54321/functions/v1/resolve_contacts \
  -H 'Authorization: Bearer test' -H 'content-type: application/json' \
  -d '{"phones": "not-an-array"}'
```

Expected: the first returns `{"error":"method not allowed"}`, the second `{"error":"phones must be string[]"}`.

- [ ] **Step 3: Exercise the happy path**

Seed a known person, then call with a real user's JWT. Get the anon key and a token from `supabase status`.

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -c \
  "select private.upsert_person('+919130000001','Curl Friend',9::smallint,9::smallint);"
```

Then POST `{"phones":["+919130000001","+919130000999"]}` with a valid `Authorization: Bearer <user jwt>`.

Expected: one match for `+919130000001` carrying `display_name: "Curl Friend"`, and no entry for the unknown number. Confirm nothing was created:

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select count(*) from public.people where display_name = 'Curl Friend';"
```

Expected: `1` — the one seeded, not two.

- [ ] **Step 4: Stop the server and commit**

```bash
kill %1
git add supabase/functions/resolve_contacts/
git commit -m "feat(functions): add resolve_contacts wrapper"
```

---

### Task 11: `drain_reminders` Edge Function

The only part of the reminder pipeline that cannot live in Postgres: the HTTP call to FCM.

**Files:**
- Create: `supabase/functions/drain_reminders/index.ts`
- Create: `supabase/functions/drain_reminders/deno.json`

**Interfaces:**
- Consumes: `public.rpc_next_reminder_batch(int)`, `public.rpc_mark_reminder_sent(bigint)`, `public.rpc_mark_reminder_failed(bigint, text)` — the service_role-only wrappers from Task 7 (R2).
- Produces: `POST /functions/v1/drain_reminders` returning `{"sent": n, "failed": n}`.

- [ ] **Step 1: Write the function**

Create `supabase/functions/drain_reminders/index.ts`:

```ts
// Drains private.notification_outbox to FCM. Everything about WHICH reminders
// are due lives in the database and is covered by 17_reminders.test.sql; this
// file is transport only.
//
// FCM_SERVER_KEY is absent until a Firebase project exists. Rather than fail,
// the function runs in dry-run mode: it reports what it would have sent and
// leaves the rows unsent, so the pipeline is exercisable before credentials.
import { createClient } from "jsr:@supabase/supabase-js@2";

type Reminder = {
  outbox_id: number;
  token: string;
  platform: string;
  subject_name: string;
  offset_days: number;
  occasion_date: string;
};

function body(r: Reminder): string {
  if (r.offset_days === 0) return `It's ${r.subject_name}'s birthday today.`;
  if (r.offset_days === 1) return `${r.subject_name}'s birthday is tomorrow.`;
  return `${r.subject_name}'s birthday is in ${r.offset_days} days.`;
}

Deno.serve(async (): Promise<Response> => {
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // R2: public wrapper, not .schema("private") — see 20260824000006.
  const { data, error } = await admin
    .rpc("rpc_next_reminder_batch", { p_limit: 100 });

  if (error) {
    console.error("next_reminder_batch failed", error.message);
    return new Response(JSON.stringify({ error: "batch read failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const batch = (data ?? []) as Reminder[];
  const fcmKey = Deno.env.get("FCM_SERVER_KEY");

  if (!fcmKey) {
    return new Response(
      JSON.stringify({ dryRun: true, would_send: batch.length, sent: 0, failed: 0 }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  let sent = 0;
  let failed = 0;

  for (const r of batch) {
    try {
      const res = await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          "Authorization": `key=${fcmKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          to: r.token,
          notification: { title: "Birthday reminder", body: body(r) },
        }),
      });

      if (!res.ok) {
        await admin.rpc("rpc_mark_reminder_failed", {
          p_outbox_id: r.outbox_id,
          p_error: `fcm ${res.status}`,
        });
        failed++;
        continue;
      }

      await admin.rpc("rpc_mark_reminder_sent", {
        p_outbox_id: r.outbox_id,
      });
      sent++;
    } catch (e) {
      await admin.rpc("rpc_mark_reminder_failed", {
        p_outbox_id: r.outbox_id,
        p_error: String(e).slice(0, 500),
      });
      failed++;
    }
  }

  return new Response(JSON.stringify({ sent, failed }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
```

Create `supabase/functions/drain_reminders/deno.json`:

```json
{
  "imports": {
    "@supabase/supabase-js": "jsr:@supabase/supabase-js@2"
  }
}
```

- [ ] **Step 2: Seed work and drain it in dry-run mode**

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -c "
  select tests.create_user('draintest');
  select private.claim_person((select id from public.profiles where handle='draintest'), '+919140000001');
  select tests.create_person('+919140000002','Drain Friend',
    extract(month from current_date)::smallint, extract(day from current_date)::smallint);
  insert into public.celebrations (celebrator_profile_id, person_id, source)
  values ((select id from public.profiles where handle='draintest'),
          (select id from public.people where display_name='Drain Friend'), 'contacts');
  insert into public.device_tokens (profile_id, token, platform)
  values ((select id from public.profiles where handle='draintest'), 'fcm-drain', 'android');
  select private.enqueue_reminders();
"
supabase functions serve drain_reminders --no-verify-jwt &
sleep 5
curl -s -X POST http://127.0.0.1:54321/functions/v1/drain_reminders
```

Expected: `{"dryRun":true,"would_send":1,"sent":0,"failed":0}` — one T-0 reminder found, nothing sent because no FCM key is configured.

- [ ] **Step 3: Confirm the row is still unsent**

```bash
docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
  "select count(*) from private.notification_outbox where sent_at is null;"
```

Expected: `1`. A dry run must not consume work.

- [ ] **Step 4: Stop the server, reset, and confirm the suite**

```bash
kill %1
supabase db reset && supabase test db
```

Expected: `Files=19, Tests=142, PASS`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/drain_reminders/
git commit -m "feat(functions): add drain_reminders with dry-run fallback"
```

---

## Phase 1 Definition of Done

- `supabase db reset && supabase test db` → **`Files=19, Tests=142, PASS`** from a cold database
- `supabase db lint --level warning` reports warnings only inside `extensions.*` (pgTAP's own code)
- `01_private.test.sql`'s allowlist still reads exactly `'can_see_person,is_staff,my_person_id'`
- Both Edge Functions respond correctly, with `drain_reminders` in dry-run mode
- Deferred to Phase 2 by design: real FCM credentials, real SMS provider, and any app code
