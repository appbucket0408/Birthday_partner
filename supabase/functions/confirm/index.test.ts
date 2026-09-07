// Integration test. Requires the local stack:
//   supabase start
//   supabase functions serve --no-verify-jwt
//
// Run with:
//   deno test --allow-net --allow-env supabase/functions/confirm/index.test.ts
//
// NOTE ON WHAT THIS FILE CAN AND CANNOT PROVE: the harness serves with
// --no-verify-jwt, so the gateway is bypassed and config.toml's
// [functions.confirm] verify_jwt = false is NOT exercised here. What the guard
// test below proves is that the five pre-existing functions each refuse an
// unauthenticated caller in their OWN handler (defence in depth), so adding
// this project's first [functions] block cannot have silently widened them
// at the handler level. The GATEWAY-level half of that claim -- that Kong
// itself still blocks those five and lets `confirm` through -- is not
// covered by this file at all; it requires a server started WITHOUT
// --no-verify-jwt and is covered separately by
// supabase/functions/test-gateway.sh, which cannot run against the same
// server process as this suite.
import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
// Task 3's fixture needs a gift in `awaiting_confirm`. The status machine's
// only transition INTO that state is from 'paid' (20260822000007_gifts.sql:79),
// and payments are M3 Phase 2, blocked on a provider account -- so there is no
// client-reachable (HTTP) way to build it. The brief offered a choice between
// a service_role-only SQL RPC (a new migration) and seeding directly over
// Postgres; direct seeding was the ruling: a test-only function in `public`
// stays visible to PostgREST forever and needs its own revoke discipline,
// while add_celebrations/index.test.ts:20-22 already sets the precedent of
// seeding over SUPABASE_DB_URL for exactly this shape of gap (there, a
// suppression row no Edge Function can create). Same import, same DB_URL
// fallback, same pattern.
import { Client as PgClient } from "jsr:@db/postgres@0.19.5";

const URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const FN = `${URL}/functions/v1/confirm`;
const DB_URL = Deno.env.get("SUPABASE_DB_URL") ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const GUARDED = [
  "claim_profile",
  "delete_account",
  "drain_reminders",
  "resolve_contacts",
  "add_celebrations",
];

