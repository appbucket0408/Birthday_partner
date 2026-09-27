begin;
select plan(4);

-- 1. The new column exists. `proargnames` includes OUT parameters, which is
-- what a `returns table` column is. (has_column does not work on a function's
-- return table -- it is for real relations only.)
select ok(
  (select p.proargnames @> array['subject_person_id']
   from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'next_reminder_batch'),
  'the batch must carry the person id a tapped notification routes to');

-- 2-4. THE assertions this file exists for. `drop function` takes the ACL
-- with it and a recreated function is executable by public, so a migration
-- that drops must re-apply every revoke. This function is security definer
-- and reads EVERY user's device tokens.
select ok(
  not has_function_privilege('anon', 'public.rpc_next_reminder_batch(int)', 'execute'),
  'anon must NOT execute the wrapper after the drop-and-recreate');
select ok(
  not has_function_privilege('authenticated', 'public.rpc_next_reminder_batch(int)', 'execute'),
  'authenticated must NOT execute the wrapper after the drop-and-recreate');
select ok(
  has_function_privilege('service_role', 'public.rpc_next_reminder_batch(int)', 'execute'),
  'service_role must still execute it -- the drain runs as service_role');

select * from finish();
rollback;
