begin;
select plan(5);

-- Fixtures: a recipient with a device, and a subject.
insert into auth.users (id, instance_id, aud, role, phone)
values ('11111111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', '919999777001')
on conflict do nothing;

insert into public.people (phone_e164_hash, display_name, birth_month, birth_day)
values (encode(digest('c1-subject','sha256'),'hex'), 'Subject', 1, 1)
on conflict (phone_e164_hash) do nothing;

insert into public.device_tokens (profile_id, token, platform)
values ('11111111-1111-1111-1111-111111111111', 'c1-token', 'android')
on conflict (token) do nothing;

insert into private.notification_outbox
  (recipient_profile_id, subject_person_id, offset_days, occasion_date)
select '11111111-1111-1111-1111-111111111111', p.id, 0, current_date
from public.people p
where p.phone_e164_hash = encode(digest('c1-subject','sha256'),'hex');

-- Claim it, exactly as the drain does.
select is(
  (select count(*)::int from private.next_reminder_batch(100)),
  1,
  'the batch claims the row');

select is(
  (select attempts from private.notification_outbox
   where recipient_profile_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'claiming burned an attempt -- this is what makes a release necessary');

-- THE assertion. A drain that abandons the batch before attempting ANY send
-- (a failed OAuth mint, a malformed service-account secret) must give the
-- attempt back. Without this, the cron re-claims every 10 minutes, burns an
-- attempt each time, and within an hour every pending reminder crosses
-- `attempts < 5` and is silently excluded from the batch FOREVER -- with
-- last_error null, because mark_reminder_failed was never called.
select private.release_reminder_claims(
  array(select id from private.notification_outbox
        where recipient_profile_id = '11111111-1111-1111-1111-111111111111'));

select is(
  (select attempts::int || ':' || coalesce(claimed_at::text, 'null')
   from private.notification_outbox
   where recipient_profile_id = '11111111-1111-1111-1111-111111111111'),
  '0:null',
  'releasing gives the attempt back and clears the lease');

-- The wrapper must be service_role-only, like every other rpc_ here. A
-- `create or replace` keeps an existing ACL, but this function is NEW, so
-- it defaults to executable by public until the revoke runs.
select ok(
  not has_function_privilege('anon', 'public.rpc_release_reminder_claims(bigint[])', 'execute'),
  'anon must NOT execute the release wrapper');
select ok(
  not has_function_privilege('authenticated', 'public.rpc_release_reminder_claims(bigint[])', 'execute'),
  'authenticated must NOT execute the release wrapper -- it rewinds attempts');

select * from finish();
rollback;
