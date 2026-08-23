create table public.wishes (
  id bigint generated always as identity primary key,
  author_profile_id uuid not null references public.profiles (id) on delete cascade,
  subject_person_id bigint not null references public.people (id) on delete cascade,
  body text not null,
  -- 'message' is a wish someone typed; 'cake' is the automatic post made when
  -- a gift is delivered (spec §5 rule 6).
  kind text not null default 'message',
  occasion_year int not null,
  created_at timestamptz not null default now(),
  constraint wishes_body_length check (length(btrim(body)) between 1 and 500),
  constraint wishes_year_sane check (occasion_year between 2020 and 2100),
  constraint wishes_kind_valid check (kind in ('message', 'cake'))
);

-- One typed message per person per year, but any number of delivered cakes.
create unique index wishes_one_message_per_year
  on public.wishes (author_profile_id, subject_person_id, occasion_year)
  where kind = 'message';

create index wishes_subject_year_idx on public.wishes (subject_person_id, occasion_year);
create index wishes_author_idx on public.wishes (author_profile_id);

alter table public.wishes enable row level security;

-- Readable by anyone who can see the subject, which is the same rule that
-- governs the person record itself.
create policy wishes_select_visible
  on public.wishes
  for select
  to authenticated
  using ((select private.can_see_person(wishes.subject_person_id)));

-- Writable only by the author, and only for someone they actually celebrate.
create policy wishes_insert_own
  on public.wishes
  for insert
  to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and exists (
      select 1 from public.celebrations c
      where c.person_id = wishes.subject_person_id
        and c.celebrator_profile_id = (select auth.uid())
    )
  );

create policy wishes_delete_own
  on public.wishes
  for delete
  to authenticated
  -- A cake post is a record of a delivery, not the sender's to retract.
  using (author_profile_id = (select auth.uid()) and kind = 'message');

-- Delivery closes the loop: the wall shows who sent a cake, which is what
-- makes the next person send one (spec §5 rule 6).
create or replace function private.post_cake_wish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'delivered' and old.status is distinct from 'delivered' then
    insert into public.wishes (
      author_profile_id, subject_person_id, body, kind, occasion_year
    ) values (
      new.sender_profile_id,
      new.recipient_person_id,
      'sent a cake',
      'cake',
      extract(year from new.occasion_date)::int
    );
  end if;
  return new;
end;
$$;

create trigger gifts_post_cake_wish
  after update on public.gifts
  for each row execute function private.post_cake_wish();

-- R13: the cake-post trigger function is PUBLIC-executable by default.
revoke execute on function private.post_cake_wish() from public, anon, authenticated;
