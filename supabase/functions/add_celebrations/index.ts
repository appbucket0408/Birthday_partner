// The import screen's commit step. Each picked contact mints a person and a
// celebration edge together.
//
// A suppressed number returns null from the RPC and is reported as "skipped",
// not as an error — someone who asked to be removed must not be resurrected,
// and one such contact must not fail an import of five hundred.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BATCH = 500;

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

  if (
    !Array.isArray(contacts) ||
    contacts.some((c) =>
      !c || typeof c.phone !== "string" || typeof c.name !== "string"
    )
  ) {
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

  for (const c of contacts as Contact[]) {
    const { data, error } = await admin.rpc("rpc_add_celebration", {
      p_celebrator: userData.user.id,
      p_phone: c.phone,
      p_name: c.name,
      p_birth_month: c.birth_month ?? null,
      p_birth_day: c.birth_day ?? null,
      p_birth_year: c.birth_year ?? null,
    });

    if (error) {
      // Never log the contact — it carries a phone number and a name.
      console.error("rpc_add_celebration failed", error.message);
      results.push({ phone: c.phone, person_id: null, status: "failed" });
      skipped++;
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

  return new Response(JSON.stringify({ added, skipped, results }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
