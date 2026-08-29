// Integration test. Requires the local stack:
//   supabase start
//   supabase functions serve --no-verify-jwt
//
// --no-verify-jwt is required, not optional: with the platform's default
// gateway-level JWT check on, an unauthenticated request never reaches the
// handler at all -- Kong intercepts it and returns its own
// {"msg": "Error: ..."} body instead of the function's
// {"error": "missing authorization"}, which fails the first test below for a
// reason that has nothing to do with the function under test.
//
// Run with:
//   deno test --allow-net --allow-env supabase/functions/add_celebrations/index.test.ts
//
// It talks HTTP to the served function rather than importing the handler,
// because the contract Phase 2b's import screen depends on is the HTTP one:
// the status vocabulary, the count invariant, and the positional results array.
//
// One test seeds a suppression directly over Postgres (SUPABASE_DB_URL)
// rather than through the API: private.suppress_person has no Edge Function
// caller anywhere in this project, so there is no HTTP-reachable way to
// create the row that exercises the `suppressed` status.
import { assertEquals } from "jsr:@std/assert@1";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { Client as PgClient } from "jsr:@db/postgres@0.19.5";

const URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DB_URL = Deno.env.get("SUPABASE_DB_URL") ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const FN = `${URL}/functions/v1/add_celebrations`;

const TEST_PHONES = ["+919999000001", "+919999000002", "+919999000003"];
let cursor = 0;

// deno-lint-ignore no-explicit-any
async function deleteUserByPhone(admin: any, phone: string): Promise<void> {
  const { data } = await admin.auth.admin.listUsers();
  const existing = data?.users?.find((u: { phone?: string }) =>
    u.phone === phone.replace("+", "")
  );
  if (existing) await admin.auth.admin.deleteUser(existing.id);
}