Deno.test("the five pre-existing functions still refuse an unauthenticated caller", async () => {
  for (const name of GUARDED) {
    const res = await fetch(`${URL}/functions/v1/${name}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    const body = await res.text();
    // Four of these five guard on `Authorization` (a Supabase session).
    // drain_reminders is the exception: it guards on a shared secret
    // (`x-drain-secret`), not a session -- see drain_reminders/index.ts:26-32.
    // Sending neither header still exercises its guard (no secret present,
    // so it never matches), so 401 is still the right expectation here; the
    // message is phrased as "caller", not "session" or "token", so it stays
    // accurate for drain_reminders too rather than implying all five share
    // one mechanism.
    assertEquals(
      res.status,
      401,
      `${name} must refuse this unauthenticated caller at its own handler, got ${res.status}: ${body}`,
    );
  }
});

// ------------------------------------------------------------------------
// Task 3: GET /confirm
//
// Fixtures below build the whole chain (sender, recipient person,
// celebration edge, service area, product, slot) directly over Postgres, as
// `postgres` (superuser), which bypasses RLS and grants entirely -- the same
// posture add_celebrations/index.test.ts:20-22 uses for its suppression row.
// A fixed identifier prefix names every row this file owns, and
// resetFixtureRows deletes them BY THOSE EXACT IDENTIFIERS (never a wildcard
// scan) before every build, so repeated runs never accumulate duplicates.

const FIXTURE_HANDLE = "confirmfixture_sender";
const FIXTURE_EMAIL = `${FIXTURE_HANDLE}@example.test`;
const FIXTURE_SENDER_NAME = "Confirmfixture Sender";
const FIXTURE_RECIPIENT_NAME = "Confirmfixture Recipient";
// A range no other test file uses (add_celebrations owns +919999xxxxxx).
const FIXTURE_RECIPIENT_PHONE = "+919888000001";
const FIXTURE_AREA_NAME = "Confirmville";
const FIXTURE_PRODUCT_NAME = "Confirmfixture Cake";
const FIXTURE_AMOUNT_MINOR = 84900;
const FIXTURE_MESSAGE = "A birthday message for testing.";
// Fix round 1, item 2: display_name is chosen by the sender and rendered to
// the recipient on an unauthenticated page -- the only property of this page
// with an attacker. Same literal used for both the sender's display_name and
// the gift message, since both reach HTML through separate esc() calls.
const HOSTILE_TEXT = `Hostile <script>alert(1)</script>"'&`;

function futureDateString(daysFromNow: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + daysFromNow);
  return d.toISOString().slice(0, 10);
}

async function scalar<T>(
  pg: PgClient,
  sql: string,
  params: unknown[] = [],
): Promise<T> {
  const result = await pg.queryArray<[T]>(sql, params);
  return result.rows[0][0];
}

// Deletes every row this file's fixtures ever create, by exact fixed
// identifier. Order matters: `gifts` holds `on delete restrict` references
// to profiles, products and service_areas (20260822000007_gifts.sql), so
// gifts must go first. gift_events cascades from gifts; celebrations
// cascades from both profiles and people; profiles cascades from auth.users;
// products and delivery_slots cascade from service_areas.
async function resetFixtureRows(pg: PgClient): Promise<void> {
  await pg.queryArray(
    `delete from public.gifts
     where sender_profile_id in (select id from public.profiles where handle = $1)
        or product_id in (select id from public.products where name = $2)`,
    [FIXTURE_HANDLE, FIXTURE_PRODUCT_NAME],
  );
  await pg.queryArray(
    `delete from public.people where display_name = $1`,
    [FIXTURE_RECIPIENT_NAME],
  );
  await pg.queryArray(`delete from auth.users where email = $1`, [
    FIXTURE_EMAIL,
  ]);
  await pg.queryArray(
    `delete from public.service_areas where name = $1`,
    [FIXTURE_AREA_NAME],
  );
}

// Sender + profiles, recipient person, celebration edge, service area,
// product and a slot whose slot_date equals the given occasion date. Task 5
// will add a server-side constraint requiring exactly that match; building
// it correctly now avoids rewriting this fixture then.
async function buildFixtureChain(
  pg: PgClient,
  occasionDate: string,
  senderName: string = FIXTURE_SENDER_NAME,
): Promise<
  { senderId: string; personId: string; productId: string; slotId: string }
> {
  // Mirrors seed.sql's tests.create_user: insert auth.users directly: the
  // on_auth_user_created trigger creates the profiles row.
  // Every one of GoTrue's *_token / *_change columns must be '' rather than
  // its column default of NULL. Left NULL (as seed.sql's own tests.create_user
  // does -- harmless there only because pgTAP wraps it in a rolled-back
  // transaction), the row is committed for real here, and GoTrue's admin
  // listUsers() does `sql.Scan` into a Go string for every one of these
  // columns across the WHOLE table: one NULL anywhere breaks listUsers() for
  // every caller, not just reads of this row. Reproduced and fixed during
  // this task -- see the report for the exact failure this caused in
  // add_celebrations/index.test.ts (an unrelated file) once this row was left
  // committed with them NULL.
  const senderId = await scalar<string>(
    pg,
    `insert into auth.users (
       id, instance_id, aud, role, email, encrypted_password,
       email_confirmed_at, created_at, updated_at,
       confirmation_token, recovery_token, email_change_token_new,
       email_change, phone_change, phone_change_token,
       email_change_token_current, reauthentication_token
     ) values (
       gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', $1, '', now(), now(), now(),
       '', '', '', '', '', '', '', ''
     ) returning id::text`,
    [FIXTURE_EMAIL],
  );
  await pg.queryArray(
    `update public.profiles set handle = $1, display_name = $2
     where id = $3::uuid`,
    [FIXTURE_HANDLE, senderName, senderId],
  );

  const personId = await scalar<string>(
    pg,
    `insert into public.people (phone_e164_hash, display_name)
     values (private.phone_hash($1), $2)
     returning id::text`,
    [FIXTURE_RECIPIENT_PHONE, FIXTURE_RECIPIENT_NAME],
  );

  await pg.queryArray(
    `insert into public.celebrations (celebrator_profile_id, person_id, source)
     values ($1::uuid, $2::bigint, 'manual')`,
    [senderId, personId],
  );

  const areaId = await scalar<string>(
    pg,
    `insert into public.service_areas (name) values ($1) returning id::text`,
    [FIXTURE_AREA_NAME],
  );

  const productId = await scalar<string>(
    pg,
    `insert into public.products (service_area_id, name, price_minor)
     values ($1::bigint, $2, $3)
     returning id::text`,
    [areaId, FIXTURE_PRODUCT_NAME, FIXTURE_AMOUNT_MINOR],
  );

  const slotId = await scalar<string>(
    pg,
    `insert into public.delivery_slots
       (service_area_id, slot_date, window_start, window_end, capacity)
     values ($1::bigint, $2::date, time '10:00', time '13:00', 5)
     returning id::text`,
    [areaId, occasionDate],
  );

  return { senderId, personId, productId, slotId };
}

async function createGift(
  pg: PgClient,
  chain: { senderId: string; personId: string; productId: string; slotId: string },
  occasionDate: string,
  message: string = FIXTURE_MESSAGE,
): Promise<{ id: string; token: string }> {
  const result = await pg.queryArray<[string, string]>(
    `select g.id::text, g.confirm_token::text
     from private.create_gift(
       $1::uuid, $2::bigint, $3::bigint, $4::bigint, $5::date, $6::text
     ) as g`,
    [
      chain.senderId,
      chain.personId,
      chain.productId,
      chain.slotId,
      occasionDate,
      message,
    ],
  );
  const [id, token] = result.rows[0];
  return { id, token };
}

async function transition(
  pg: PgClient,
  giftId: string,
  to: string,
): Promise<void> {
  await pg.queryArray(
    `select t.id from private.gift_transition($1::bigint, $2::public.gift_status) as t`,
    [giftId, to],
  );
}

// A gift in awaiting_confirm, built with service_role-equivalent (postgres)
// access. See the file-level comment above for why this cannot be built any
// other way in this phase.
async function awaitingConfirmGift(pg: PgClient): Promise<{
  token: string;
  senderName: string;
  productName: string;
  city: string;
}> {
  await resetFixtureRows(pg);
  const occasionDate = futureDateString(7);
  const chain = await buildFixtureChain(pg, occasionDate);
  const { id, token } = await createGift(pg, chain, occasionDate);
  await transition(pg, id, "paid");
  await transition(pg, id, "awaiting_confirm");

  return {
    token,
    senderName: FIXTURE_SENDER_NAME,
    productName: FIXTURE_PRODUCT_NAME,
    city: FIXTURE_AREA_NAME,
  };
}

// A real, well-formed token whose gift is still 'draft' -- confirm_token is
// populated at CREATION (default gen_random_uuid()), not at payment, so this
// token exists long before the gift is confirmable (spec §4.3).
async function draftGift(pg: PgClient): Promise<{ token: string }> {
  await resetFixtureRows(pg);
  const occasionDate = futureDateString(7);
  const chain = await buildFixtureChain(pg, occasionDate);
  const { token } = await createGift(pg, chain, occasionDate);
  return { token };
}

// Fix round 1, item 1: a gift actually walked through to `confirmed`, so
// `confirm_token_used_at` is genuinely set the same way a real recipient
// submission would set it -- not faked by writing the column directly.
// private.confirm_gift is revoked from public/anon/authenticated
// (20260822000008_gift_lifecycle.sql:247-248), but that revoke does not bind
// `postgres`: this connection is the superuser, exactly like every other
// fixture call in this file (private.create_gift, private.gift_transition
// are equally revoked from those three roles and equally callable here).
// The city passed is the fixture's own service area, so this reaches
// confirm_gift's success path (in-area) rather than its refund path.
async function confirmedGift(pg: PgClient): Promise<{ token: string }> {
  await resetFixtureRows(pg);
  const occasionDate = futureDateString(7);
  const chain = await buildFixtureChain(pg, occasionDate);
  const { id, token } = await createGift(pg, chain, occasionDate);
  await transition(pg, id, "paid");
  await transition(pg, id, "awaiting_confirm");

  await pg.queryArray(
    `select c.id
     from private.confirm_gift(
       $1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text
     ) as c`,
    [token, "1 Test Lane", "", FIXTURE_AREA_NAME, "560001", "Home"],
  );

  return { token };
}

// Fix round 1, item 2: a sender's display_name (and the gift message) reach
// HTML unauthenticated. This gift's sender name and message are both the
// same hostile literal, so a single fixture exercises both esc() call sites
// renderForm has.
async function hostileAwaitingConfirmGift(pg: PgClient): Promise<{ token: string }> {
  await resetFixtureRows(pg);
  const occasionDate = futureDateString(7);
  const chain = await buildFixtureChain(pg, occasionDate, HOSTILE_TEXT);
  const { id, token } = await createGift(pg, chain, occasionDate, HOSTILE_TEXT);
  await transition(pg, id, "paid");
  await transition(pg, id, "awaiting_confirm");
  return { token };
}

Deno.test("GET with a valid token renders the address form, and no price", async () => {
  const pg = new PgClient(DB_URL);
  await pg.connect();
  let gift;
  try {
    gift = await awaitingConfirmGift(pg);
  } finally {
    await pg.end();
  }

  const res = await fetch(`${FN}?token=${gift.token}`);
  const html = await res.text();

  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type")?.includes("text/html"), true);
  // The five inputs the recipient must fill.
  for (const field of ["line1", "line2", "city", "pincode", "label"]) {
    assertEquals(
      html.includes(`name="${field}"`),
      true,
      `form is missing input name="${field}"`,
    );
  }
  // What it may show.
  assertEquals(html.includes(gift.senderName), true, "sender name missing");
  assertEquals(html.includes(gift.productName), true, "product name missing");
  // What it must NEVER show (spec §4.6). The seeded amount is 84900 paise.
  assertEquals(html.includes("84900"), false, "the page leaked amount_minor");
  assertEquals(html.includes("849"), false, "the page leaked a rupee price");
});

Deno.test("GET with an unknown token and GET for a non-awaiting gift are byte-identical", async () => {
  const pg = new PgClient(DB_URL);
  await pg.connect();
  let draft;
  try {
    draft = await draftGift(pg);
  } finally {
    await pg.end();
  }

  const unknown = await fetch(
    `${FN}?token=00000000-0000-4000-8000-000000000000`,
  );
  const wrongStatus = await fetch(`${FN}?token=${draft.token}`);

  const unknownBody = await unknown.text();
  const wrongBody = await wrongStatus.text();

  assertEquals(unknown.status, 404);
  assertEquals(wrongStatus.status, 404);
  // The point of the test: separating these would confirm to a prober that a
  // token is real but its gift unpaid -- an oracle no legitimate recipient
  // needs, because links are only sent after payment (spec §4.3).
  assertEquals(
    wrongBody,
    unknownBody,
    "a real-but-unconfirmable token must be indistinguishable from an unknown one",
  );
});

Deno.test("GET with a malformed or missing token is the same neutral 404", async () => {
  const missing = await fetch(FN);
  const malformed = await fetch(`${FN}?token=not-a-uuid`);
  assertEquals(missing.status, 404);
  assertEquals(malformed.status, 404);
  assertEquals(await malformed.text(), await missing.text());
});

// Fix round 1, item 1: the third of the three GET outcomes the brief
// declares (form / already confirmed / neutral 404) had no test at all.
Deno.test("GET after confirmation shows the already-confirmed notice, not the neutral 404", async () => {
  const pg = new PgClient(DB_URL);
  await pg.connect();
  let gift;
  try {
    gift = await confirmedGift(pg);
  } finally {
    await pg.end();
  }

  const res = await fetch(`${FN}?token=${gift.token}`);
  const html = await res.text();

  const neutral = await (
    await fetch(`${FN}?token=00000000-0000-4000-8000-000000000000`)
  ).text();

  assertEquals(res.status, 200, `expected 200, got ${res.status}: ${html}`);
  assertEquals(
    html.includes("This gift is already confirmed."),
    true,
    "already-confirmed body is missing its copy",
  );
  // The point of this test: an already-confirmed token and an unknown one
  // are ADJACENT branches in the handler, and only this assertion proves
  // they resolve differently -- status 200 alone would also pass if the
  // handler fell through to some other 200 page.
  assertNotEquals(
    html,
    neutral,
    "the already-confirmed page must not be the neutral 404 -- that distinction is the whole point of the branch",
  );
});

// Fix round 1, item 2: display_name is sender-chosen and rendered to the
// recipient on an unauthenticated page -- the only property of this page
// with an attacker. Checks BOTH that the raw tag is absent AND that the
// escaped form is present, so this fails if esc() is removed (the raw tag
// leaks) and would equally fail if the hostile value were silently dropped
// instead of escaped (the escaped form would then be absent too).
Deno.test("GET escapes a hostile sender display_name and gift message", async () => {
  const pg = new PgClient(DB_URL);
  await pg.connect();
  let gift;
  try {
    gift = await hostileAwaitingConfirmGift(pg);
  } finally {
    await pg.end();
  }

  const res = await fetch(`${FN}?token=${gift.token}`);
  const html = await res.text();

  assertEquals(res.status, 200);
  assertEquals(
    html.includes("<script>alert(1)</script>"),
    false,
    "a raw <script> tag reached the page -- an unescaped interpolation",
  );
  assertEquals(
    html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"),
    true,
    "the escaped form of the hostile sender name/message is missing",
  );
});
