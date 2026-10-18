
create or replace function private.queue_test_push(
  p_profile_id uuid,
  p_kind text default 'reminder'
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person_id bigint;
  v_wish_id bigint;
  v_outbox_id bigint;
begin
  select p.id into v_person_id
  from public.people p
  where p.profile_id = p_profile_id;
  if v_person_id is null then
    raise exception 'profile % has no claimed person: finish onboarding first',
      p_profile_id;
  end if;

  if p_kind = 'reminder' then
    insert into private.notification_outbox (
      recipient_profile_id, subject_person_id, offset_days, occasion_date
    ) values (
      p_profile_id, v_person_id, 0, current_date
    )
    on conflict on constraint notification_outbox_once do update
      set sent_at = null, claimed_at = null, attempts = 0, last_error = null
    returning id into v_outbox_id;

  elsif p_kind = 'wish' then
    select w.id into v_wish_id
    from public.wishes w
    where w.subject_person_id = v_person_id
      and w.author_profile_id <> p_profile_id
      and w.kind = 'message'
    order by w.created_at desc, w.id desc
    limit 1;
    if v_wish_id is null then
      raise exception 'no wish by someone else on this member''s wall: post one from another account first';
    end if;

    insert into private.notification_outbox (
      recipient_profile_id, subject_person_id, kind, wish_id
    ) values (
      p_profile_id, v_person_id, 'wish', v_wish_id
    )
    on conflict (wish_id) where wish_id is not null do update
      set sent_at = null, claimed_at = null, attempts = 0, last_error = null
    returning id into v_outbox_id;

  else
    raise exception 'unknown kind %: use reminder or wish', p_kind;
  end if;

  return v_outbox_id;
end;
$$;

revoke execute on function private.queue_test_push(uuid, text)
  from public, anon, authenticated;

create or replace function public.rpc_queue_test_push(
  p_profile_id uuid,
  p_kind text default 'reminder'
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select private.queue_test_push(p_profile_id, p_kind);
$$;

revoke execute on function public.rpc_queue_test_push(uuid, text)
  from public, anon, authenticated;
grant execute on function public.rpc_queue_test_push(uuid, text) to service_role;
