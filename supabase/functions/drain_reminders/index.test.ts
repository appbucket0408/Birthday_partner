// Unit tests. No server required:
//   deno test supabase/functions/drain_reminders/index.test.ts
import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  accessToken,
  invalidateToken,
  isDeadToken,
  isRejectedBearer,
  resetTokenCache,
  safeName,
} from "./fcm.ts";

Deno.test("a plain name passes through untouched", () => {
  assertEquals(safeName("Priya Sharma"), "Priya Sharma");
});

Deno.test("newlines are stripped -- they let a name forge a second line", () => {
  const forged = safeName("Priya\nTap here to verify your account");
  assertEquals(forged.includes("\n"), false);
});

Deno.test("control characters are stripped", () => {
  assertEquals(safeName("Pri\u0000ya\u007F"), "Priya");
});

Deno.test("bidi overrides are stripped", () => {
  const raw = "Priya‮reversed";
  assertEquals(safeName(raw).includes("‮"), false);
});

Deno.test("U+2028 and U+2029 are stripped -- they ARE line breaks", () => {
  // Review finding I2. C0/C1 stripping misses these two entirely, and
  // Android's ICU line breaker treats both as mandatory breaks. A name
  // ending in U+2028 forges exactly the second line of app-authored text
  // that this whole function exists to prevent.
  for (const sep of ["\u2028", "\u2029"]) {
    const forged = safeName(`Asha${sep}Your account was suspended.`);
    assertEquals(forged.includes(sep), false, `U+${sep.codePointAt(0)!.toString(16)}`);
  }
});

Deno.test("the remaining bidi controls are stripped too", () => {
  // Review finding I2. LRM/RLM/ALM are not in U+202A-U+202E or U+2066-U+2069
  // but reorder rendered text just the same.
  for (const c of ["\u200E", "\u200F", "\u061C"]) {
    assertEquals(safeName(`Asha${c} evil`).includes(c), false);
  }
});

Deno.test("zero-width characters cannot defeat the Someone fallback", () => {
  // Review finding I3. trim() does not remove U+200B (it is not Zs), so a
  // name of nothing but zero-width joiners survived as non-empty and
  // rendered as "It's 's birthday today." -- the exact string the
  // control-character test was written to make impossible.
  for (const c of ["\u200B", "\u200C", "\u200D", "\uFEFF"]) {
    assertEquals(safeName(c.repeat(5)), "Someone");
  }
  assertEquals(safeName("\u200B\u0000\u202E"), "Someone");
});

Deno.test("a name of only control characters becomes Someone", () => {
  // Without this, the body reads "It's 's birthday today."
  assertEquals(safeName("\u0000\u0001\u0002"), "Someone");
});

Deno.test("an empty name becomes Someone", () => {
  assertEquals(safeName("   "), "Someone");
});

Deno.test("a long name is clamped to 64 code points", () => {
  const long = "a".repeat(200);
  assertEquals([...safeName(long)].length, 64);
});

Deno.test("clamping never splits an astral character", () => {
  // Review Focus 1. 70 emoji, each ONE code point but TWO UTF-16 units.
  // `.slice(0, 64)` on units would cut the 32nd emoji in half and emit a
  // lone surrogate, which renders as a replacement character.
  const emoji = "\u{1F382}".repeat(70);
  const out = safeName(emoji);
  assertEquals([...out].length, 64);
  assertEquals(out.includes("�"), false);
  // A lone high surrogate would survive a round-trip as a replacement char.
  assertEquals(
    new TextDecoder().decode(new TextEncoder().encode(out)).includes("�"),
    false,
  );
});

Deno.test("the clamp counts code points, not UTF-16 units", () => {
  const short = "\u{1F382}".repeat(10);
  assertEquals(safeName(short), short);
  assertNotEquals(safeName(short).length, 10); // UTF-16 length is 20
});


