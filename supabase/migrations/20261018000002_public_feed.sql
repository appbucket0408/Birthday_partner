
create or replace function public.feed_page(
  p_before timestamptz default null,
  p_limit int default 20
)
returns table (
  id bigint,
  author_profile_id uuid,
  subject_person_id bigint,
  body text,
  kind text,
  occasion_year int,
  created_at timestamptz,
  photo_path text,
  author_name text,
  subject_name text,
  can_open_subject boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    w.id,
    w.author_profile_id,
    w.subject_person_id,
    w.body,
    w.kind,
    w.occasion_year,
    w.created_at,
    w.photo_path,
    case
      when ap.id is not null and private.can_see_person(ap.id)
        then ap.display_name
      else apr.display_name
    end,
    case
      when private.can_see_person(sp.id) then sp.display_name
      else spr.display_name
    end,
    private.can_see_person(sp.id)
  from public.wishes w
  join public.people sp on sp.id = w.subject_person_id
  left join public.profiles spr on spr.id = sp.profile_id
  left join public.people ap on ap.profile_id = w.author_profile_id
  left join public.profiles apr on apr.id = w.author_profile_id
  where (select auth.uid()) is not null
    and (p_before is null or w.created_at < p_before)
    and (
      sp.profile_id is not null
      or w.author_profile_id = (select auth.uid())
      or private.can_see_person(sp.id)
    )
  order by w.created_at desc, w.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.feed_page(timestamptz, int)
  from public, anon;
grant execute on function public.feed_page(timestamptz, int) to authenticated;

-- A public post's photo must load for the members who now see the post.
-- wish_photos_select_visible's own lookup runs under the caller's wishes
-- RLS, which hides these rows from strangers, so this check is a definer
-- function -- the same public rule as feed_page, nothing wider.
create or replace function private.is_public_wish_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.wishes w
    join public.people sp on sp.id = w.subject_person_id
    where w.photo_path = p_name
      and sp.profile_id is not null
  );
$$;

revoke execute on function private.is_public_wish_photo(text)
  from public, anon;
grant execute on function private.is_public_wish_photo(text) to authenticated;

create policy wish_photos_select_public_feed
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'wish_photos'
    and (select private.is_public_wish_photo(storage.objects.name))
  );
