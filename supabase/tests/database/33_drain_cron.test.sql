begin;
select plan(6);

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

select * from finish();
rollback;
