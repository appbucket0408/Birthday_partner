begin;
select plan(4);

-- 1-3: the wrapper is reachable by service_role and by nobody else. This is the
-- whole security posture of the confirm endpoint: the token is the capability,
-- and the ONLY thing that may turn a token into an address write is the Edge
-- Function running as service_role.
select ok(
  has_function_privilege('service_role',
    'public.rpc_confirm_gift(uuid,text,text,text,text,text)', 'EXECUTE'),
  'service_role can execute rpc_confirm_gift'
);
select ok(
  not has_function_privilege('anon',
    'public.rpc_confirm_gift(uuid,text,text,text,text,text)', 'EXECUTE'),
  'anon CANNOT execute rpc_confirm_gift'
);
select ok(
  not has_function_privilege('authenticated',
    'public.rpc_confirm_gift(uuid,text,text,text,text,text)', 'EXECUTE'),
  'authenticated CANNOT execute rpc_confirm_gift'
);

-- 4: search_path is pinned. A security definer function without this is the
-- classic privilege-escalation shape: a caller-controlled search_path can
-- resolve an unqualified name to their own object.
select is(
  (select p.proconfig::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rpc_confirm_gift'),
  '{"search_path=\"\""}',
  'rpc_confirm_gift pins an empty search_path'
);

select * from finish();
rollback;
