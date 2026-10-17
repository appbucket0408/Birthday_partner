begin;
select plan(8);

-- Two users. The signup trigger creates their profiles rows.
insert into auth.users (id, instance_id, aud, role, phone)
values
  ('a5a5a5a5-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   '919999888001'),
  ('a5a5a5a5-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   '919999888002')
on conflict do nothing;

select is(
  (select public from storage.buckets where id = 'avatars'),
  false,
  'the avatars bucket exists and is private');

-- Owner writes into their own folder.
select tests.as_user('a5a5a5a5-0000-0000-0000-000000000001');

select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('avatars', 'a5a5a5a5-0000-0000-0000-000000000001/me.jpg',
             'a5a5a5a5-0000-0000-0000-000000000001') $$,
  'a user can upload into their own folder');

select throws_ok(
  $$ insert into storage.objects (bucket_id, name, owner)
     values ('avatars', 'a5a5a5a5-0000-0000-0000-000000000002/me.jpg',
             'a5a5a5a5-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'a user cannot upload into someone else''s folder');

select is(
  (select count(*)::int from storage.objects
   where bucket_id = 'avatars'
     and name = 'a5a5a5a5-0000-0000-0000-000000000001/me.jpg'),
  1,
  'the owner can read their own photo');

select lives_ok(
  $$ update public.profiles
     set avatar_url = 'a5a5a5a5-0000-0000-0000-000000000001/me.jpg'
     where id = 'a5a5a5a5-0000-0000-0000-000000000001' $$,
  'a profile can point at a photo in its own folder');

select throws_ok(
  $$ update public.profiles
     set avatar_url = 'a5a5a5a5-0000-0000-0000-000000000002/them.jpg'
     where id = 'a5a5a5a5-0000-0000-0000-000000000001' $$,
  '23514',
  null,
  'a profile cannot point at a photo in someone else''s folder');

-- The second user sees nothing of the first's.
select tests.as_user('a5a5a5a5-0000-0000-0000-000000000002');

select is(
  (select count(*)::int from storage.objects
   where bucket_id = 'avatars'
     and name like 'a5a5a5a5-0000-0000-0000-000000000001/%'),
  0,
  'another user cannot read the photo');

reset role;
select tests.as_anon();

select is(
  (select count(*)::int from storage.objects where bucket_id = 'avatars'),
  0,
  'anon cannot read any photo');

reset role;
select * from finish();
rollback;
