-- Only a person sets their own birthday.
--
-- Product decision: one user must never set or change another user's
-- birthday (or name -- nicknames went in 20261017000002). Until now three
-- paths let a celebrator write the birthday of someone not on the app:
--
--   1. rpc_update_person_birthday -- the timeline's "Edit birthday".
--   2. Contacts import (rpc_add_celebration) carrying the address book's
--      birthday, which upsert_person filled into a blank person row.
--   3. The import's "Add their birthdays" step, which rode path 2.
--
-- After this migration a person's birthday comes from exactly one place: their
-- own profile, copied onto their person row by private.sync_person_from_profile
-- (and by private.claim_person when they first claim the row). Someone who is
-- not on the app has NO birthday until they join -- so no Calendar entry and
-- no reminders for them until then. That is the accepted cost.

-- 1. The edit path, gone. Dropping the function drops its EXECUTE grants.
drop function public.rpc_update_person_birthday(bigint, smallint, smallint, smallint);

-- 2. Import no longer takes a birthday. The signatures lose the three
--    birthday parameters outright rather than ignoring them, so a caller
--    that still sends one (an old add_celebrations deploy) fails loudly
--    instead of silently doing something different from what it says.
drop function public.rpc_add_celebration(uuid, text, text, smallint, smallint, smallint);
drop function private.add_celebration(uuid, text, text, smallint, smallint, smallint);

create function private.add_celebration(
  p_celebrator uuid,
  p_phone text,
  p_name text
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

  -- No birthday: only the person themselves supplies one, by claiming.
  v_person_id := private.upsert_person(p_phone, p_name);

  if v_person_id is null then
    return null;  -- suppressed
  end if;

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
      using errcode = '45001';
  end if;

  insert into public.celebrations (celebrator_profile_id, person_id, source)
  values (p_celebrator, v_person_id, 'contacts')
  on conflict on constraint celebrations_unique_edge do nothing;

  return v_person_id;
end;
$$;

create function public.rpc_add_celebration(
  p_celebrator uuid,
  p_phone text,
  p_name text
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select private.add_celebration(p_celebrator, p_phone, p_name);
$$;

-- Same exposure as before: private is never client-callable, and the public
-- wrapper is for the add_celebrations Edge Function (service_role) only.
revoke execute on function private.add_celebration(uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.rpc_add_celebration(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.rpc_add_celebration(uuid, text, text)
  to service_role;

-- private.upsert_person keeps its optional birthday parameters: it is not
-- reachable by any client (private schema, execute revoked), and the only
-- caller left, add_celebration above, passes none. Its remaining callers are
-- test fixtures acting as the database owner.

-- 3. Birthdays already written by someone other than the person. An
--    unclaimed row's birthday can only have come from an importer or an
--    edit, never from the person, so it is cleared. Claimed rows keep theirs:
--    sync_person_from_profile has been writing the owner's own birthday onto
--    them.
update public.people
set birth_month = null, birth_day = null, birth_year = null
where profile_id is null
  and birth_month is not null;
