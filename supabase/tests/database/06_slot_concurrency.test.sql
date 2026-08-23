begin;
select plan(3);

select tests.as_postgres();

create temporary table race_result as select * from tests.race_last_slot();

select is(
  (select blocked from race_result),
  true,
  'the second checkout blocks on the first rather than reading stale capacity'
);

select is(
  (select loser_sqlstate from race_result),
  '23514',
  'the second checkout loses with the slot-full error'
);

-- Exactly one unit was sold.
select is(
  (select s.reserved from public.delivery_slots s
   join public.service_areas a on a.id = s.service_area_id
   where a.name = 'Race Test Area'),
  1,
  'exactly one of the two racing checkouts reserved the slot'
);

select * from finish();
rollback;
