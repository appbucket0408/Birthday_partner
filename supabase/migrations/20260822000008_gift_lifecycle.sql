-- Webhook idempotency. A provider that delivers the same event twice must not
-- advance a gift twice or refund twice.
create table public.payment_events (
  id bigint generated always as identity primary key,
  provider text not null default 'razorpay',
  provider_event_id text not null unique,
  gift_id bigint references public.gifts (id) on delete set null,
  payload jsonb,
  created_at timestamptz not null default now()
);

create index payment_events_gift_id_idx on public.payment_events (gift_id);

alter table public.payment_events enable row level security;
-- No policies: service role only.

-- Reserve the slot and create the gift in one short transaction. The payment
-- provider is called by the Edge Function afterwards, outside any transaction,
-- so no row lock is ever held across a network round trip.
create or replace function private.create_gift(
  p_sender uuid,
  p_recipient_person_id bigint,
  p_product_id bigint,
  p_slot_id bigint,
  p_occasion_date date,
  p_message text default null,
  p_hold_minutes int default 15
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.gifts;
  v_area bigint;
  v_price bigint;
begin
  if p_sender is null then
    raise exception 'a gift needs a sender';
  end if;

  if p_recipient_person_id = (
    select p.id from public.people p where p.profile_id = p_sender
  ) then
    raise exception 'you cannot send a cake to yourself';
  end if;

  select pr.service_area_id, pr.price_minor into v_area, v_price
  from public.products pr
  where pr.id = p_product_id and pr.is_active;

  if v_area is null then
    raise exception 'product % is not available', p_product_id;
  end if;

  -- The slot must belong to the same service area as the product.
  if not exists (
    select 1 from public.delivery_slots s
    where s.id = p_slot_id and s.service_area_id = v_area
  ) then
    raise exception 'slot % is not in the product''s service area', p_slot_id
      using errcode = '23514';
  end if;

  perform private.reserve_slot(p_slot_id);

  insert into public.gifts (
    sender_profile_id, recipient_person_id, product_id, service_area_id,
    slot_id, occasion_date, amount_minor, message, status, slot_hold_expires_at
  ) values (
    p_sender, p_recipient_person_id, p_product_id, v_area,
    p_slot_id, p_occasion_date, v_price, p_message, 'draft',
    now() + make_interval(mins => p_hold_minutes)
  )
  returning * into v_row;

  insert into public.gift_events (gift_id, from_status, to_status, actor_profile_id)
  values (v_row.id, null, 'draft', p_sender);

  return v_row;
end;
$$;

-- Called by the payment webhook. Idempotent on provider_event_id.
create or replace function private.mark_gift_paid(
  p_gift_id bigint,
  p_payment_ref text,
  p_provider_event_id text
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.gifts;
begin
  insert into public.payment_events (provider_event_id, gift_id)
  values (p_provider_event_id, p_gift_id)
  on conflict (provider_event_id) do nothing;

  if not found then
    -- Already processed. Return current state rather than replaying.
    select * into v_row from public.gifts where id = p_gift_id;
    return v_row;
  end if;

  -- R4: no set_config wrapper. gifts_guard_status fires only when status
  -- changes and this update does not touch status, so the wrapper was dead
  -- code that would silently wave a future status write past the guard.
  update public.gifts
  set payment_ref = p_payment_ref,
      slot_hold_expires_at = null
  where id = p_gift_id;

  v_row := private.gift_transition(p_gift_id, 'paid');
  v_row := private.gift_transition(p_gift_id, 'awaiting_confirm');

  return v_row;
end;
$$;

-- The recipient's side, reached from the app or from the tokenized web page.
create or replace function private.confirm_gift(
  p_confirm_token uuid,
  p_line1 text,
  p_line2 text,
  p_city text,
  p_pincode text,
  p_label text default 'Home'
)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gift public.gifts;
  v_address_id bigint;
  v_area_name text;
begin
  select * into v_gift
  from public.gifts
  where confirm_token = p_confirm_token
  for update;

  if v_gift.id is null then
    raise exception 'unknown confirmation link';
  end if;

  if v_gift.confirm_token_used_at is not null then
    raise exception 'this confirmation link has already been used';
  end if;

  if v_gift.status <> 'awaiting_confirm' then
    raise exception 'gift % is not awaiting confirmation', v_gift.id
      using errcode = '23514';
  end if;

  -- Out of the service area means refund, not delivery (spec §5 rule 5).
  select a.name into v_area_name
  from public.service_areas a where a.id = v_gift.service_area_id;

  if lower(p_city) <> lower(v_area_name) then
    -- R20: this path must NOT raise. The plan did the decline, the slot release
    -- and the refund and then raised, which rolls all three back — the sender's
    -- money is never returned and the slot stays held. Proved by test 14:
    -- "have: awaiting_confirm slot_reserved=1". Spec 5 rule 5 makes the refund
    -- the whole point of the out-of-area case, so the outcome is reported
    -- through the returned row's status ('refunded'), not through an exception.
    -- A retry is already impossible: the gift is no longer awaiting_confirm, so
    -- a second call fails the status check below with 23514.
    perform private.gift_transition(v_gift.id, 'declined');
    perform private.release_slot(v_gift.slot_id);
    return private.refund_gift(v_gift.id);
  end if;

  v_address_id := private.set_address_for_person(
    v_gift.recipient_person_id, p_label, p_line1, p_line2, p_city, p_pincode
  );

  -- R4: as in mark_gift_paid — this update does not touch status.
  update public.gifts
  set delivery_address_id = v_address_id,
      delivery_city = p_city,
      confirm_token_used_at = now()
  where id = v_gift.id;

  return private.gift_transition(v_gift.id, 'confirmed');
end;
$$;

create or replace function private.refund_gift(p_gift_id bigint)
returns public.gifts
language plpgsql
security definer
set search_path = ''
as $$
begin
  return private.gift_transition(p_gift_id, 'refunded');
end;
$$;

-- Run by pg_cron in M4. Releases abandoned checkout holds, and expires gifts
-- that were paid for but never confirmed before the cutoff.
create or replace function private.expire_stale_gifts()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  r record;
begin
  -- Abandoned drafts: release the slot, expire the gift. No money was taken.
  for r in
    select id, slot_id from public.gifts
    where status = 'draft' and slot_hold_expires_at < now()
  loop
    perform private.release_slot(r.slot_id);
    perform private.gift_transition(r.id, 'expired');
    v_count := v_count + 1;
  end loop;

  -- Paid but unconfirmed past the cutoff: expire, release, refund.
  for r in
    select id, slot_id from public.gifts
    where status = 'awaiting_confirm'
      and occasion_date <= current_date
  loop
    perform private.gift_transition(r.id, 'expired');
    perform private.release_slot(r.slot_id);
    perform private.gift_transition(r.id, 'refunded');
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function private.create_gift(uuid, bigint, bigint, bigint, date, text, int)
  from public, anon, authenticated;
revoke execute on function private.mark_gift_paid(bigint, text, text)
  from public, anon, authenticated;
revoke execute on function private.confirm_gift(uuid, text, text, text, text, text)
  from public, anon, authenticated;
revoke execute on function private.refund_gift(bigint) from public, anon, authenticated;
revoke execute on function private.expire_stale_gifts() from public, anon, authenticated;
