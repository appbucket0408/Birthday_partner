create type public.gift_status as enum (
  'draft',
  'paid',
  'awaiting_confirm',
  'confirmed',
  'placed',
  'out_for_delivery',
  'delivered',
  'expired',
  'declined',
  'delivery_failed',
  'refunded'
);

create table public.gifts (
  id bigint generated always as identity primary key,
  -- The public handle used by the invite link. The row id is never exposed in
  -- a URL, and the token is single-use via confirm_token_used_at.
  confirm_token uuid not null default gen_random_uuid() unique,
  sender_profile_id uuid not null references public.profiles (id) on delete restrict,
  recipient_person_id bigint not null references public.people (id) on delete restrict,
  product_id bigint not null references public.products (id) on delete restrict,
  service_area_id bigint not null references public.service_areas (id) on delete restrict,
  slot_id bigint references public.delivery_slots (id) on delete set null,
  occasion_date date not null,
  amount_minor bigint not null,
  currency text not null default 'INR',
  message text,
  status public.gift_status not null default 'draft',
  slot_hold_expires_at timestamptz,
  delivery_address_id bigint references public.addresses (id) on delete set null,
  -- Denormalized so the sender can see the city without any access to the
  -- addresses row. Written only at confirmation (spec §6 rule 2).
  delivery_city text,
  payment_ref text,
  confirm_token_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gifts_amount_positive check (amount_minor > 0),
  constraint gifts_currency_supported check (currency = 'INR'),
  constraint gifts_message_length check (message is null or length(message) <= 280)
);

create index gifts_sender_idx on public.gifts (sender_profile_id);
create index gifts_recipient_idx on public.gifts (recipient_person_id);
create index gifts_product_idx on public.gifts (product_id);
create index gifts_service_area_idx on public.gifts (service_area_id);
create index gifts_slot_idx on public.gifts (slot_id);
create index gifts_delivery_address_idx on public.gifts (delivery_address_id);
-- Drives the ops manifest and the expiry sweep.
create index gifts_status_occasion_idx on public.gifts (status, occasion_date);

alter table public.gifts enable row level security;

create table public.gift_events (
  id bigint generated always as identity primary key,
  gift_id bigint not null references public.gifts (id) on delete cascade,
  from_status public.gift_status,
  to_status public.gift_status not null,
  actor_profile_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index gift_events_gift_id_idx on public.gift_events (gift_id);
create index gift_events_actor_idx on public.gift_events (actor_profile_id);

alter table public.gift_events enable row level security;

-- The legal graph, as data (spec §5).
create table private.gift_transitions (
  from_status public.gift_status not null,
  to_status public.gift_status not null,
  primary key (from_status, to_status)
);

insert into private.gift_transitions (from_status, to_status) values
  ('draft', 'paid'),
  ('draft', 'expired'),
  ('paid', 'awaiting_confirm'),
  ('paid', 'refunded'),
  ('awaiting_confirm', 'confirmed'),
  ('awaiting_confirm', 'declined'),
  ('awaiting_confirm', 'expired'),
  ('confirmed', 'placed'),
  ('confirmed', 'delivery_failed'),
  ('placed', 'out_for_delivery'),
  ('placed', 'delivery_failed'),
  ('out_for_delivery', 'delivered'),
  ('out_for_delivery', 'delivery_failed'),
  ('expired', 'refunded'),
  ('declined', 'refunded'),
  ('delivery_failed', 'refunded');

alter table private.gift_transitions enable row level security;

-- The only sanctioned way to move a gift. Takes a row lock so two webhook
-- deliveries cannot both advance the same gift.
create or replace function private.gift_transition(
  p_gift_id bigint,
  p_to public.gift_status,
  p_actor uuid default null
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from public.gift_status;
  v_row public.gifts;
begin
  select g.status into v_from
  from public.gifts g
  where g.id = p_gift_id
  for update;

  if v_from is null then
    raise exception 'gift % not found', p_gift_id using errcode = '23503';
  end if;

  if not exists (
    select 1 from private.gift_transitions t
    where t.from_status = v_from and t.to_status = p_to
  ) then
    raise exception 'illegal gift transition % to %', v_from, p_to
      using errcode = '23514';
  end if;

  -- Unlock the guard trigger for this statement only.
  perform set_config('app.gift_transition', 'on', true);

  update public.gifts
  set status = p_to,
      updated_at = now()
  where id = p_gift_id
  returning * into v_row;

  perform set_config('app.gift_transition', 'off', true);

  insert into public.gift_events (gift_id, from_status, to_status, actor_profile_id)
  values (p_gift_id, v_from, p_to, p_actor);

  return v_row;
end;
$$;

revoke execute on function private.gift_transition(bigint, public.gift_status, uuid)
  from public, anon, authenticated;

-- Blocks any status write that did not come through gift_transition. RLS
-- cannot do this job, because the service role bypasses RLS and Edge
-- Functions run as the service role.
create or replace function private.guard_gift_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
     and coalesce(current_setting('app.gift_transition', true), 'off') <> 'on' then
    raise exception 'gift status must change through private.gift_transition';
  end if;
  return new;
end;
$$;

create trigger gifts_guard_status
  before update on public.gifts
  for each row execute function private.guard_gift_status();

-- ------------------------------------------------------------- policies

-- Sender, recipient and staff may read a gift. delivery_address_id is visible
-- to the sender as a bare integer, which discloses nothing: the addresses row
-- it points at is unreadable to them (Task 5).
create policy gifts_select_participants
  on public.gifts
  for select
  to authenticated
  using (
    sender_profile_id = (select auth.uid())
    or recipient_person_id = (select private.my_person_id())
    or (select private.is_staff())
  );

-- No insert, update or delete policies. Every write goes through a
-- security-definer function invoked by an Edge Function.

create policy gift_events_select_staff
  on public.gift_events
  for select
  to authenticated
  using ((select private.is_staff()));

-- R13: the guard trigger function is a private helper and is PUBLIC-executable
-- by default. A trigger fires regardless of the invoking role's EXECUTE
-- privilege (that is checked at CREATE TRIGGER time), so revoking it does not
-- disarm the guard — proved by 02_profiles' own update path against the
-- identically revoked private.sync_person_from_profile().
revoke execute on function private.guard_gift_status() from public, anon, authenticated;
