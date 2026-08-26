begin;
select plan(3);

-- Every table in public AND private must have RLS enabled. Private tables are
-- server-only, but "server-only" is a schema property, not a row property —
-- service_role bypasses RLS and Edge Functions run as service_role. RLS stays
-- on there too, so a future policy is additive rather than a retrofit, and so
-- nothing is reachable if the schema is ever exposed.
select is_empty(
  $$ select n.nspname || '.' || c.relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = any(array['public', 'private'])
       and c.relkind = 'r'
       and not c.relrowsecurity $$,
  'every public and private table has row level security enabled'
);

-- Every foreign key column in public AND private must be indexed.
select is_empty(
  $$ select con.conrelid::regclass::text || '.' || a.attname
     from pg_constraint con
     join pg_attribute a
       on a.attrelid = con.conrelid and a.attnum = any (con.conkey)
     join pg_class c on c.oid = con.conrelid
     join pg_namespace n on n.oid = c.relnamespace
     where con.contype = 'f'
       and n.nspname = any(array['public', 'private'])
       and not exists (
         select 1 from pg_index i
         where i.indrelid = con.conrelid
           and a.attnum = (i.indkey)[0]
       ) $$,
  'every foreign key column in public and private is indexed'
);

-- R3: the same PUBLIC-executable-by-default trap as R13, but in `public`, where
-- the private allowlist does not look. Later tasks add server-side wrapper
-- functions in public that must be callable by service_role and nobody else; a
-- forgotten revoke would hand every signed-in user a server-side entry point.
-- This is an ALLOWLIST: extend it only for a function clients are meant to call.
select is(
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'my_birthday_stats,my_celebrates,ops_get_delivery_address,register_device_token',
  'only intentionally client-callable public functions are executable'
);

select * from finish();
rollback;
