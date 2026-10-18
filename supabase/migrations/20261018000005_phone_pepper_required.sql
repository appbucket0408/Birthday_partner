-- The phone-hash pepper fails closed.
--
-- 20260822000002 seeded private.config.phone_pepper with a placeholder,
-- 'dev-pepper-replace-in-production', and left replacing it to a runbook
-- step. That placeholder is public in this repository, and every phone
-- number is stored only as an HMAC keyed by it: a project deployed without
-- the step hashes its whole contact graph with a key anyone can read, and
-- nothing anywhere says so. Once real numbers are hashed it cannot be fixed
-- either -- changing the pepper orphans every stored hash.
--
-- So the placeholder is removed, and hashing refuses to run without a real
-- value. A fresh project now fails at its FIRST sign-up with a message naming
-- the step, instead of quietly running on a public key. Local development
-- and CI get their own value from supabase/seed.sql, which `db push` never
-- sends anywhere.

do $$
begin
  if exists (
    select 1 from private.config
    where key = 'phone_pepper'
      and value = 'dev-pepper-replace-in-production'
  ) then
    if not exists (select 1 from public.people)
       and not exists (select 1 from private.suppressions) then
      -- Nothing has been hashed with it yet, so removing it orphans nothing.
      delete from private.config
      where key = 'phone_pepper'
        and value = 'dev-pepper-replace-in-production';
    else
      -- Hashes already exist under the placeholder. Deleting it now would
      -- orphan every one of them, which is worse than the leak, so it stays
      -- -- loudly. Re-keying means re-hashing every stored phone number from
      -- its source, which this database does not keep.
      raise warning 'phone_pepper is still the public placeholder, and % people and % suppressions are hashed with it. It was left in place: removing it would orphan them. Plan a deliberate re-key; see docs/db.md.',
        (select count(*) from public.people),
        (select count(*) from private.suppressions);
    end if;
  end if;
end;
$$;

-- Same signature, volatility and grants as before (owner-only; revoked from
-- public/anon/authenticated in 20260822000002, which `create or replace`
-- preserves). Only the missing-pepper case changes: it used to return NULL --
-- hmac() with a null key -- which surfaced much later as an unexplained
-- not-null violation on people.phone_e164_hash.
create or replace function private.phone_hash(p_phone text)
returns text
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_pepper text;
begin
  select value into v_pepper from private.config where key = 'phone_pepper';
  if v_pepper is null or v_pepper = '' then
    raise exception 'phone_pepper is not configured'
      using hint = 'Set private.config.phone_pepper to a long random secret before anyone signs up. See docs/superpowers/execution/2026-10-18-push-deploy-runbook.md, step 3.';
  end if;
  return encode(extensions.hmac(p_phone, v_pepper, 'sha256'), 'hex');
end;
$$;
