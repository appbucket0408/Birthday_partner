begin;
select plan(3);

select has_extension('extensions', 'pgtap', 'pgtap is installed');
select has_extension('extensions', 'pgcrypto', 'pgcrypto is installed');
select has_extension('extensions', 'dblink', 'dblink is installed');

select * from finish();
rollback;
