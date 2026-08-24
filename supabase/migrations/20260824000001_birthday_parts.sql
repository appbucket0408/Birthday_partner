-- Reminders need a month and a day. A year is a bonus that device address books
-- frequently do not carry, and a `date` column cannot represent "March 15, year
-- unknown" at all. Splitting the column removes that whole class of problem.

-- ---------------------------------------------------------------- people

alter table public.people
  add column birth_month smallint,
  add column birth_day smallint,
  add column birth_year smallint;

update public.people
set birth_month = extract(month from birthday)::smallint,
    birth_day   = extract(day from birthday)::smallint,
    birth_year  = extract(year from birthday)::smallint
where birthday is not null;

alter table public.people drop constraint people_birthday_sane;
alter table public.people drop column birthday;

alter table public.people
  add constraint people_birth_parts_together
    check ((birth_month is null) = (birth_day is null)),
  add constraint people_birth_month_valid
    check (birth_month is null or birth_month between 1 and 12),
  add constraint people_birth_day_valid
    check (birth_day is null or birth_day between 1 and 31),
  add constraint people_birth_day_in_month
    check (
      birth_month is null or birth_day is null
      or birth_day <= case birth_month
           when 2 then 29
           when 4 then 30 when 6 then 30 when 9 then 30 when 11 then 30
           else 31 end
    ),
  add constraint people_birth_year_needs_parts
    check (birth_year is null or birth_month is not null),
  add constraint people_birth_year_sane
    check (
      birth_year is null
      or (
        birth_year between 1900 and extract(year from current_date)::int
        and (
          birth_year < extract(year from current_date)::int
          or (birth_month, birth_day)
             <= (extract(month from current_date)::smallint,
                 extract(day from current_date)::smallint)
        )
      )
    ),
  add constraint people_birth_leap_valid
    check (
      birth_year is null or birth_month is null
      or not (birth_month = 2 and birth_day = 29)
      or (birth_year % 4 = 0 and (birth_year % 100 <> 0 or birth_year % 400 = 0))
    );

-- The reminder fan-out matches month and day for an exact target date, so this
-- is an equality lookup. No date arithmetic, no December-to-January wraparound.
create index people_birth_parts_idx on public.people (birth_month, birth_day);

-- ---------------------------------------------------------------- profiles

-- The trigger is declared `after update of display_name, date_of_birth`, so it
-- depends on the column and the drop fails without removing it first. Verified:
-- "cannot drop column date_of_birth ... trigger profiles_sync_person depends on
-- column date_of_birth".
drop trigger profiles_sync_person on public.profiles;

alter table public.profiles
  add column birth_month smallint,
  add column birth_day smallint,
  add column birth_year smallint;

update public.profiles
set birth_month = extract(month from date_of_birth)::smallint,
    birth_day   = extract(day from date_of_birth)::smallint,
    birth_year  = extract(year from date_of_birth)::smallint
where date_of_birth is not null;

alter table public.profiles drop constraint profiles_dob_sane;
alter table public.profiles drop column date_of_birth;

alter table public.profiles
  add constraint profiles_birth_parts_together
    check ((birth_month is null) = (birth_day is null)),
  add constraint profiles_birth_month_valid
    check (birth_month is null or birth_month between 1 and 12),
  add constraint profiles_birth_day_valid
    check (birth_day is null or birth_day between 1 and 31),
  add constraint profiles_birth_day_in_month
    check (
      birth_month is null or birth_day is null
      or birth_day <= case birth_month
           when 2 then 29
           when 4 then 30 when 6 then 30 when 9 then 30 when 11 then 30
           else 31 end
    ),
  add constraint profiles_birth_year_needs_parts
    check (birth_year is null or birth_month is not null),
  add constraint profiles_birth_year_sane
    check (
      birth_year is null
      or (
        birth_year between 1900 and extract(year from current_date)::int
        and (
          birth_year < extract(year from current_date)::int
          or (birth_month, birth_day)
             <= (extract(month from current_date)::smallint,
                 extract(day from current_date)::smallint)
        )
      )
    ),
  add constraint profiles_birth_leap_valid
    check (
      birth_year is null or birth_month is null
      or not (birth_month = 2 and birth_day = 29)
      or (birth_year % 4 = 0 and (birth_year % 100 <> 0 or birth_year % 400 = 0))
    );

