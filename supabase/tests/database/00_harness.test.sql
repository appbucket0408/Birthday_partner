begin;
select plan(2);

select has_extension('extensions', 'pgtap', 'pgtap is installed');
select has_extension('extensions', 'pgcrypto', 'pgcrypto is installed');

select * from finish();
rollback;
