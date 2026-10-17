
drop function public.rpc_resolve_contacts(text[]);
drop function private.resolve_contacts(text[]);

create function private.resolve_contacts(p_phones text[])
returns table (
  phone text,
  person_id bigint,
  display_name text,
  is_member boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct c.phone, p.id, p.display_name, (p.profile_id is not null)
  from unnest(p_phones) as c(phone)
  join public.people p
    on p.phone_e164_hash = private.phone_hash(c.phone)
  where not exists (
    select 1 from private.suppressions s
    where s.phone_e164_hash = p.phone_e164_hash
  );
$$;

create function public.rpc_resolve_contacts(p_phones text[])
returns table (
  phone text,
  person_id bigint,
  display_name text,
  is_member boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.resolve_contacts(p_phones);
$$;

-- Same exposure as before: the resolve_contacts Edge Function (service_role)
-- only.
revoke execute on function private.resolve_contacts(text[])
  from public, anon, authenticated;
revoke execute on function public.rpc_resolve_contacts(text[])
  from public, anon, authenticated;
grant execute on function public.rpc_resolve_contacts(text[]) to service_role;