// A fresh signed-in user per test, so repeated runs never collide on the
// unique celebration edge and read as "duplicate" when they mean "added".
async function signedInUser(): Promise<{ jwt: string; phone: string }> {
  // Only the three numbers in [auth.sms.test_otp] receive code 123456, so the
  // pool is fixed rather than random. Cleanup is lazy, not eager: nothing
  // deletes a phone's user when its test finishes, so deleteUserByPhone runs
  // here, at the START of the next signedInUser() call for that same slot,
  // before the number is reused.
  const admin = createClient(URL, SERVICE);
  const phone = TEST_PHONES[cursor++ % TEST_PHONES.length];
  await deleteUserByPhone(admin, phone);
  const { error } = await admin.auth.admin.createUser({
    phone,
    phone_confirm: true,
  });
  if (error) throw error;

  // The created user is signed in through the test OTP map, which is the same
  // path the app takes. generateLink is email-only and does not apply here.
  const anon = createClient(URL, ANON);
  const { error: otpErr } = await anon.auth.signInWithOtp({ phone });
  if (otpErr) throw otpErr;
  const { data: verified, error: vErr } = await anon.auth.verifyOtp({
    phone,
    token: "123456",
    type: "sms",
  });
  if (vErr) throw vErr;
  const jwt = verified.session!.access_token;

  // Claiming is REQUIRED for the `self` status to be reachable.
  // private.add_celebration's self-guard fires only when the person row is
  // already claimed by the celebrator, or carries their phone hash. A user who
  // has signed in but not claimed gets `added` for their own number, and
  // claim_person deletes the self-edge retroactively instead.
  const claim = await fetch(`${URL}/functions/v1/claim_profile`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${jwt}` },
  });
  if (!claim.ok) throw new Error(`claim_profile failed: ${claim.status}`);

  return { jwt, phone };
}

function post(body: unknown, jwt?: string) {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (jwt) headers["Authorization"] = `Bearer ${jwt}`;
  return fetch(FN, { method: "POST", headers, body: JSON.stringify(body) });
}

Deno.test("rejects a request with no Authorization header", async () => {
  const res = await post({ contacts: [] });
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "missing authorization");
});

Deno.test("rejects more than MAX_BATCH contacts with 413", async () => {
  const { jwt } = await signedInUser();
  const contacts = Array.from({ length: 501 }, (_, i) => ({
    phone: `+91999${String(i).padStart(7, "0")}`,
    name: "Too Many",
  }));
  const res = await post({ contacts }, jwt);
  assertEquals(res.status, 413);
  assertEquals((await res.json()).error, "at most 500 contacts per request");
});

Deno.test("the count invariant holds across every status", async () => {
  const { jwt, phone } = await signedInUser();
  const contacts = [
    { phone: "+919999222201", name: "Added One" },
    { phone: "+919999222201", name: "Added One Again" }, // duplicate
    { phone: "not-a-number", name: "Bad Phone" },        // invalid_phone
    { phone: "+919999222202", name: "   " },             // invalid_name
    { phone: "+919999222203", name: "x".repeat(129) },   // invalid_name
    { phone, name: "Me" },                                // self
  ];
  const res = await post({ contacts }, jwt);
  assertEquals(res.status, 200);
  const body = await res.json();

  assertEquals(
    body.added + body.skipped + body.failed + body.duplicates,
    contacts.length,
    "added + skipped + failed + duplicates must equal contacts.length",
  );
  assertEquals(
    body.results.length,
    contacts.length,
    "one result per input index, so the client can zip positionally",
  );
  assertEquals(body.results.map((r: { status: string }) => r.status), [
    "added",
    "duplicate",
    "invalid_phone",
    "invalid_name",
    "invalid_name",
    "self",
  ]);
});

Deno.test("a repeat occurrence echoes the first verdict, not a second edge", async () => {
  const { jwt } = await signedInUser();
  const contacts = [
    { phone: "+919999222301", name: "Twice" },
    { phone: "+919999222301", name: "Twice" },
  ];
  const body = await (await post({ contacts }, jwt)).json();
  assertEquals(body.added, 1, "one real edge");
  assertEquals(body.duplicates, 1);
  assertEquals(
    body.results[0].person_id,
    body.results[1].person_id,
    "the duplicate carries the first occurrence's person_id",
  );
});

Deno.test("a birthday supplied with the contact is stored", async () => {
  const { jwt } = await signedInUser();
  const contacts = [{
    phone: "+919999222401",
    name: "Has Birthday",
    birth_month: 4,
    birth_day: 15,
    birth_year: null,
  }];
  const body = await (await post({ contacts }, jwt)).json();
  assertEquals(body.added, 1);

  const admin = createClient(URL, SERVICE);
  const { data } = await admin
    .from("people")
    .select("birth_month, birth_day")
    .eq("id", body.results[0].person_id)
    .single();
  assertEquals(data, { birth_month: 4, birth_day: 15 });
});

Deno.test("a suppressed number is reported as an opaque skip, never labelled", async () => {
  // private.suppress_person has no Edge Function caller anywhere in this
  // project (grepped all five), so the only way to create a suppression for
  // this test is a direct Postgres connection, seeding
  // private.suppressions the same way the RPC would. private.phone_hash is
  // called server-side so the pepper is applied by Postgres, never computed
  // here.
  //
  // +919999555xxx is used only by this test, distinct from the
  // +919999222xxx range (count invariant / repeat / birthday tests above)
  // and the +91999<7 digits> range the MAX_BATCH test generates.
  const phone = "+919999555001";

  const pg = new PgClient(DB_URL);
  await pg.connect();
  try {
    await pg.queryArray(
      `insert into private.suppressions (phone_e164_hash)
       values (private.phone_hash($1))
       on conflict do nothing`,
      [phone],
    );
  } finally {
    await pg.end();
  }

  const { jwt } = await signedInUser();
  const body = await (await post(
    { contacts: [{ phone, name: "Suppressed Person" }] },
    jwt,
  )).json();

  // `skipped` is otherwise unobservable from the HTTP contract -- nothing
  // else in this file increments it -- so asserting the counter, not just
  // the per-result status string, is the only way to pin that a regression
  // from `status: "skipped"` to `status: "failed"` (which the import
  // screen would render as naming the contact, the exact leak the spec
  // forbids) shows up as a test failure.
  assertEquals(body.skipped, 1);
  assertEquals(body.results[0].status, "skipped");
  assertEquals(body.results[0].person_id, null);

  // The oracle guard: no response field anywhere may carry the word
  // "suppressed", or the endpoint is enumerable again.
  assertEquals(JSON.stringify(body).includes("suppressed"), false);
});
