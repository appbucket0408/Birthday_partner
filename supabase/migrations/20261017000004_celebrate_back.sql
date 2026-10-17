-- "Celebrate back": add someone who already celebrates you, without their
-- phone number.
--
-- Until now the only way to celebrate anyone was contacts import, keyed on a
-- phone number. A person who added you but is not in your address book could
-- never be added back, and the app never sees another user's number (people
-- rows hold only a hash), so it could not offer to.
--
-- This takes a person id instead -- one the caller can already see in their
-- Celebrates list (my_celebrates) -- and is refused for anyone who does NOT
-- celebrate the caller. That condition is the whole privacy argument: it
-- keeps the rule that nobody can reach a stranger (spec §6 rule 7), because
-- the only ids it accepts belong to people who reached the caller first.
--
-- Errors (docs/db.md: unassigned class 45):
--   45006  that person does not celebrate you (or is not on the app).
-- The existing celebrations_guard trigger still runs on the insert: it
-- refuses self-celebration and a person who has blocked the caller.
create function public.rpc_celebrate_back(p_person_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_target_profile uuid;
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select p.profile_id into v_target_profile
  from public.people p
  where p.id = p_person_id;

  -- Must be a member (a claimed person) who celebrates the caller's own
  -- person row. An unclaimed person cannot celebrate anyone.
  if v_target_profile is null or not exists (
    select 1 from public.celebrations c
    where c.celebrator_profile_id = v_target_profile
      and c.person_id = private.my_person_id()
  ) then
    raise exception 'you can only celebrate back someone who celebrates you'
      using errcode = '45006';
  end if;

  -- 'manual': not from an address book. Idempotent, like add_celebration --
  -- a double tap must not error.
  insert into public.celebrations (celebrator_profile_id, person_id, source)
  values (v_me, p_person_id, 'manual')
  on conflict on constraint celebrations_unique_edge do nothing;

  return p_person_id;
end;
$$;

revoke execute on function public.rpc_celebrate_back(bigint)
  from public, anon;
grant execute on function public.rpc_celebrate_back(bigint) to authenticated;
