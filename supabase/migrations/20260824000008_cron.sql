-- pg_cron is already in shared_preload_libraries on both local and hosted
-- Supabase, so creating the extension is all that is required.
--
-- No `with schema` clause: pg_cron's control file pins it to pg_catalog and it
-- creates its own `cron` schema for cron.job regardless. Verified on this
-- database as the non-superuser `postgres` role: cron.job is reachable and
-- cron.schedule returns a job id.
create extension if not exists pg_cron;

-- 03:00 UTC. Reminders are day-granular, so the exact hour only needs to be
-- early enough that a T-0 reminder arrives on the morning of the day itself.
-- unschedule first so re-running a reset does not accumulate duplicate jobs.
select cron.unschedule('birthday-reminder-fanout')
where exists (select 1 from cron.job where jobname = 'birthday-reminder-fanout');

select cron.schedule(
  'birthday-reminder-fanout',
  '0 3 * * *',
  $$ select private.enqueue_reminders(); $$
);
