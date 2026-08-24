begin;
select plan(5);

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

select * from finish();
rollback;
