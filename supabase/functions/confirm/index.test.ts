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

const URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const FN = `${URL}/functions/v1/confirm`;

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
