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
// unauthenticated caller in their OWN handler, so adding this project's first
// [functions] block cannot have silently widened them. The config value itself
// is verifiable only by deployment or by reading the file.
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
    assertEquals(
      res.status,
      401,
      `${name} must reject an unauthenticated POST at the handler, got ${res.status}: ${body}`,
    );
  }
});
