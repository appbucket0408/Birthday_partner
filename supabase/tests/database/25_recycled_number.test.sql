-- B2 and B3. 20260827000005 scrubbed the deleted user's name and birthday off
-- their surviving people row but kept `phone_e164_hash` -- the row's only
-- lookup key -- so the row stayed findable by anyone who could compute that
-- hash from the number:
--
--   B2  private.claim_person upserts `on conflict (phone_e164_hash) do update
--       set profile_id = ...`, so the next person to verify that recycled
--       number was attached to the previous owner's row and inherited their
--       inbound celebration edges and their whole wish wall. Carriers reissue
--       disconnected numbers routinely; this needed no attacker at all.
--
--   B3  private.upsert_person refills BLANK birth columns on any row with
--       `profile_id is null`, and the scrubbed row is exactly blank and
--       unclaimed. One friend re-importing their address book restored the
--       deleted user's birthday, and private.enqueue_reminders then queued a
--       real notification about them.
--
-- 20260827000007 rotates the hash to 64 random hex characters inside the
-- scrub. Both faces close at once, because both were reached through the
-- same lookup.
--
-- The two are exercised on two SEPARATE deleted users and two separate phone
-- numbers on purpose. Running the recycle and the re-import against one
-- number makes each assertion depend on the other's outcome, and a test that
-- can only fail for a tangle of reasons does not say which thing broke.
--
-- The deliberate trade-off, asserted below rather than merely written down:
-- the bystander's edge is permanently stranded on a 'Deleted user' row, and a
-- later re-import of the same number mints a SECOND, separate row beside it.
begin;
select plan(14);

select tests.as_postgres();

select tests.create_user('recyclealice');
select tests.create_user('recyclebystander');
select tests.create_user('recyclebob');
select tests.create_user('recycleghost');
select tests.create_user('recyclefriend');

create temporary table ids as
select
  (select id from public.profiles where handle = 'recyclealice')     as alice,
  (select id from public.profiles where handle = 'recyclebystander') as bystander,
  (select id from public.profiles where handle = 'recyclebob')       as bob,
  (select id from public.profiles where handle = 'recycleghost')     as ghost,
  (select id from public.profiles where handle = 'recyclefriend')    as friend;

update public.profiles
set display_name = 'Alice Real Name', birth_month = 4, birth_day = 15, birth_year = 1990
where id = (select alice from ids);

update public.profiles
set display_name = 'Ghost Real Name', birth_month = 6, birth_day = 20, birth_year = 1988
where id = (select ghost from ids);

-- Volatile calls in one SELECT list have no defined order, so each claim is
-- its own statement rather than several columns of one `create table as`.
create temporary table setup (label text primary key, person_id bigint);

insert into setup
select 'alice', private.claim_person((select alice from ids), '+919770000001');
insert into setup
select 'bystander', private.claim_person((select bystander from ids), '+919770000009');
insert into setup
select 'ghost', private.claim_person((select ghost from ids), '+919770000002');
insert into setup
select 'friend', private.claim_person((select friend from ids), '+919770000008');

-- The bystander celebrates alice by number, and wishes her a happy birthday.
insert into setup
select 'via_bystander', private.add_celebration((select bystander from ids),
  '+919770000001', 'Alice', null::smallint, null::smallint, null::smallint);

insert into public.wishes (subject_person_id, author_profile_id, body, occasion_year)
select (select person_id from setup where label = 'alice'),
       (select bystander from ids), 'happy birthday Alice', 2026;

select is(
  (select person_id from setup where label = 'via_bystander'),
  (select person_id from setup where label = 'alice'),
  'before: the bystander''s edge points at alice''s own person row'
);

-- Both users delete their accounts. This one statement is what
-- auth.admin.deleteUser reduces to; the BEFORE DELETE scrub trigger runs off
-- it.
delete from auth.users where id = (select alice from ids);
delete from auth.users where id = (select ghost from ids);

-- ---------------------------------------------------- the row still exists

select is(
  (select count(*)::int from public.people
    where id = (select person_id from setup where label = 'alice')
      and profile_id is null and display_name = 'Deleted user'),
  1,
  'after: alice''s person row survives, unclaimed and scrubbed'
);

select is(
  (select count(*)::int from public.celebrations
    where celebrator_profile_id = (select bystander from ids)
      and person_id = (select person_id from setup where label = 'alice')),
  1,
  'after: the bystander''s inbound edge survives on that same row id'
);

