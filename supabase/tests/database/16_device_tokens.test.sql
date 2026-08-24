begin;
select plan(10);

select has_table('public', 'device_tokens', 'device_tokens exists');

select tests.as_postgres();
select tests.create_user('phoneowner');
select tests.create_user('nosyuser');

create temporary table ids as
select
  (select id from public.profiles where handle = 'phoneowner') as owner,
  (select id from public.profiles where handle = 'nosyuser')   as nosy;
grant select on ids to authenticated;

select tests.as_user((select owner from ids));

select lives_ok(
  $$ insert into public.device_tokens (profile_id, token, platform)
     values ((select auth.uid()), 'fcm-token-owner', 'android') $$,
  'a user registers their own device token'
);

-- Another user must not be able to read it.
select tests.as_postgres();
select tests.as_user((select nosy from ids));
select is(
  (select count(*)::int from public.device_tokens),
  0,
  'another user cannot read my device token'
);

-- Nor forge one in my name.
select throws_ok(
  $$ insert into public.device_tokens (profile_id, token, platform)
     values ((select owner from ids), 'fcm-token-forged', 'ios') $$,
  '42501',
  null,
  'another user cannot register a token in my name'
);

-- Platform is constrained: a typo must not reach the FCM drain.
select tests.as_postgres();
select tests.as_user((select owner from ids));
select throws_ok(
  $$ insert into public.device_tokens (profile_id, token, platform)
     values ((select auth.uid()), 'fcm-token-bad-platform', 'windowsphone') $$,
  '23514',
  null,
  'an unknown platform is rejected'
);

-- The policy is `for all`, so the update and delete paths need cover too. A
-- non-owner is filtered rather than refused, so these assert rows-affected
-- rather than an error.
select tests.as_postgres();
select tests.as_user((select owner from ids));

select lives_ok(
  $$ update public.device_tokens set last_seen_at = now()
     where profile_id = (select auth.uid()) $$,
  'an owner refreshes last_seen_at on their own token'
);

select tests.as_postgres();
select tests.as_user((select nosy from ids));

with attempted as (
  update public.device_tokens set token = 'hijacked' returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'a non-owner update affects zero token rows'
);

with attempted as (
  delete from public.device_tokens returning 1
)
select is(
  (select count(*)::int from attempted),
  0,
  'a non-owner delete affects zero token rows'
);

select tests.as_postgres();
select tests.as_user((select owner from ids));

select lives_ok(
  $$ delete from public.device_tokens where profile_id = (select auth.uid()) $$,
  'an owner deletes their own token on sign-out'
);

-- Reassignment: the same physical device, now a different account.
select tests.as_postgres();
select tests.as_user((select owner from ids));
select public.register_device_token('shared-device-token', 'android');

select tests.as_postgres();
select tests.as_user((select nosy from ids));
select public.register_device_token('shared-device-token', 'android');

select tests.as_postgres();
select is(
  (select count(*)::int || ' owned by nosy=' ||
          (select count(*)::int from public.device_tokens
            where token = 'shared-device-token'
              and profile_id = (select nosy from ids))::text
     from public.device_tokens where token = 'shared-device-token'),
  '1 owned by nosy=1',
  'a device token moves to the account that last registered it'
);

select * from finish();
rollback;
