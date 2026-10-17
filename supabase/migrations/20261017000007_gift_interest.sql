-- "Send a cake" is not live yet: until payments exist it opens a Coming soon
-- screen that asks "Notify me when it's live". This is where those taps go,
-- so demand can be measured before the gifting flow is built out, and so
-- the people who asked can be told when it launches.
--
-- One row per (sender, recipient): tapping twice for the same friend is one
-- signal, not two. recipient is nullable and set null on delete so a
-- removed person does not erase the sender's interest.
create table public.gift_interest (
  id bigint generated always as identity primary key,
  profile_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  recipient_person_id bigint
    references public.people (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint gift_interest_once unique (profile_id, recipient_person_id)
);

-- profile_id is covered by the unique constraint's leading column;
-- recipient_person_id needs its own (11_rls_coverage: every FK is indexed),
-- for the on-delete-set-null from people.
create index gift_interest_recipient_idx
  on public.gift_interest (recipient_person_id);

alter table public.gift_interest enable row level security;

-- Your own interest only, and only for someone you actually celebrate --
-- the same people "Send a cake" is offered for.
create policy gift_interest_insert_own
  on public.gift_interest
  for insert
  to authenticated
  with check (
    profile_id = (select auth.uid())
    and exists (
      select 1 from public.celebrations c
      where c.celebrator_profile_id = (select auth.uid())
        and c.person_id = gift_interest.recipient_person_id
    )
  );

-- Read back only your own, so the screen can show "You're on the list".
-- Totals are read by the ops side with the service role.
create policy gift_interest_select_own
  on public.gift_interest
  for select
  to authenticated
  using (profile_id = (select auth.uid()));

revoke all on public.gift_interest from anon, authenticated;
grant select on public.gift_interest to authenticated;
grant insert (recipient_person_id) on public.gift_interest to authenticated;
