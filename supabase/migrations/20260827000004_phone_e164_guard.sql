-- private.phone_hash is a bare HMAC with zero normalisation: '+919999000002',
-- '919999000002' and '+91 99990 00002' all hash to DIFFERENT values even
-- though they name the same phone number. That silently forks one human into
-- several public.people rows, and it defeats add_celebration's self-
-- celebration check, because that check compares hashes derived from
-- p_celebrator's ALREADY-claimed row against a hash derived from whatever
-- string this caller happened to send -- a caller who sends their own number
-- in a non-canonical form hashes to a value that does not match, so the
-- check silently passes and a self-edge is created.
--
-- claim_person's retroactive self-edge cleanup (20260827000003) does not
-- help either: it deletes by the person id reached through the E.164 hash,
-- so a self-import under a non-normalised form mints a SEPARATE people row
-- the cleanup never looks at.
--
-- The fix belongs at the write paths, in the database, not only in the Edge
-- Function: this is the only place pgTAP can hold it down, and it closes
-- every write path (Edge Function, tests.*, any future caller) at once
-- rather than just the HTTP one.
create or replace function private.assert_e164(p_phone text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'phone number must be in E.164 format'
      using errcode = '22023';
  end if;

  return p_phone;
end;
$$;

revoke execute on function private.assert_e164(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- write paths

-- Unchanged apart from validating p_phone before it is hashed. Every branch
-- below (suppression check, existing-row update, insert) already used
-- v_hash, so validating at the point v_hash is computed protects all of them
-- with a single call.
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
  v_hash text := private.phone_hash(private.assert_e164(p_phone));
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

-- Unchanged apart from validating p_phone before it is hashed.
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
  v_hash text := private.phone_hash(private.assert_e164(p_phone));
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

  -- Close the retroactive self-edge hole: if this profile imported their own
  -- number as a contact before claiming it, the edge became a self-edge the
  -- instant profile_id was attached above. Remove it now -- a self-edge is
  -- never valid regardless of when it was created.
  delete from public.celebrations
  where celebrator_profile_id = p_profile_id and person_id = v_id;

  return v_id;
end;
$$;

revoke execute on function private.claim_person(uuid, text)
  from public, anon, authenticated;

-- Unchanged apart from (a) validating p_phone up front, defence-in-depth
-- alongside upsert_person's own validation, and (b) tagging the
-- self-celebration raise with a stable SQLSTATE instead of the generic
-- P0001 every other unhandled exception also carries. Importing your own
-- number is the single most likely "failure" in a real contacts import --
-- your own number is in your own address book -- and before this it was
-- indistinguishable from a database outage to the Edge Function's error
-- branch.
create or replace function private.add_celebration(
  p_celebrator uuid,
  p_phone text,
  p_name text,
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
  v_person_id bigint;
begin
  p_phone := private.assert_e164(p_phone);

  v_person_id := private.upsert_person(
    p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);

  if v_person_id is null then
    return null;  -- suppressed
  end if;

  -- Reject celebrating yourself. Two ways that can happen, and the second is
  -- the one that bites: the resolved person is already claimed by this
  -- celebrator, OR it is still unclaimed but carries the celebrator's own
  -- phone hash -- in which case claim_person would later attach it to them
  -- and the edge would become a self-edge retroactively, with no trigger to
  -- catch it (celebrations_guard is BEFORE INSERT only).
  --
  -- M0's celebrations_guard cannot do this job here: it compares against
  -- private.my_person_id(), which reads auth.uid(), and there is no session
  -- under service_role.
  if exists (
    select 1 from public.people p
    where p.id = v_person_id
      and (
        p.profile_id = p_celebrator
        or p.phone_e164_hash = (
          select c.phone_e164_hash from public.people c
          where c.profile_id = p_celebrator
        )
      )
  ) then
    raise exception 'you cannot celebrate yourself'
      using errcode = 'P0002';
  end if;

  -- on conflict: a retried request or a double tap is idempotent.
  insert into public.celebrations (celebrator_profile_id, person_id, source)
  values (p_celebrator, v_person_id, 'contacts')
  on conflict on constraint celebrations_unique_edge do nothing;

  return v_person_id;
end;
$$;

revoke execute on function private.add_celebration(
  uuid, text, text, smallint, smallint, smallint)
  from public, anon, authenticated;

-- private.resolve_contacts deliberately does NOT get assert_e164. It is a
-- read-only lookup over a caller's whole address book: a malformed entry
-- there must simply fail to match private.people.phone_e164_hash (nothing
-- hashes to it), not raise and kill the whole batch. It already has no
-- write path to protect.
