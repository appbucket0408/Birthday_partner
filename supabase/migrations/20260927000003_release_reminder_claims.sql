-- next_reminder_batch burns an attempt AS IT CLAIMS (20260824000006:31-32,
-- `set claimed_at = now(), attempts = o.attempts + 1`), before a single send
-- is tried. That is right when the drain then tries to send: a drain that
-- dies mid-flight must not retry forever.
--
-- It is WRONG when the drain abandons the whole batch before attempting
-- anything -- a failed OAuth2 mint, or a malformed FCM_SERVICE_ACCOUNT. The
-- drain returns 500 without marking any row failed, which looks safe and is
-- not: the rows keep their incremented `attempts`, the cron re-claims them
-- ten minutes later, and within about an hour every pending reminder crosses
-- `attempts < 5` and is silently excluded from the batch forever. Because
-- mark_reminder_failed was never called, `last_error` is null on every one of
-- them, so there is nothing to diagnose it from either.
--
-- This gives the attempt back for exactly that case. It is deliberately NOT
-- "reset attempts to 0": a row that has genuinely failed four times and is
-- then caught by one mint failure must come back at 4, not at 0.
create or replace function private.release_reminder_claims(p_ids bigint[])
returns int
language sql
security definer
set search_path = ''
as $$
  with released as (
    update private.notification_outbox
    set claimed_at = null,
        -- greatest(...,0) so a double release can never drive this negative
        -- and hand a row unlimited retries.
        attempts = greatest(attempts - 1, 0)
    where id = any(p_ids)
      and sent_at is null
    returning 1
  )
  select count(*)::int from released;
$$;

revoke execute on function private.release_reminder_claims(bigint[])
  from public, anon, authenticated;

-- The thin public wrapper the drain calls, granted to service_role only --
-- same shape as rpc_next_reminder_batch and the two mark_* wrappers.
create or replace function public.rpc_release_reminder_claims(p_ids bigint[])
returns int
language sql
security definer
set search_path = ''
as $$
  select private.release_reminder_claims(p_ids);
$$;

revoke execute on function public.rpc_release_reminder_claims(bigint[])
  from public, anon, authenticated;
grant execute on function public.rpc_release_reminder_claims(bigint[])
  to service_role;
