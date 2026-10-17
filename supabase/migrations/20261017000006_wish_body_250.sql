-- A wish is a short note on someone's wall, not a letter: 250 characters,
-- down from 500. The compose sheet enforces the same number, but the check
-- here is the real limit -- a client that skips the sheet still hits it.
--
-- NOT VALID: wishes already written under the old 500 limit stay as they
-- are. The constraint applies to every insert and update from here on.
alter table public.wishes drop constraint wishes_body_length;
alter table public.wishes
  add constraint wishes_body_length
  check (length(btrim(body)) between 1 and 250) not valid;
