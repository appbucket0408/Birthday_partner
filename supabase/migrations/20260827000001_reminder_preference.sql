-- The Settings screen's notification toggle. Defaults to on: a user who
-- installed a reminder app wants reminders, and an opt-out is the only shape
-- that does not silently drop the product's core function.
alter table public.profiles
  add column reminders_enabled boolean not null default true;

-- R14: profiles has NO table-level update grant for authenticated — it was
-- revoked and specific columns granted back one at a time. A new column is
-- therefore not client-writable until it is named here. The failure is LOUD,
-- not silent: updating a non-granted column raises
-- "permission denied for table profiles", and it aborts the whole statement
-- even when a granted column appears in the same SET list.
grant update (reminders_enabled) on public.profiles to authenticated;

-- The fan-out has to consult it. Without this the toggle is decorative.
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

    with due as (
      insert into private.notification_outbox (
        recipient_profile_id, subject_person_id, offset_days, occasion_date
      )
      select c.celebrator_profile_id, p.id, v_offset, v_target
      from public.celebrations c
      join public.people p on p.id = c.person_id
      join public.profiles r on r.id = c.celebrator_profile_id
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
        -- The Settings toggle.
        and r.reminders_enabled
        and not exists (
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
