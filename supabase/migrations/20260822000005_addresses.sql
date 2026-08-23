-- Owned by a person, not a profile: a non-user recipient confirming through
-- the tokenized web page has no profile (spec §6 rule 5).
create table public.addresses (
  id bigint generated always as identity primary key,
  owner_person_id bigint not null references public.people (id) on delete cascade,
  label text,
  line1 text not null,
  line2 text,
  city text not null,
  pincode text not null,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now(),
  constraint addresses_pincode_format check (pincode ~ '^[1-9][0-9]{5}$')
);

create index addresses_owner_person_id_idx on public.addresses (owner_person_id);

alter table public.addresses enable row level security;

-- The only policy on this table. There is no sender role here, and no policy
-- that any other user's session can satisfy (spec §6 rule 1).
create policy addresses_all_own
  on public.addresses
  for all
  to authenticated
  using (owner_person_id = (select private.my_person_id()))
  with check (owner_person_id = (select private.my_person_id()));

-- Used by confirm_gift on behalf of a non-user recipient, who has no session.
create or replace function private.set_address_for_person(
  p_person_id bigint,
  p_label text,
  p_line1 text,
  p_line2 text,
  p_city text,
  p_pincode text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if not exists (select 1 from public.people p where p.id = p_person_id) then
    raise exception 'person % not found', p_person_id;
  end if;

  insert into public.addresses (
    owner_person_id, label, line1, line2, city, pincode
  ) values (
    p_person_id, p_label, p_line1, p_line2, p_city, p_pincode
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function private.set_address_for_person(bigint, text, text, text, text, text)
  from public, anon, authenticated;
