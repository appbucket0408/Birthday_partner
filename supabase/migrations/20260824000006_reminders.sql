-- Scheduling lives in the database so it is testable without deploying
-- anything. The Edge Function that drains this table does only the HTTP call.
--
-- private, not public: nothing client-side reads it, and PostgREST cannot see
-- the private schema at all, so the API surface stays closed by construction.
create table private.notification_outbox (
  id bigint generated always as identity primary key,
  recipient_profile_id uuid not null references public.profiles (id) on delete cascade,
  subject_person_id bigint not null references public.people (id) on delete cascade,
  kind text not null default 'reminder',
  offset_days smallint not null,
  occasion_date date not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  claimed_at timestamptz,
  attempts int not null default 0,
  last_error text,
  constraint notification_outbox_kind_valid check (kind in ('reminder')),
  constraint notification_outbox_offset_valid check (offset_days in (7, 1, 0)),
  -- THE no-double-send guarantee. A cron re-run, a retry, or two overlapping
  -- schedules cannot produce a second notification for the same person, day and
  -- offset. Idempotency is a constraint here, not a convention.
  --
  -- `kind` is part of the key even though the check constraint admits only one
  -- value today: the day a second kind is added, a reminder and the new kind for
  -- the same person, date and offset would collide and the second would vanish
  -- silently into the fan-out's DO NOTHING.
  constraint notification_outbox_once
    unique (recipient_profile_id, subject_person_id, occasion_date, offset_days, kind)
);

-- `sent_at` is constant-null across every row this partial index contains, so
-- it is dead weight as a leading column. `attempts` is what the drain actually
-- filters on next.
create index notification_outbox_unsent_idx
  on private.notification_outbox (attempts, id)
  where sent_at is null;

create index notification_outbox_subject_idx
  on private.notification_outbox (subject_person_id);

alter table private.notification_outbox enable row level security;
-- No policies: service_role only, which is what the drain runs as.

-- Queue every reminder due relative to p_today. Returns the number of rows
-- actually inserted, so "0" is a meaningful answer meaning "nothing new".
create or replace function private.enqueue_reminders(p_today date default current_date)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted int := 0;
  v_offset smallint;
  v_target date;
  v_match_month smallint;
  v_match_day smallint;
begin
  foreach v_offset in array array[7, 1, 0]::smallint[]
  loop
    v_target := p_today + v_offset;
    v_match_month := extract(month from v_target)::smallint;
    v_match_day := extract(day from v_target)::smallint;

    -- A Feb 29 birthday has no Feb 29 to land on in a common year, so it is
    -- observed on Feb 28 — inside February, rather than sliding into March.
    -- On Feb 28 of a common year we therefore match both 28 and 29.
    with due as (
      insert into private.notification_outbox (
        recipient_profile_id, subject_person_id, offset_days, occasion_date
      )
      select c.celebrator_profile_id, p.id, v_offset, v_target
      from public.celebrations c
      join public.people p on p.id = c.person_id
      where p.birth_month is not null
        and p.birth_month = v_match_month
        and (
          p.birth_day = v_match_day
          or (
            v_match_month = 2 and v_match_day = 28
            and p.birth_day = 29
            and not (
              extract(year from v_target)::int % 4 = 0
              and (extract(year from v_target)::int % 100 <> 0
                   or extract(year from v_target)::int % 400 = 0)
            )
          )
        )
        and not exists (
          -- A block does not delete existing edges, so the fan-out has to
          -- filter. Without this we push a blocked person's name to the very
          -- user they blocked.
          select 1 from public.blocks b
          where b.blocker_profile_id = p.profile_id
            and b.blocked_profile_id = c.celebrator_profile_id
        )
      on conflict on constraint notification_outbox_once do nothing
      returning 1
    )
    select v_inserted + count(*)::int into v_inserted from due;
  end loop;

  return v_inserted;
end;
$$;

revoke execute on function private.enqueue_reminders(date)
  from public, anon, authenticated;

