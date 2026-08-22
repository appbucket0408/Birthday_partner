begin;
select plan(6);

select has_schema('private', 'private schema exists');
select has_table('private', 'config', 'private.config exists');

-- The pepper must be seeded, or hashing silently returns null.
select isnt(
  (select value from private.config where key = 'phone_pepper'),
  null,
  'phone_pepper is seeded'
);

-- Hashing is deterministic and shaped like sha256 hex.
select matches(
  private.phone_hash('+919876543210'),
  '^[0-9a-f]{64}$',
  'phone_hash returns 64 hex chars'
);

select is(
  private.phone_hash('+919876543210'),
  private.phone_hash('+919876543210'),
  'phone_hash is deterministic'
);

select isnt(
  private.phone_hash('+919876543210'),
  private.phone_hash('+919876543211'),
  'different numbers hash differently'
);

select * from finish();
rollback;
