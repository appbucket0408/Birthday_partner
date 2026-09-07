-- F3: the slot must fall on the occasion date, enforced in the database.
--
-- Phase 1a enforced `slot_date = occasion_date` only in the slot picker's
-- client-side exact-date filter (slot_picker_screen.dart). private.create_gift
-- checked the sender, self-gifting, the product being active, the slot's
-- service area, and capacity -- but never the date -- and gifts carried no
-- such constraint. Anything creating a gift outside the picker (a future
-- deep link, an ops tool, a script) could write a row whose van arrives on a
-- day different from the occasion it records.
--
-- This closes ruling F3 by adding the check here, in the same transaction
-- that reserves the slot. The picker's client-side filter stays -- this is
-- defence in depth, not a relocation of the only check.
--
-- private.create_gift is recreated in full (copied from
-- 20260822000008_gift_lifecycle.sql:20-85) so this migration is
-- self-contained; only the slot lookup block changes.
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
  v_slot_date date;
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

  -- The slot must belong to the same service area as the product, and its
  -- date must be the occasion date -- one cake, one day, both checked in
  -- the same lookup rather than a second query.
  select s.slot_date into v_slot_date
  from public.delivery_slots s
  where s.id = p_slot_id and s.service_area_id = v_area;

  if v_slot_date is null then
    raise exception 'slot % is not in the product''s service area', p_slot_id
      using errcode = '23514';
  end if;

  if v_slot_date <> p_occasion_date then
    raise exception
      'slot % falls on % but the occasion date is %',
      p_slot_id, v_slot_date, p_occasion_date
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
