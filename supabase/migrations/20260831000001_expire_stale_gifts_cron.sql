-- Spec 2026-08-30 §4. private.expire_stale_gifts() shipped in M0 and nothing
-- ever called it. Slot capacity is a hard constraint
-- (delivery_slots_not_oversold), so an abandoned draft holds a delivery slot
-- PERMANENTLY and a real customer eventually cannot book a van that is free.
--
-- This is the same shape as M1's "nothing triggers the drain yet", with one
-- difference that makes it fixable now rather than deferred: the drain needed
-- FCM credentials; this needs nothing. It is pure SQL.
--
-- Every ten minutes. The hold is fifteen, so a released slot is bookable again
-- within a few minutes of being abandoned -- fast enough that a sender who
-- reloads sees it free, slow enough to be trivial load.
--
-- unschedule first, guarded by exists(), so re-running a db reset does not
-- accumulate duplicate jobs. A FROM-less select is one synthesized row filtered
-- by WHERE, so when the exists() is false the target list is never evaluated
-- and unschedule is never called. That is a skip, not a call-and-ignore.
select cron.unschedule('gift-hold-sweep')
where exists (select 1 from cron.job where jobname = 'gift-hold-sweep');

select cron.schedule(
  'gift-hold-sweep',
  '*/10 * * * *',
  $$ select private.expire_stale_gifts(); $$
);