-- ------------------------------------------------ but is no longer findable

select is(
  (select count(*)::int from public.people
    where phone_e164_hash = private.phone_hash('+919770000001')),
  0,
  'after: no person row can be found by alice''s original phone number'
);

-- The next two assertions are SHAPE guards on the rotation, not proof of it.
-- Neither fails if the rotation is removed entirely -- a real HMAC is also 64
-- hex and is also distinct per row -- so they are not what closes B2/B3
-- (assertions 4, 6, 8, 9, 10, 12, 13 and 14 are). What they pin is the choice
-- of replacement VALUE: measured against the running database, rotating to a
-- constant sentinel aborts the second account deletion on
-- people_phone_e164_hash_key, and rotating to anything that is not 64
-- lowercase hex aborts the first on people_phone_hash_format. Both surface as
-- a failed deletion rather than as a quiet wrong answer, and these two
-- assertions are here to name the reason when that happens.
select matches(
  (select phone_e164_hash from public.people
    where id = (select person_id from setup where label = 'alice')),
  '^[0-9a-f]{64}$',
  'after: the rotated hash keeps the 64-hex shape the column constrains'
);

select isnt(
  (select phone_e164_hash from public.people
    where id = (select person_id from setup where label = 'alice')),
  private.phone_hash('+919770000001'),
  'after: the stored hash is no longer the hash of her number'
);

select isnt(
  (select phone_e164_hash from public.people
    where id = (select person_id from setup where label = 'alice')),
  (select phone_e164_hash from public.people
    where id = (select person_id from setup where label = 'ghost')),
  'after: two scrubbed rows rotate to different values'
);

-- ---------------------------------------- B2: the recycled number is clean

-- Bob is issued alice's recycled number and verifies it during onboarding.
create temporary table recycled as
select private.claim_person((select bob from ids), '+919770000001') as person_id;

select isnt(
  (select person_id from recycled),
  (select person_id from setup where label = 'alice'),
  'B2: a recycled number mints a NEW person row, not alice''s old one'
);

select is(
  (select count(*)::int from public.celebrations c
    join public.people p on p.id = c.person_id
   where p.profile_id = (select bob from ids)),
  0,
  'B2: bob inherits no inbound celebration edges'
);

select is(
  (select count(*)::int from public.wishes w
    join public.people p on p.id = w.subject_person_id
   where p.profile_id = (select bob from ids)),
  0,
  'B2: bob inherits no wishes -- alice''s wall is not his'
);

select is(
  (select count(*)::int from public.people
    where id = (select person_id from recycled)
      and display_name = 'Recyclebob'),
  1,
  'B2: bob''s new row carries bob''s own identity, not the placeholder'
);

-- ------------------------------- B3: a re-import cannot refill the birthday

-- A friend still has the ghost in their address book, complete with a
-- birthday, and imports it. Nobody has recycled that number: the scrubbed row
-- is the only candidate, unclaimed and blank, which is exactly the state
-- upsert_person used to refill.
create temporary table reimported as
select private.add_celebration((select friend from ids), '+919770000002',
  'Ghost From My Contacts', 6::smallint, 20::smallint, null::smallint) as person_id;

select is(
  (select display_name || '|' || coalesce(birth_month::text, 'NULL') || '|' ||
          coalesce(birth_day::text, 'NULL') || '|' || coalesce(birth_year::text, 'NULL')
     from public.people where id = (select person_id from setup where label = 'ghost')),
  'Deleted user|NULL|NULL|NULL',
  'B3: a re-import carrying their real birthday does not restore it on the scrubbed row'
);

-- The trade-off, made explicit and pinned: the import mints a SECOND row
-- beside the stranded one, and nothing will ever reunite them. That is the
-- price of not handing a deleted user's graph to whoever holds the number
-- next.
select isnt(
  (select person_id from reimported),
  (select person_id from setup where label = 'ghost'),
  'B3: the re-import mints a second, separate row rather than reviving the stranded one'
);

select private.enqueue_reminders('2026-06-20'::date);

select is(
  (select count(*)::int from private.notification_outbox
    where subject_person_id = (select person_id from setup where label = 'ghost')),
  0,
  'B3: enqueue_reminders queues nothing about the deleted user on their old birthday'
);

select * from finish();
rollback;
