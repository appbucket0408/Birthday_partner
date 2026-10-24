-- Fix 20261024170000: wishes_insert_own read public.blocks under the author's
-- RLS, which hides blocks made against them, so a blocked author could still post.

create function private.is_blocked_with_person(p_person_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.people p
    where p.id = p_person_id
      and p.profile_id is not null
      and private.is_blocked_with(p.profile_id)
  );
$$;

revoke execute on function private.is_blocked_with_person(bigint) from public, anon;
grant execute on function private.is_blocked_with_person(bigint) to authenticated;

drop policy wishes_insert_own on public.wishes;

create policy wishes_insert_own
  on public.wishes
  for insert
  to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and exists (
      select 1 from public.celebrations c
      where c.person_id = wishes.subject_person_id
        and c.celebrator_profile_id = (select auth.uid())
    )
    and not private.is_blocked_with_person(wishes.subject_person_id)
  );
