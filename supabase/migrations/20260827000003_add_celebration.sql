-- "Create on select": the import screen resolves matches read-only, and the
-- person row is minted only when the user actually picks someone. The person
-- and the edge are created in one call so a failure cannot leave a person
-- nobody celebrates, or an edge pointing at nothing.
--
-- Returns null when the number is suppressed. Callers must treat that as
-- "skip this contact", not as an error — someone who asked to be removed must
-- not be resurrected by the next person who imports their number.
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
  v_person_id := private.upsert_person(
    p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);

  if v_person_id is null then
    return null;  -- suppressed
  end if;

  -- Reject celebrating yourself. Two ways that can happen, and the second is
  -- the one that bites: the resolved person is already claimed by this
  -- celebrator, OR it is still unclaimed but carries the celebrator's own
  -- phone hash — in which case claim_person would later attach it to them
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
    raise exception 'you cannot celebrate yourself';
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

-- service_role only, reached through the add_celebrations Edge Function.
create or replace function public.rpc_add_celebration(
  p_celebrator uuid,
  p_phone text,
  p_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select private.add_celebration(
    p_celebrator, p_phone, p_name, p_birth_month, p_birth_day, p_birth_year);
$$;

revoke execute on function public.rpc_add_celebration(
  uuid, text, text, smallint, smallint, smallint)
  from public, anon, authenticated;
grant execute on function public.rpc_add_celebration(
  uuid, text, text, smallint, smallint, smallint) to service_role;

-- Code review (round 1) flagged a hole in the self-celebration check above:
-- it only catches a person row ALREADY claimed by p_celebrator. If the
-- celebrator has signed up but not yet claimed their own person row, that
-- row does not exist yet, both branches of the OR above evaluate to NULL,
-- and the self-edge is inserted. claim_person later attaches profile_id to
-- that same row by phone-hash conflict, turning the edge into a self-edge
-- retroactively — and celebrations_guard is BEFORE INSERT only, so nothing
-- ever re-validates it.
--
-- add_celebration cannot close this itself: at import time there is no
-- in-schema record of "this profile's own phone number" to compare against
-- for a profile that has not claimed yet, so the check above is necessary
-- but not sufficient. The only point where the missing fact becomes known
-- is claim_person, when profile_id is attached — so that is where the
-- retroactive self-edge has to be removed.
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

  -- Close the retroactive self-edge hole: if this profile imported their own
  -- number as a contact before claiming it, the edge became a self-edge the
  -- instant profile_id was attached above. Remove it now — a self-edge is
  -- never valid regardless of when it was created.
  delete from public.celebrations
  where celebrator_profile_id = p_profile_id and person_id = v_id;

  return v_id;
end;
$$;

revoke execute on function private.claim_person(uuid, text)
  from public, anon, authenticated;
