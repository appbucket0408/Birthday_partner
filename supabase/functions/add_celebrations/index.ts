// The import screen's commit step. Each picked contact mints a person and a
// celebration edge together.
//
// A suppressed number returns null from the RPC and is reported as
// "skipped", not as an error — someone who asked to be removed must not be
// resurrected, and one such contact must not fail an import of five
// hundred.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BATCH = 500;
const MAX_NAME_LENGTH = 128;

type Contact = {
  phone: string;
  name: string;
  birth_month?: number | null;
  birth_day?: number | null;
  birth_year?: number | null;
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return new Response(JSON.stringify({ error: "missing authorization" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  let contacts: unknown;
  try {
    ({ contacts } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // Cheap, O(1) checks first: whether the payload is an array at all, then
  // its size. A 50,000-element body should be rejected by its length, not by
  // walking every element's shape first only to reject it anyway.
  if (!Array.isArray(contacts)) {
    return new Response(
      JSON.stringify({ error: "contacts must be {phone, name}[]" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  if (contacts.length > MAX_BATCH) {
    return new Response(
      JSON.stringify({ error: `at most ${MAX_BATCH} contacts per request` }),
      { status: 413, headers: { "content-type": "application/json" } },
    );
  }

  if (
    contacts.some((c) =>
      !c || typeof c.phone !== "string" || typeof c.name !== "string"
    )
  ) {
    return new Response(
      JSON.stringify({ error: "contacts must be {phone, name}[]" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "function is misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const admin = createClient(url, serviceKey);
  const results: Array<
    { phone: string; person_id: number | null; status: string }
  > = [];
  let added = 0;
  let skipped = 0;
  let failed = 0;

  // Dedupe by phone before the loop. An address book routinely holds the
  // same number twice (a duplicate contact, a synced-twice entry); calling
  // rpc_add_celebration once per occurrence creates no extra edge — it's
  // idempotent via `on conflict do nothing` — but it WOULD double-count
  // "added" in the summary this screen shows the user (two RPC calls, two
  // non-null person ids, "added: 2" for one real edge). Deduping first means
  // one RPC round trip per unique phone, so added/skipped/failed always
  // describe the batch's actual outcomes and results.length is exactly the
  // number of distinct contacts processed — never contacts.length when the
  // request itself contained duplicates, which is deliberate: counting the
  // same phone as a second independent contact is the bug being fixed here.
  const seenPhones = new Set<string>();
  const deduped: Contact[] = [];
  for (const c of contacts as Contact[]) {
    if (seenPhones.has(c.phone)) continue;
    seenPhones.add(c.phone);
    deduped.push(c);
  }

  for (const c of deduped) {
    const trimmedName = c.name.trim();
    if (trimmedName.length === 0 || c.name.length > MAX_NAME_LENGTH) {
      results.push({ phone: c.phone, person_id: null, status: "invalid" });
      failed++;
      continue;
    }

    const { data, error } = await admin.rpc("rpc_add_celebration", {
      p_celebrator: userData.user.id,
      p_phone: c.phone,
      p_name: c.name,
      p_birth_month: c.birth_month ?? null,
      p_birth_day: c.birth_day ?? null,
      p_birth_year: c.birth_year ?? null,
    });

    if (error) {
      // Never log the contact: error.message is safe (it never carries the
      // phone or the name), but error.details WOULD carry display_name for
      // a constraint violation, so only ever log .message, never the error
      // object itself or the contact that produced it.
      console.error("rpc_add_celebration failed", error.message);

      // 22023 (invalid_parameter_value): private.assert_e164 rejected a
      // malformed phone. A permanent, caller-caused condition — report it
      // distinctly from a transient server fault so the app can tell the
      // user to fix the contact rather than retry the whole import.
      if (error.code === "22023") {
        results.push({ phone: c.phone, person_id: null, status: "invalid" });
        failed++;
        continue;
      }

      // P0002: private.add_celebration's self-celebration guard. Importing
      // your own number is the single most likely "failure" in a real
      // import — it's in your own address book — so it gets its own status
      // rather than being indistinguishable from a database outage.
      if (error.code === "P0002") {
        results.push({ phone: c.phone, person_id: null, status: "self" });
        failed++;
        continue;
      }

      results.push({ phone: c.phone, person_id: null, status: "failed" });
      failed++;
      continue;
    }

    if (data === null) {
      results.push({ phone: c.phone, person_id: null, status: "suppressed" });
      skipped++;
      continue;
    }

    results.push({ phone: c.phone, person_id: data, status: "added" });
    added++;
  }

  return new Response(JSON.stringify({ added, skipped, failed, results }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
