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
  let duplicates = 0;

  // An address book routinely holds the same number twice (a duplicate
  // contact, a synced-twice entry). Calling rpc_add_celebration once per
  // occurrence creates no extra edge — it is idempotent via
  // `on conflict do nothing` — but it WOULD report "added: 2" for one real
  // edge. So each distinct phone is sent to Postgres exactly once.
  //
  // The RPC calls are deduped; the RESULTS are not. Every input index gets
  // its own entry, because `results` carries no input index of its own and
  // the obvious client implementation zips it against the picked-contacts
  // list positionally. Returning fewer entries than were sent would silently
  // shift every outcome after the first duplicate onto the wrong contact.
  // Repeat occurrences echo the first one's verdict under status
  // "duplicate", so `added` still counts real edges while
  // `added + skipped + failed + duplicates === contacts.length` holds.
  type Outcome = { person_id: number | null; status: string };
  const firstOutcome = new Map<string, Outcome>();

  for (const c of contacts as Contact[]) {
    const prior = firstOutcome.get(c.phone);
    if (prior !== undefined) {
      results.push({
        phone: c.phone,
        person_id: prior.person_id,
        status: "duplicate",
      });
      duplicates++;
      continue;
    }

    const record = (o: Outcome) => {
      firstOutcome.set(c.phone, o);
      results.push({ phone: c.phone, person_id: o.person_id, status: o.status });
    };

    // Trim once and use the trimmed value for BOTH the bound check and the
    // write, so a padded name cannot slip its whitespace into the database.
    const trimmedName = c.name.trim();
    if (trimmedName.length === 0 || trimmedName.length > MAX_NAME_LENGTH) {
      record({ person_id: null, status: "invalid_name" });
      failed++;
      continue;
    }

    const { data, error } = await admin.rpc("rpc_add_celebration", {
      p_celebrator: userData.user.id,
      p_phone: c.phone,
      p_name: trimmedName,
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
        record({ person_id: null, status: "invalid_phone" });
        failed++;
        continue;
      }

      // 45001: private.add_celebration's self-celebration guard. Importing
      // your own number is the single most likely "failure" in a real
      // import — it's in your own address book — so it gets its own status
      // rather than being indistinguishable from a database outage.
      if (error.code === "45001") {
        record({ person_id: null, status: "self" });
        failed++;
        continue;
      }

      record({ person_id: null, status: "failed" });
      failed++;
      continue;
    }

    // A suppressed number is reported with the same opaque status as any other
    // non-actionable skip, NOT as "suppressed". Returning the labelled status
    // made this endpoint an oracle: it accepts 500 arbitrary numbers per
    // request with no rate limit and no requirement that the caller holds them
    // in an address book, so a labelled response let anyone enumerate who had
    // asked to be forgotten. The aggregate `skipped` count is unchanged, so the
    // count inference accepted in Phase 2b remains -- but the per-phone oracle
    // is gone.
    if (data === null) {
      record({ person_id: null, status: "skipped" });
      skipped++;
      continue;
    }

    record({ person_id: data, status: "added" });
    added++;
  }

  return new Response(
    JSON.stringify({ added, skipped, failed, duplicates, results }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
});
