-- Match an address book against people the app already knows, and create
-- nothing. A bulk import that upserted would mint a row for every contact of
-- every user — thousands of people who never consented to anything — so the
-- row is minted later, by upsert_person, only when the user picks someone.
--
-- Hashing happens here because the pepper lives in private.config and must
-- never leave the database. That is why raw numbers reach the server at all.
create or replace function private.resolve_contacts(p_phones text[])
returns table (
  phone text,
  person_id bigint,
  display_name text,
  birth_month smallint,
  birth_day smallint
)
language sql
security definer
set search_path = ''
stable
as $$
  select distinct c.phone, p.id, p.display_name, p.birth_month, p.birth_day
  from unnest(p_phones) as c(phone)
  join public.people p
    on p.phone_e164_hash = private.phone_hash(c.phone)
  where not exists (
    select 1 from private.suppressions s
    where s.phone_e164_hash = p.phone_e164_hash
  );
$$;

revoke execute on function private.resolve_contacts(text[])
  from public, anon, authenticated;

-- R2: the Edge Function reaches this through a public wrapper, because
-- PostgREST exposes only public and graphql_public. service_role only.
create or replace function public.rpc_resolve_contacts(p_phones text[])
returns table (
  phone text,
  person_id bigint,
  display_name text,
  birth_month smallint,
  birth_day smallint
)
language sql
security definer
set search_path = ''
stable
as $$
  select * from private.resolve_contacts(p_phones);
$$;

revoke execute on function public.rpc_resolve_contacts(text[])
  from public, anon, authenticated;
grant execute on function public.rpc_resolve_contacts(text[]) to service_role;
