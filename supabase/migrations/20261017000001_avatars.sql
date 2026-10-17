-- Profile photos.
--
-- A PRIVATE bucket, not the usual public avatars bucket: everything else
-- about a person here is visible only inside their graph (spec §6 rule 7),
-- and a public bucket would make a photo readable by anyone holding the URL.
-- The app reads a photo through a short-lived signed URL instead.
--
-- Layout: avatars/<profile uuid>/<file>. The first path segment IS the
-- owner, and every policy below keys on it -- the same convention as
-- Supabase's own storage examples, so storage.foldername() does the parsing.
--
-- profiles.avatar_url (already in 20260822000003_profiles.sql, already
-- granted to `authenticated`) holds the object PATH, not a URL: a signed URL
-- expires, a path does not.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  false,
  -- The app resizes to 512px before upload, which lands far below this; the
  -- limit only stops a modified client using the bucket as free storage.
  2 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Owner-only, all four verbs. Reading OTHER people's photos is deliberately
-- not granted yet: showing a friend's photo needs a graph-aware rule (the
-- can_see_person shape), which is its own change.
create policy avatars_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- A profile may only point at a photo in its OWN folder. Storage policy
-- already stops anyone signing a URL for someone else's object, but without
-- this a profile could still claim another user's photo as its own the day
-- photos become visible to friends.
alter table public.profiles
  add constraint profiles_avatar_own_folder
    check (avatar_url is null or avatar_url like id::text || '/%');