-- Claims its batch rather than just reading it. Two drains overlapping (a cron
-- tick landing on a slow retry) would otherwise both take the same rows and both
-- send; the enqueue-side unique constraint cannot help, because it guards
-- insertion, not delivery. `for update skip locked` alone is not enough either —
-- this runs as one implicit transaction, so the lock is gone the moment the
-- select returns.
--
-- The 10-minute lease means a drain that dies mid-send does not strand its rows
-- permanently. Eligibility requires a device to EXIST rather than joining to
-- one, which keeps p_limit counting reminders instead of token-rows AND stops a
-- device-less row being claimed and stranded.
create or replace function private.next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  with claimed as (
    update private.notification_outbox o
    set claimed_at = now()
    where o.id in (
      select c.id
      from private.notification_outbox c
      where c.sent_at is null
        and c.attempts < 5
        and (c.claimed_at is null or c.claimed_at < now() - interval '10 minutes')
        and exists (
          select 1 from public.device_tokens d
          where d.profile_id = c.recipient_profile_id
        )
      order by c.id
      limit p_limit
      for update skip locked
    )
    returning o.id, o.recipient_profile_id, o.subject_person_id,
              o.offset_days, o.occasion_date
  )
  select cl.id, d.token, d.platform, p.display_name, cl.offset_days, cl.occasion_date
  from claimed cl
  join public.device_tokens d on d.profile_id = cl.recipient_profile_id
  join public.people p on p.id = cl.subject_person_id
  order by cl.id;
$$;

revoke execute on function private.next_reminder_batch(int)
  from public, anon, authenticated;

create or replace function private.mark_reminder_sent(p_outbox_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.notification_outbox
  set sent_at = now(), last_error = null
  where id = p_outbox_id;
$$;

revoke execute on function private.mark_reminder_sent(bigint)
  from public, anon, authenticated;

create or replace function private.mark_reminder_failed(
  p_outbox_id bigint,
  p_error text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.notification_outbox
  set attempts = attempts + 1, last_error = p_error
  where id = p_outbox_id;
$$;

revoke execute on function private.mark_reminder_failed(bigint, text)
  from public, anon, authenticated;

-- ------------------------------------------------------------- rpc surface

-- R2: PostgREST exposes only the schemas in config.toml's `[api] schemas`,
-- which is ["public", "graphql_public"]. An Edge Function therefore CANNOT call
-- a private function directly — verified against the running stack, a request
-- with `Content-Profile: private` returns PGRST106 "Invalid schema: private".
--
-- Adding `private` to that list was rejected: the point of the private schema is
-- that it is unreachable through the API by construction, not merely by grant.
-- Instead each function the drain needs gets a thin public wrapper granted to
-- service_role and nobody else. Task 1's public allowlist assertion is what
-- catches a forgotten revoke here.
create or replace function public.rpc_next_reminder_batch(p_limit int default 100)
returns table (
  outbox_id bigint,
  token text,
  platform text,
  subject_name text,
  offset_days smallint,
  occasion_date date
)
language sql
security definer
set search_path = ''
as $$
  select * from private.next_reminder_batch(p_limit);
$$;

revoke execute on function public.rpc_next_reminder_batch(int)
  from public, anon, authenticated;
grant execute on function public.rpc_next_reminder_batch(int) to service_role;

create or replace function public.rpc_mark_reminder_sent(p_outbox_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.mark_reminder_sent(p_outbox_id);
$$;

revoke execute on function public.rpc_mark_reminder_sent(bigint)
  from public, anon, authenticated;
grant execute on function public.rpc_mark_reminder_sent(bigint) to service_role;

create or replace function public.rpc_mark_reminder_failed(
  p_outbox_id bigint,
  p_error text
)
returns void
language sql
security definer
set search_path = ''
as $$
  select private.mark_reminder_failed(p_outbox_id, p_error);
$$;

revoke execute on function public.rpc_mark_reminder_failed(bigint, text)
  from public, anon, authenticated;
grant execute on function public.rpc_mark_reminder_failed(bigint, text) to service_role;