-- R14: date_of_birth carried `authenticated=w` and that grant died with the
-- column. Without these three the app cannot write a birthday and there is no
-- error to trace — the update simply affects nothing it was not granted.
grant update (birth_month, birth_day, birth_year) on public.profiles to authenticated;

-- ---------------------------------------------------------------- functions

create or replace function private.upsert_person(
  p_phone text,
  p_display_name text,
  p_birth_month smallint default null,
  p_birth_day smallint default null,
  p_birth_year smallint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := private.phone_hash(p_phone);
  v_id bigint;
begin
  -- A half-known date is a caller bug, and the table constraint would reject it
  -- with a message about a constraint rather than about the argument. Fail here
  -- where the reason is obvious.
  if (p_birth_month is null) <> (p_birth_day is null) then
    raise exception 'a birthday needs both a month and a day, or neither'
      using errcode = '23514';
  end if;

  if exists (select 1 from private.suppressions s where s.phone_e164_hash = v_hash) then
    return null;
  end if;

  select p.id into v_id from public.people p where p.phone_e164_hash = v_hash;

  if v_id is not null then
    -- Never overwrite a name or birthday the person set themselves; only fill
    -- blanks left by earlier imports.
    update public.people
    set birth_month = coalesce(birth_month, p_birth_month),
        birth_day   = coalesce(birth_day, p_birth_day),
        birth_year  = coalesce(birth_year, p_birth_year)
    where id = v_id and profile_id is null;
    return v_id;
  end if;

  insert into public.people (
    phone_e164_hash, display_name, birth_month, birth_day, birth_year
  )
  values (v_hash, p_display_name, p_birth_month, p_birth_day, p_birth_year)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function private.upsert_person(text, text, smallint, smallint, smallint)
  from public, anon, authenticated;

-- The old three-argument form would otherwise linger as a callable overload
-- taking a date, and callers would silently keep using it.
drop function if exists private.upsert_person(text, text, date);

create or replace function private.claim_person(
  p_profile_id uuid,
  p_phone text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := private.phone_hash(p_phone);
  v_id bigint;
  v_name text;
  v_month smallint;
  v_day smallint;
  v_year smallint;
begin
  select p.display_name, p.birth_month, p.birth_day, p.birth_year
    into v_name, v_month, v_day, v_year
  from public.profiles p where p.id = p_profile_id;

  insert into public.people (
    phone_e164_hash, display_name, birth_month, birth_day, birth_year, profile_id
  )
  values (v_hash, coalesce(v_name, 'New user'), v_month, v_day, v_year, p_profile_id)
  on conflict (phone_e164_hash) do update
    set profile_id  = p_profile_id,
        display_name = coalesce(v_name, public.people.display_name),
        birth_month = coalesce(v_month, public.people.birth_month),
        birth_day   = coalesce(v_day, public.people.birth_day),
        birth_year  = coalesce(v_year, public.people.birth_year)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function private.claim_person(uuid, text)
  from public, anon, authenticated;

create or replace function private.sync_person_from_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.people
  set display_name = new.display_name,
      birth_month = coalesce(new.birth_month, birth_month),
      birth_day   = coalesce(new.birth_day, birth_day),
      birth_year  = coalesce(new.birth_year, birth_year)
  where profile_id = new.id;
  return new;
end;
$$;

revoke execute on function private.sync_person_from_profile()
  from public, anon, authenticated;

create trigger profiles_sync_person
  after update of display_name, birth_month, birth_day, birth_year
  on public.profiles
  for each row execute function private.sync_person_from_profile();
