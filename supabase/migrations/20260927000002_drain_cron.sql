-- The 03:00 fan-out has filled notification_outbox since Phase 1 and nothing
-- has ever drained it. drain_reminders has only ever been called by hand.
create extension if not exists pg_net;

-- Single row, enforced by the primary key: a boolean PK with a check that it
-- is true admits exactly one row and no more.
--
-- private, not public, for the same reason notification_outbox is: PostgREST
-- cannot see the private schema, so a table holding a bearer secret has no
-- API surface to mis-police. No policies; service_role and the cron's own
-- definer context are the only readers.
create table private.drain_config (
  id boolean primary key default true,
  function_url text not null,
  drain_secret text not null,
  constraint drain_config_single_row check (id)
);

alter table private.drain_config enable row level security;

-- Created EMPTY. Values are inserted per environment by an operator, so no
-- secret is ever committed and the same migration applies to local and
-- hosted without edits.
create or replace function private.trigger_drain()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_config private.drain_config%rowtype;
begin
  select * into v_config from private.drain_config limit 1;
  -- An unconfigured environment must be a NO-OP. Without this the cron
  -- fires every ten minutes against a null URL and fills the Postgres log
  -- with errors that look like a broken drain rather than an unconfigured
  -- one.
  if not found then
    return;
  end if;

  perform net.http_post(
    url := v_config.function_url,
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-drain-secret', v_config.drain_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

revoke execute on function private.trigger_drain() from public, anon, authenticated;

-- Ten minutes, not once a day. The fan-out is day-granular, but a lone daily
-- drain means one transient FCM failure delays a reminder by a full day, and
-- next_reminder_batch's ten-minute claim lease already assumes re-entry on
-- roughly this scale.
--
-- unschedule first so re-running a reset does not accumulate duplicate jobs.
-- A FROM-less select is one synthesized row filtered by WHERE, so when the
-- exists() is false the target list is never evaluated and unschedule is
-- never called. This is a skip, not a call-and-ignore-the-error.
select cron.unschedule('reminder-drain')
where exists (select 1 from cron.job where jobname = 'reminder-drain');

select cron.schedule(
  'reminder-drain',
  '*/10 * * * *',
  $$ select private.trigger_drain(); $$
);

-- To configure an environment (NOT committed, run by hand):
--   insert into private.drain_config (function_url, drain_secret)
--   values ('https://<ref>.supabase.co/functions/v1/drain_reminders',
--           '<the same value as the DRAIN_SECRET function secret>')
--   on conflict (id) do update
--     set function_url = excluded.function_url,
--         drain_secret = excluded.drain_secret;
--
-- KNOWN GAP: net.http_post queues asynchronously and returns a request id
-- without ever raising, so a wrong URL or a dead function produces a cron
-- that reports success forever while nothing is delivered. Check delivery in
-- net._http_response, not in cron.job_run_details.
