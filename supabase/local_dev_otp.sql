-- LOCAL ONLY: every phone number accepts the OTP "123456".
--
-- Loaded by `supabase db reset` through [db.seed] in config.toml, together
-- with the [auth.hook.send_sms] entry there. It is deliberately NOT a
-- migration: `supabase db push` never sends this file to a hosted project.
-- On a hosted project this would let anyone sign in as anyone -- never run
-- it there (no `db push --include-seed`, no `db reset --linked`, no
-- `config push`; see check-no-config-push.sh).
--
-- How it works. GoTrue has no wildcard test OTP ([auth.sms.test_otp] is a
-- per-number list), and the local Twilio credentials are placeholders, so an
-- unlisted number fails at "send". Two pieces:
--
--   1. local_dev.send_sms is the Send SMS hook: it sends nothing, and
--      records the generated code against its destination number.
--   2. GoTrue saves the code's hash -- sha224(phone || otp) -- only AFTER
--      the hook returns. A trigger on auth.users and auth.one_time_tokens
--      sees that save, and when the hash is exactly one the hook just
--      recorded, swaps it for sha224(phone || '123456').
--
-- Matching the exact recorded hash keeps email tokens (hashed from the
-- email address) and everything else GoTrue writes untouched. Numbers in
-- [auth.sms.test_otp] never reach the hook; they keep working as before.

create schema if not exists local_dev;

create table if not exists local_dev.sent_sms (
  phone text not null,
  otp text not null,
  sent_at timestamptz not null default now()
);

create or replace function local_dev.send_sms(event jsonb)
returns jsonb
language plpgsql
as $$
begin
  delete from local_dev.sent_sms where sent_at < now() - interval '1 hour';
  insert into local_dev.sent_sms (phone, otp)
  values (event->'sms'->>'phone', event->'sms'->>'otp');
  return '{}'::jsonb;
end;
$$;

-- The fixed-code hash for [phone] when [token] is a code the hook just sent
-- to it; otherwise [token] unchanged.
create or replace function local_dev.fixed_token(phone text, token text)
returns text
language sql
stable
-- GoTrue's role cannot use the extensions schema (pgcrypto's digest).
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select encode(extensions.digest(phone || '123456', 'sha224'), 'hex')
      from local_dev.sent_sms s
      where s.phone = fixed_token.phone
        and encode(extensions.digest(s.phone || s.otp, 'sha224'), 'hex')
          = fixed_token.token
      limit 1
    ),
    token
  );
$$;

create or replace function local_dev.fix_user_tokens()
returns trigger
language plpgsql
as $$
begin
  if coalesce(new.confirmation_token, '') <> '' and new.phone is not null then
    new.confirmation_token :=
      local_dev.fixed_token(new.phone, new.confirmation_token);
  end if;
  if coalesce(new.phone_change_token, '') <> ''
     and coalesce(new.phone_change, '') <> '' then
    new.phone_change_token :=
      local_dev.fixed_token(new.phone_change, new.phone_change_token);
  end if;
  return new;
end;
$$;

create or replace function local_dev.fix_one_time_token()
returns trigger
language plpgsql
as $$
begin
  new.token_hash := local_dev.fixed_token(new.relates_to, new.token_hash);
  return new;
end;
$$;

drop trigger if exists local_dev_fixed_otp on auth.users;
create trigger local_dev_fixed_otp
  before insert or update of confirmation_token, phone_change_token
  on auth.users
  for each row execute function local_dev.fix_user_tokens();

drop trigger if exists local_dev_fixed_otp on auth.one_time_tokens;
create trigger local_dev_fixed_otp
  before insert or update of token_hash
  on auth.one_time_tokens
  for each row execute function local_dev.fix_one_time_token();

-- Only GoTrue calls the hook; nothing here is reachable through the API.
grant usage on schema local_dev to supabase_auth_admin;
grant select, insert, delete on local_dev.sent_sms to supabase_auth_admin;
grant execute on all functions in schema local_dev to supabase_auth_admin;
revoke execute on all functions in schema local_dev
  from public, anon, authenticated;
