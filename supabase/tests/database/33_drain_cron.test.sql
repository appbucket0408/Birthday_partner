begin;
select plan(9);

select has_table('private', 'drain_config', 'the drain needs a config row');

-- private, not public: PostgREST cannot see the private schema, so a table
-- holding a bearer secret has no API surface to mis-police.
select ok(
  not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'drain_config'
  ),
  'drain_config must NOT be in public -- it holds a bearer secret');

select ok(
  (select count(*) = 1 from cron.job where jobname = 'reminder-drain'),
  'the drain cron must be scheduled exactly once');

select is(
  (select schedule from cron.job where jobname = 'reminder-drain'),
  '*/10 * * * *',
  'every ten minutes');

-- Review Focus 5. An unconfigured environment must be a no-op, not a cron
-- firing every ten minutes against a null URL and filling the log.
select lives_ok(
  $$ select private.trigger_drain() $$,
  'trigger_drain against an EMPTY drain_config must not raise');

select ok(
  (select count(*) = 0 from net.http_request_queue),
  'and it must not have queued a request');


-- Review finding I9. Everything above only ever reaches the `if not found`
-- guard, so the net.http_post call itself -- its argument names, the header
-- jsonb, the column references -- was executed by NOTHING. plpgsql binds
-- late, so a renamed column or a wrong argument name would have failed
-- first in production, on a cron whose failures are invisible because
-- net.http_post never raises.
insert into private.drain_config (function_url, drain_secret)
values ('http://kong-test-host:8000/functions/v1/drain_reminders', 'test-secret');

select lives_ok(
  $$ select private.trigger_drain() $$,
  'trigger_drain against a CONFIGURED drain_config must not raise');

select is(
  (select count(*)::int from net.http_request_queue
   where url = 'http://kong-test-host:8000/functions/v1/drain_reminders'),
  1,
  'exactly one request was queued, at the configured URL');

select is(
  (select headers->>'x-drain-secret' from net.http_request_queue
   where url = 'http://kong-test-host:8000/functions/v1/drain_reminders'),
  'test-secret',
  'and it carried the secret the function checks -- a drain that queued '
  'without this header would 401 forever, invisibly');

select * from finish();
rollback;
