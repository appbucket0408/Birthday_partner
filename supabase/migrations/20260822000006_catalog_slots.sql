create table public.service_areas (
  id bigint generated always as identity primary key,
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.service_areas enable row level security;

create table public.products (
  id bigint generated always as identity primary key,
  service_area_id bigint not null references public.service_areas (id) on delete cascade,
  name text not null,
  flavour text,
  size text,
  price_minor bigint not null,
  currency text not null default 'INR',
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint products_price_positive check (price_minor > 0),
  constraint products_currency_supported check (currency = 'INR')
);

create index products_service_area_id_idx on public.products (service_area_id);

alter table public.products enable row level security;

create table public.delivery_slots (
  id bigint generated always as identity primary key,
  service_area_id bigint not null references public.service_areas (id) on delete cascade,
  slot_date date not null,
  window_start time not null,
  window_end time not null,
  capacity int not null,
  reserved int not null default 0,
  created_at timestamptz not null default now(),
  constraint delivery_slots_capacity_non_negative check (capacity >= 0),
  constraint delivery_slots_reserved_non_negative check (reserved >= 0),
  -- The daily cap, enforced by the database rather than by remembering to check.
  constraint delivery_slots_not_oversold check (reserved <= capacity),
  constraint delivery_slots_window_ordered check (window_end > window_start),
  constraint delivery_slots_unique_window unique (service_area_id, slot_date, window_start)
);

create index delivery_slots_area_date_idx
  on public.delivery_slots (service_area_id, slot_date);

alter table public.delivery_slots enable row level security;

-- Catalog data is public to signed-in users and writable only by staff.
create policy service_areas_select_all
  on public.service_areas for select to authenticated using (true);

create policy service_areas_staff_write
  on public.service_areas for all to authenticated
  using ((select private.is_staff())) with check ((select private.is_staff()));

create policy products_select_active
  on public.products for select to authenticated using (is_active);

create policy products_staff_write
  on public.products for all to authenticated
  using ((select private.is_staff())) with check ((select private.is_staff()));

create policy delivery_slots_select_all
  on public.delivery_slots for select to authenticated using (true);

create policy delivery_slots_staff_write
  on public.delivery_slots for all to authenticated
  using ((select private.is_staff())) with check ((select private.is_staff()));

-- A single conditional UPDATE is atomic under read committed: the row is
-- locked, the predicate is re-evaluated against the updated row, and a loser
-- sees zero rows affected. No SELECT FOR UPDATE, no advisory lock, and no
-- lock held across an HTTP call to the payment provider.
create or replace function private.reserve_slot(p_slot_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.delivery_slots
  set reserved = reserved + 1
  where id = p_slot_id
    and reserved < capacity;

  if not found then
    raise exception 'delivery slot % is full or does not exist', p_slot_id
      using errcode = '23514';
  end if;
end;
$$;

create or replace function private.release_slot(p_slot_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.delivery_slots
  set reserved = reserved - 1
  where id = p_slot_id
    and reserved > 0;
end;
$$;

revoke execute on function private.reserve_slot(bigint) from public, anon, authenticated;
revoke execute on function private.release_slot(bigint) from public, anon, authenticated;
