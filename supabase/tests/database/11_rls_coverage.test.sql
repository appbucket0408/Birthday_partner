begin;
select plan(2);

-- Every table in public must have RLS enabled.
select is_empty(
  $$ select c.relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'r'
       and not c.relrowsecurity $$,
  'every public table has row level security enabled'
);

-- Every foreign key column in public must be indexed.
select is_empty(
  $$ select con.conrelid::regclass::text || '.' || a.attname
     from pg_constraint con
     join pg_attribute a
       on a.attrelid = con.conrelid and a.attnum = any (con.conkey)
     join pg_class c on c.oid = con.conrelid
     join pg_namespace n on n.oid = c.relnamespace
     where con.contype = 'f'
       and n.nspname = 'public'
       and not exists (
         select 1 from pg_index i
         where i.indrelid = con.conrelid
           and a.attnum = (i.indkey)[0]
       ) $$,
  'every foreign key column in public is indexed'
);

select * from finish();
rollback;
