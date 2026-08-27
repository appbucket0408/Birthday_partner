-- "delete my account" has to mean the app stops knowing your birthday, not
-- just that your login stops working.
--
-- private.claim_person's upsert OVERWRITES the surviving people row with the
-- PROFILE's own display_name and birth_month/day/year (COALESCEing away
-- whatever an address-book import had contributed), and
-- private.sync_person_from_profile keeps them in lockstep on every profile
-- edit thereafter. So after a claim, the people row Task 7 deliberately
-- leaves behind is NOT "whatever a bystander called them" -- it is the
-- user's own self-entered name and real birth date, sitting in a row that
-- is now unclaimed but still fully live.
--
-- private.enqueue_reminders (20260824000006) gates only on
-- `p.birth_month is not null`; it never checks whether the person is
-- claimed. Left alone, a user who asked to be erased keeps generating
-- birthday reminders to strangers, under their real name and real date,
-- forever.
--
-- The fix belongs at the database layer, for the same reason
-- private.assert_e164 does: it must hold for every deletion path (this
-- Edge Function today, any future admin tooling, a support script), not
-- just for whatever the Edge Function happens to call.
--
-- What must survive (this is the entire point of Task 7): the people row
-- itself, its id, its phone_e164_hash, and every OTHER profile's
-- celebration edge into it -- other people's lists must not break.
--
-- What must NOT survive: the deleted user's own contributed data. That is
-- their self-entered name and birthday (scrubbed below), their own
-- delivery address (public.addresses.owner_person_id -> people -- zero
-- rows today since addresses is M3, but unambiguously the user's own data,
-- contributed by nobody else), and any reminder already queued under their
-- real name (nulling birth_month also stops enqueue_reminders from ever
-- queueing a NEW one for this person).
create or replace function private.scrub_person_on_profile_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person_id bigint;
begin
  select p.id into v_person_id from public.people p where p.profile_id = old.id;

  -- A profile that never claimed a number (deleted mid-onboarding, or an
  -- email/anonymous session) has no people row to scrub.
  if v_person_id is null then
    return old;
  end if;

  -- Already-queued reminders would otherwise still drain and fire -- under
  -- the placeholder name set below rather than a leaked real one, since
  -- private.next_reminder_batch reads public.people.display_name live
  -- rather than a copy, but a "Deleted user's birthday is today" push is
  -- still a notification about nobody's birthday and must not go out.
  delete from private.notification_outbox where subject_person_id = v_person_id;

  delete from public.addresses where owner_person_id = v_person_id;

  update public.people
  set display_name = 'Deleted user',
      birth_month = null,
      birth_day = null,
      birth_year = null
  where id = v_person_id;

  return old;
end;
$$;

revoke execute on function private.scrub_person_on_profile_delete()
  from public, anon, authenticated;

-- BEFORE DELETE, not AFTER: every FK's ON DELETE action off public.profiles
-- (including people.profile_id's SET NULL) is enforced by Postgres's own
-- referential-integrity triggers, and those are always fired AFTER ROW. A
-- BEFORE ROW trigger therefore runs strictly before any of that machinery,
-- so `people.profile_id` still equals OLD.id when this looks it up -- this
-- ordering was verified against the running database rather than assumed
-- (see the Task 7 review report).
create trigger profiles_scrub_person_before_delete
  before delete on public.profiles
  for each row execute function private.scrub_person_on_profile_delete();
