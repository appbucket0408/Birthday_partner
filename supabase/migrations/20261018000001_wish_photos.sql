
alter table public.wishes add column photo_path text;

alter table public.wishes
  add constraint wishes_photo_path_valid check (
    photo_path is null
    or (
      kind = 'message'
      and photo_path ~ ('^' || author_profile_id::text || '/[A-Za-z0-9_-]+\.(jpg|png|webp)$')
    )
  );

-- One wish per photo, and the lookup the storage read policy below runs.
create unique index wishes_photo_path_key
  on public.wishes (photo_path)
  where photo_path is not null;

-- PRIVATE, like avatars: a wish is visible only inside the subject's graph
-- (spec §6 rule 7), and its photo must not be readable by anyone holding a
-- URL. The app reads it through a short-lived signed URL.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'wish_photos',
  'wish_photos',
  false,
  -- The app resizes to 1440px before upload, which lands well below this.
  5 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Readable by its uploader, and by anyone who can read a wish that points at
-- it. The subquery runs under the caller's own RLS on public.wishes, so the
-- photo follows exactly the wish's visibility (wishes_select_visible) and
-- never more.
create policy wish_photos_select_visible
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'wish_photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.wishes w
        where w.photo_path = storage.objects.name
      )
    )
  );

create policy wish_photos_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'wish_photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Delete only: a failed wish insert removes its just-uploaded photo. There is
-- no update -- a photo is never replaced in place.
create policy wish_photos_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'wish_photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
