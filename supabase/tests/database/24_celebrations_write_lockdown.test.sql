-- B1: `public.celebrations` used to be a write-your-own-visibility table.
-- celebrations_insert_own constrained only celebrator_profile_id, so an
-- ordinary signed-in user could insert an edge aimed at ANY person id, and
-- private.can_see_person then handed them that public.people row -- real
-- display_name, real birth_month/birth_day/birth_year. public.people.id is a
-- sequential bigint, so that enumerated the entire user base. The UPDATE
-- policy had the same hole and no trigger at all, because M0's
-- celebrations_guard was BEFORE INSERT only.
--
-- This file replicates the original repro as a test. The attacker is handed
-- the victim's real person id for free (via a granted temp table) rather than
-- being made to guess it -- the fix must hold even against an attacker who
-- already knows the id, because on a sequential key everybody does.
--
-- 20260827000006 closes it three ways, and each is asserted separately so a
-- future migration that undoes any one of them fails by name.
begin;
select plan(15);

select tests.as_postgres();

select tests.create_user('lockvictim');
select tests.create_user('lockattacker');
select tests.create_user('lockblocker');

create temporary table ids as
select
  (select id from public.profiles where handle = 'lockvictim')   as victim,
  (select id from public.profiles where handle = 'lockattacker') as attacker,
  (select id from public.profiles where handle = 'lockblocker')  as blocker;

-- A real user's self-entered identity, which is exactly what leaked.
update public.profiles
set display_name = 'Lock Victim Real', birth_month = 7, birth_day = 11, birth_year = 1991
where id = (select victim from ids);

-- Volatile calls in one SELECT list have no defined order, so each claim is
-- its own statement rather than four columns of one `create table as`.
create temporary table setup (label text primary key, person_id bigint);

insert into setup
select 'victim', private.claim_person((select victim from ids), '+919760000001');
insert into setup
select 'attacker', private.claim_person((select attacker from ids), '+919760000002');
insert into setup
select 'blocker', private.claim_person((select blocker from ids), '+919760000003');

-- The one edge the attacker legitimately owns, minted the only way an edge
-- can be minted now: private.add_celebration, keyed on a phone number.
insert into setup
select 'owned', private.add_celebration((select attacker from ids), '+919760000009',
  'A Contact');

grant select on ids, setup to authenticated;

-- ------------------------------------------------------------ the attacker

select tests.as_user((select attacker from ids));

-- Guard for every throws_ok below: if the attacker could not read `setup`,
-- those statements would raise 42501 for reading a temp table rather than for
-- touching celebrations, and every assertion in this file would pass for the
-- wrong reason.
select isnt(
  (select person_id from setup where label = 'victim'),
  null,
  'the attacker really can read the victim''s person id (the repro is fair)'
);

select throws_ok(
  $$ insert into public.celebrations (celebrator_profile_id, person_id, source)
     values ((select auth.uid()),
             (select person_id from setup where label = 'victim'), 'manual') $$,
  '42501',
  null,
  'authenticated cannot insert an edge aimed at a stranger''s person id'
);

select throws_ok(
  $$ update public.celebrations
        set person_id = (select person_id from setup where label = 'victim')
      where celebrator_profile_id = (select auth.uid()) $$,
  '42501',
  null,
  'authenticated cannot redirect an edge it owns at another person_id'
);

select throws_ok(
  $$ update public.celebrations set source = 'manual'
      where celebrator_profile_id = (select auth.uid()) $$,
  '42501',
  null,
  'authenticated cannot rewrite source, the provenance of the edge'
);

select throws_ok(
  $$ update public.celebrations
        set celebrator_profile_id = (select blocker from ids)
      where celebrator_profile_id = (select auth.uid()) $$,
  '42501',
  null,
  'authenticated cannot hand an edge it owns to another profile'
);

-- No column is writable any more. nickname was the last one, and it was
-- dropped (20261017000002): nobody renames anybody. A row-level UPDATE that
-- names no column a user may write still has to fail, not silently no-op.
select throws_ok(
  $$ update public.celebrations set source = source
      where celebrator_profile_id = (select auth.uid())
        and person_id = (select person_id from setup where label = 'owned') $$,
  '42501',
  null,
  'authenticated cannot update any column of an edge it owns'
);

-- ------------------------------------------------- the enumeration is shut

select is(
  (select count(*)::int from public.people
    where id = (select person_id from setup where label = 'victim')),
  0,
  'after all of the above the victim''s person row is still invisible to the attacker'
);

select is(
  (select count(*)::int from public.people where display_name = 'Lock Victim Real'),
  0,
  'the victim''s real name never becomes readable'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select auth.uid())
      and person_id = (select person_id from setup where label = 'owned')),
  1,
  'the attacker still holds exactly the one edge they legitimately created'
);

-- -------------------------------------------------------------- the grants

select tests.as_postgres();

select is(
  has_table_privilege('authenticated', 'public.celebrations', 'INSERT'),
  false,
  'authenticated holds no INSERT privilege on celebrations'
);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'celebrations' and cmd = 'INSERT'),
  0,
  'celebrations has no INSERT policy left for anyone to slip through'
);

-- docs/db.md: a column-level revoke cannot cut back a table-level grant, so
-- this is the assertion that proves the table privilege really was revoked
-- and the columns really were granted back one at a time. If someone
-- re-grants table-level UPDATE "to fix a permission error", every column
-- appears here and this fails.
select is(
  (select coalesce(string_agg(a.attname, ',' order by a.attname), '')
     from pg_attribute a
    where a.attrelid = 'public.celebrations'::regclass
      and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')),
  '',
  'authenticated may update no column of celebrations'
);

select is(
  (select coalesce(string_agg(a.attname, ',' order by a.attname), '')
     from pg_attribute a
    where a.attrelid = 'public.celebrations'::regclass
      and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('anon', a.attrelid, a.attnum, 'UPDATE')),
  '',
  'anon may update nothing on celebrations'
);

-- --------------------------------------------------- the BEFORE UPDATE guard

select matches(
  (select pg_get_triggerdef(t.oid) from pg_trigger t
    where t.tgrelid = 'public.celebrations'::regclass
      and t.tgname = 'celebrations_guard_update'),
  'BEFORE UPDATE ON public\.celebrations FOR EACH ROW EXECUTE FUNCTION private\.guard_celebration\(\)',
  'guard_celebration is wired to BEFORE UPDATE, not only BEFORE INSERT'
);

-- ...and it actually fires. Asserted under `postgres`, which bypasses RLS and
-- every column grant, because that is the only role that can still reach an
-- UPDATE of person_id at all -- which is precisely the point of a trigger as
-- opposed to a grant: it holds even for a caller the grants do not stop.
-- The block branch is used rather than the self-edge branch because the
-- self-edge branch reads auth.uid(), which is null under postgres.
insert into public.blocks (blocker_profile_id, blocked_profile_id)
select (select blocker from ids), (select attacker from ids);

select throws_ok(
  $$ update public.celebrations
        set person_id = (select person_id from setup where label = 'blocker')
      where celebrator_profile_id = (select attacker from ids) $$,
  'P0001',
  'this person has blocked you',
  'redirecting an edge into someone who blocked you is rejected on UPDATE too'
);

select * from finish();
rollback;
