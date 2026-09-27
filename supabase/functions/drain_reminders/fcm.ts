// Everything in drain_reminders that has logic worth testing. index.ts stays
// transport and orchestration only.

/// C0 and C1 control characters. Newlines are the dangerous ones: they let a
/// display_name forge what looks like a second line of app-authored text.
const CONTROL = /[\u0000-\u001F\u007F-\u009F]/g;

/// Unicode bidirectional overrides and isolates. These let a name visually
/// reorder the sentence it is interpolated into without changing a byte of
/// the surrounding template.
const BIDI = /[‪-‮⁦-⁩]/g;

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
  const stripped = raw.replace(CONTROL, "").replace(BIDI, "").trim();
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

let cached: { token: string; expiresAtMs: number } | null = null;

/// Test seam. Module-scope cache survives between Deno.test cases in one
/// process, so without this each test would see the previous one's token.
export function resetTokenCache(): void {
  cached = null;
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
  if (cached && cached.expiresAtMs - now > EXPIRY_MARGIN_MS) {
    return cached.token;
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
  // Assigned only on success, so a failure is never cached.
  cached = {
    token: json.access_token,
    expiresAtMs: now + json.expires_in * 1000,
  };
  return cached.token;
}
