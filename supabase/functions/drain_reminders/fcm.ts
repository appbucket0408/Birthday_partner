// Everything in drain_reminders that has logic worth testing. index.ts stays
// transport and orchestration only.

/// C0 and C1 control characters, PLUS U+2028 LINE SEPARATOR and U+2029
/// PARAGRAPH SEPARATOR. Line breaks are the dangerous ones: they let a
/// display_name forge what looks like a second line of app-authored text.
/// U+2028/U+2029 are not control characters by category, but Android's ICU
/// line breaker treats both as mandatory breaks, so omitting them left the
/// exact attack this function exists to prevent wide open.
const CONTROL = /[\u0000-\u001F\u007F-\u009F\u2028\u2029]/g;

/// Unicode bidirectional controls: the embeddings and overrides
/// (U+202A-U+202E), the isolates (U+2066-U+2069), and the invisible marks
/// LRM, RLM and ALM. All of them reorder rendered text without changing a
/// byte of the surrounding template.
const BIDI = /[\u202A-\u202E\u2066-\u2069\u200E\u200F\u061C]/g;

/// Zero-width and invisible formatting characters, stripped for a different
/// reason than the two above: `trim()` does NOT remove them (none is in
/// category Zs), so a name made entirely of them survived as non-empty and
/// defeated the "Someone" fallback, rendering as "It's 's birthday today."
/// -- the very string the control-character case forbids.
const INVISIBLE = /[\u200B\u200C\u200D\uFEFF\u00AD\u180E]/g;

const MAX_NAME_POINTS = 64;

/// people.display_name is free text the user chooses, and
/// 20260824000005_device_tokens.sql documents the reachable attack: an
/// attacker who obtains a device token reassigns it to their own account,
/// creates a celebrated person whose display_name is arbitrary text with a
/// birthday of today, and the pipeline delivers that text to the victim's
/// device as a trusted notification.
///
/// This narrows the class; it does not close it. A short, plain, printable
/// name can still read as a sentence. Closing that needs a title/body split
/// that never interpolates into app-authored prose -- spec section 10.1.
export function safeName(raw: string): string {
  const stripped = raw
    .replace(CONTROL, "")
    .replace(BIDI, "")
    .replace(INVISIBLE, "")
    .trim();
  // Spread iterates CODE POINTS. `.slice(0, 64)` on the string would work on
  // UTF-16 units and cut an emoji or a Devanagari cluster in half, emitting a
  // lone surrogate.
  const points = [...stripped];
  const clamped = points.length > MAX_NAME_POINTS
    ? points.slice(0, MAX_NAME_POINTS).join("")
    : stripped;
  const final = clamped.trim();
  return final === "" ? "Someone" : final;
}
export function wishBody(authorName: string | null): string {
  return `${safeName(authorName ?? "")} left you a birthday wish.`;
}

export function reminderBody(name: string, offsetDays: number): string {
  const safe = safeName(name);
  if (offsetDays === 0) return `It's ${safe}'s birthday today.`;
  if (offsetDays === 1) return `${safe}'s birthday is tomorrow.`;
  return `${safe}'s birthday is in ${offsetDays} days.`;
}

export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/// Re-mint when less than this remains. A token that expires mid-batch
/// fails every message after the boundary, and those failures consume
/// `attempts` on reminders that were perfectly deliverable.
const EXPIRY_MARGIN_MS = 5 * 60 * 1000;

/// Keyed on the service account's own identity. An unkeyed module-scope
/// cache is correct only while one deployment has exactly one service
/// account; rotate the key and the stale bearer is served for the new one.
const cache = new Map<string, { token: string; expiresAtMs: number }>();

/// Test seam. Module-scope cache survives between Deno.test cases in one
/// process, so without this each test would see the previous one's token.
export function resetTokenCache(): void {
  cache.clear();
}

/// Drops one service account's cached bearer. Called when FCM rejects it,
/// so a key revoked mid-life costs one failed batch rather than the ~55
/// minutes the cache would otherwise keep serving it.
export function invalidateToken(sa: ServiceAccount): void {
  cache.delete(sa.client_email);
}

/// FCM rejecting the CREDENTIAL, as opposed to rejecting the token being
/// sent to. Distinct from isDeadToken: this one must never delete a
/// device_tokens row, because the device is fine and we are not.
export function isRejectedBearer(status: number): boolean {
  return status === 401 || status === 403;
}

/// FCM's 404 means UNREGISTERED: the token is permanently dead, not
/// temporarily unreachable. Retrying it is what makes a revoked token burn
/// `attempts` on every future reminder for that user.
export function isDeadToken(status: number): boolean {
  return status === 404;
}

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  // JSON.parse has already turned the file's literal \n escapes into real
  // newlines, so the PEM arrives correctly formed.
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  // A real ArrayBuffer, not `someUint8Array.buffer`: Deno 2.9's lib types
  // make Uint8Array generic over ArrayBufferLike, which does not satisfy
  // importKey's BufferSource overload.
  const buf = new ArrayBuffer(raw.length);
  const out = new Uint8Array(buf);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return buf;
}

/// Mints (or reuses) an OAuth2 bearer for FCM HTTP v1.
///
/// `now` and `fetchImpl` are injected so the cache boundary and a failed
/// exchange are testable without waiting an hour or reaching Google.
export async function accessToken(
  sa: ServiceAccount,
  now: number,
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  const hit = cache.get(sa.client_email);
  if (hit && hit.expiresAtMs - now > EXPIRY_MARGIN_MS) {
    return hit.token;
  }

  const iat = Math.floor(now / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: SCOPE,
    aud: TOKEN_ENDPOINT,
    iat,
    exp: iat + 3600,
  };
  const enc = new TextEncoder();
  const signingInput = `${base64url(enc.encode(JSON.stringify(header)))}.${
    base64url(enc.encode(JSON.stringify(claims)))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(signingInput),
  );
  const assertion = `${signingInput}.${base64url(new Uint8Array(sig))}`;

  const res = await fetchImpl(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!res.ok) {
    // Throwing rather than returning a falsy token is deliberate: index.ts
    // must abandon the batch, not send `Bearer undefined` for every message
    // and burn `attempts` on reminders that were never attempted.
    throw new Error(`token exchange failed: ${res.status}`);
  }
  const json = await res.json() as { access_token: string; expires_in: number };
  // Written only on success, so a failure is never cached.
  cache.set(sa.client_email, {
    token: json.access_token,
    expiresAtMs: now + json.expires_in * 1000,
  });
  return json.access_token;
}
