-- pgtap powers the test suite; dblink is used only by the slot concurrency test.
-- Both live in the extensions schema so they are never exposed through the API.
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
create extension if not exists pgcrypto with schema extensions;
