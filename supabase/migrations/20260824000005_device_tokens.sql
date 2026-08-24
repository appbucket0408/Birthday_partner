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
