-- The stranger preview gains a @handle (to tell two "Sachin"s apart) and a
-- mutual count: how many people the caller celebrates also celebrate them.
-- A number, never names. Still no birthday.

drop function public.member_preview(bigint);

create function public.member_preview(p_person_id bigint)
returns table (
  id bigint,
  display_name text,
  handle text,
  celebrator_count int,
  mutual_count int
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    pr.display_name,
    -- The signup placeholder ('u' + uuid) is not a name anyone chose.
    case when pr.handle ~ '^u[0-9a-f]{32}$' then null else pr.handle end,
    (select count(*)::int from public.celebrations c where c.person_id = p.id),
    (select count(*)::int
       from public.celebrations mine
       join public.people mp on mp.id = mine.person_id
       join public.celebrations theirs
         on theirs.celebrator_profile_id = mp.profile_id
        and theirs.person_id = p.id
      where mine.celebrator_profile_id = (select auth.uid()))
  from public.people p
  join public.profiles pr on pr.id = p.profile_id
  where (select auth.uid()) is not null
    and p.id = p_person_id
    and private.is_discoverable(p.id);
$$;

revoke execute on function public.member_preview(bigint) from public, anon;
grant execute on function public.member_preview(bigint) to authenticated;
