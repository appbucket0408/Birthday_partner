create table public.orders (
  id bigint generated always as identity primary key,
  gift_id bigint not null unique references public.gifts (id) on delete cascade,
  bakery_name text,
  bakery_cost_minor bigint,
  courier text,
  tracking_ref text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_cost_non_negative check (bakery_cost_minor is null or bakery_cost_minor >= 0)
);

alter table public.orders enable row level security;

create policy orders_staff_all
  on public.orders
  for all
  to authenticated
  using ((select private.is_staff()))
  with check ((select private.is_staff()));

create table public.address_access_log (
  id bigint generated always as identity primary key,
  gift_id bigint not null references public.gifts (id) on delete cascade,
  address_id bigint not null references public.addresses (id) on delete cascade,
  staff_profile_id uuid not null references public.profiles (id) on delete restrict,
  accessed_at timestamptz not null default now()
);

create index address_access_log_gift_idx on public.address_access_log (gift_id);
create index address_access_log_address_idx on public.address_access_log (address_id);
create index address_access_log_staff_idx on public.address_access_log (staff_profile_id);

alter table public.address_access_log enable row level security;

-- Staff may read the log but never modify it: an audit trail its own subject
-- can edit is not an audit trail.
create policy address_access_log_staff_select
  on public.address_access_log
  for select
  to authenticated
  using ((select private.is_staff()));

-- The only path from the ops console to a real address. Gated on status,
-- logged on every call (spec §6 rule 3).
create or replace function public.ops_get_delivery_address(p_gift_id bigint)
returns table (
  recipient_name text,
  line1 text,
  line2 text,
  city text,
  pincode text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff uuid := (select auth.uid());
  v_address_id bigint;
  v_status public.gift_status;
begin
  if not private.is_staff() then
    raise exception 'not authorised' using errcode = '42501';
  end if;

  select g.delivery_address_id, g.status into v_address_id, v_status
  from public.gifts g where g.id = p_gift_id;

  if v_address_id is null
     or v_status not in ('confirmed', 'placed', 'out_for_delivery') then
    raise exception 'no deliverable address for gift %', p_gift_id
      using errcode = '42501';
  end if;

  insert into public.address_access_log (gift_id, address_id, staff_profile_id)
  values (p_gift_id, v_address_id, v_staff);

  return query
  select pe.display_name, a.line1, a.line2, a.city, a.pincode
  from public.addresses a
  join public.gifts g on g.delivery_address_id = a.id
  join public.people pe on pe.id = g.recipient_person_id
  where a.id = v_address_id;
end;
$$;

revoke execute on function public.ops_get_delivery_address(bigint) from public, anon;
grant execute on function public.ops_get_delivery_address(bigint) to authenticated;
