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

  -- M0's celebrations_guard trigger also rejects self-celebration, but it
  -- compares against private.my_person_id(), which reads auth.uid() from the
  -- session JWT. This function is reached through a service_role RPC with no
  -- per-caller session — auth.uid() is null there, so the trigger alone would
  -- never catch a service-role call where p_celebrator picks their own
  -- number. Check explicitly against the p_celebrator argument instead.
  if exists (
    select 1 from public.people
    where id = v_person_id and profile_id = p_celebrator
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
