-- One row per device per user. The token is the user's own property, so the app
-- writes it directly rather than through an Edge Function; RLS is the boundary.
create table public.device_tokens (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint device_tokens_platform_valid check (platform in ('ios', 'android'))
);

create index device_tokens_profile_id_idx on public.device_tokens (profile_id);

alter table public.device_tokens enable row level security;

-- for all: the app inserts on sign-in, updates last_seen_at, and deletes on
-- sign-out. A signed-out device that keeps its row keeps receiving someone
-- else's reminders.
create policy device_tokens_all_own
  on public.device_tokens
  for all
  to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- A physical device's push token can legitimately move between accounts: an
-- unclean sign-out, a reinstall that reuses the token, or a handed-down phone.
-- Owner-only RLS means the new user can neither insert (unique violation on
-- token) nor clear the stale row, so without this the device can never register
-- again and the user silently receives nothing.
--
-- Possession of the token is what proves you are on that device, which is the
-- standard basis for reassigning it. security definer because the caller by
-- definition does not own the row being removed.
--
-- The real reachable consequence of an attacker obtaining a victim's device
-- token (leaked log, compromised client, shared device) is not just noise: the
-- attacker calls this function to move the token onto their own account, then
-- arranges a celebrated person whose `display_name` is arbitrary text with a
-- birthday of today. The reminder pipeline then delivers that attacker-chosen
-- text as a trusted push notification straight to the victim's device — while
-- the victim silently stops receiving their own reminders, since the token no
-- longer points at them. Phase 2 MUST NOT place an unsanitised `display_name`
-- in a notification title or body; this is the path that makes it exploitable.
create or replace function public.register_device_token(
  p_token text,
  p_platform text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if (select auth.uid()) is null then
    raise exception 'a device token needs a signed-in user'
      using errcode = '42501';
  end if;

  delete from public.device_tokens where token = p_token;

  insert into public.device_tokens (profile_id, token, platform)
  values ((select auth.uid()), p_token, p_platform)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.register_device_token(text, text)
  from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