// A real RSA key is required: WebCrypto will not import a fake one. Generated
// per call, not committed, and never leaves this process.
async function testServiceAccount() {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const b64 = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    b64.match(/.{1,64}/g)!.join("\n")
  }\n-----END PRIVATE KEY-----\n`;
  return {
    project_id: "birthdaypartner-e7b7b",
    client_email: "drain@birthdaypartner-e7b7b.iam.gserviceaccount.com",
    private_key: pem,
  };
}

Deno.test("a minted token is returned and carries the right scope", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let seenBody = "";
  const fakeFetch = ((_url: string, init: RequestInit) => {
    seenBody = String(init.body);
    return Promise.resolve(
      new Response(JSON.stringify({ access_token: "tok-1", expires_in: 3600 })),
    );
  }) as unknown as typeof fetch;

  const tok = await accessToken(sa, Date.now(), fakeFetch);

  assertEquals(tok, "tok-1");

  // The scope is NOT a plain form field -- it lives base64url-encoded inside
  // the JWT assertion's payload, which is the only place Google reads it
  // from. Asserting on the raw body would pass for a request whose assertion
  // requested no scope at all.
  const assertion = new URLSearchParams(seenBody).get("assertion")!;
  const [, payloadB64] = assertion.split(".");
  const payload = JSON.parse(
    atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/")),
  );
  assertEquals(payload.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(payload.aud, "https://oauth2.googleapis.com/token");
  assertEquals(payload.iss, sa.client_email);
  assertEquals(payload.exp - payload.iat, 3600);
});

Deno.test("a cached token is reused rather than re-minted", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(JSON.stringify({ access_token: "tok-1", expires_in: 3600 })),
    );
  }) as unknown as typeof fetch;

  const now = Date.now();
  await accessToken(sa, now, fakeFetch);
  await accessToken(sa, now + 60_000, fakeFetch);

  assertEquals(calls, 1);
});

Deno.test("a token inside the 5-minute margin is re-minted", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ access_token: `tok-${calls}`, expires_in: 3600 }),
      ),
    );
  }) as unknown as typeof fetch;

  const now = Date.now();
  await accessToken(sa, now, fakeFetch);
  // 3600s minus 4 minutes: inside the margin, so it must re-mint rather
  // than hand FCM a token that expires mid-batch.
  const tok = await accessToken(sa, now + (3600 - 240) * 1000, fakeFetch);

  assertEquals(calls, 2);
  assertEquals(tok, "tok-2");
});

Deno.test("a failed exchange throws rather than returning a bad token", async () => {
  // Review Focus 3. If this returned undefined, index.ts would send
  // `Bearer undefined` to FCM for every message in the batch and mark each
  // one failed -- burning `attempts` on reminders that were never attempted.
  resetTokenCache();
  const sa = await testServiceAccount();
  const fakeFetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 }),
    )) as unknown as typeof fetch;

  let threw = false;
  try {
    await accessToken(sa, Date.now(), fakeFetch);
  } catch (_) {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("a failed exchange is not cached", async () => {
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return calls === 1
      ? Promise.resolve(new Response("{}", { status: 500 }))
      : Promise.resolve(
        new Response(JSON.stringify({ access_token: "ok", expires_in: 3600 })),
      );
  }) as unknown as typeof fetch;

  try {
    await accessToken(sa, Date.now(), fakeFetch);
  } catch (_) { /* expected */ }
  const tok = await accessToken(sa, Date.now(), fakeFetch);

  assertEquals(tok, "ok");
  assertEquals(calls, 2);
});

Deno.test("a 404 is a dead token; a 503 is not", () => {
  assertEquals(isDeadToken(404), true);
  assertEquals(isDeadToken(503), false);
  assertEquals(isDeadToken(401), false);
});

Deno.test("the cache is keyed on the service account, not global", async () => {
  // Review finding I7. A module-scope cache with no key is correct only by
  // the accident that one deployment has one service account. Rotate the
  // key (or run a second project) and the stale bearer is served for the
  // other identity.
  resetTokenCache();
  const a = await testServiceAccount();
  const b = { ...(await testServiceAccount()), client_email: "other@x.iam" };
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ access_token: `tok-${calls}`, expires_in: 3600 }),
      ),
    );
  }) as unknown as typeof fetch;

  const now = Date.now();
  assertEquals(await accessToken(a, now, fakeFetch), "tok-1");
  assertEquals(await accessToken(b, now, fakeFetch), "tok-2");
  // And the first identity still gets its own cached token, not b's.
  assertEquals(await accessToken(a, now, fakeFetch), "tok-1");
  assertEquals(calls, 2);
});

Deno.test("a rejected bearer can be invalidated and re-minted", async () => {
  // Review finding I7. Without this, a key revoked mid-life means every
  // message in every drain 401s for up to ~55 minutes while the cache keeps
  // handing out the same dead bearer.
  resetTokenCache();
  const sa = await testServiceAccount();
  let calls = 0;
  const fakeFetch = (() => {
    calls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ access_token: `tok-${calls}`, expires_in: 3600 }),
      ),
    );
  }) as unknown as typeof fetch;

  const now = Date.now();
  assertEquals(await accessToken(sa, now, fakeFetch), "tok-1");
  invalidateToken(sa);
  assertEquals(await accessToken(sa, now, fakeFetch), "tok-2");
  assertEquals(calls, 2);
});

Deno.test("a 401 or 403 from FCM means the bearer is dead", () => {
  assertEquals(isRejectedBearer(401), true);
  assertEquals(isRejectedBearer(403), true);
  assertEquals(isRejectedBearer(404), false);
  assertEquals(isRejectedBearer(503), false);
});
