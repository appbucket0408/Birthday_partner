// Thin wrapper. All matching logic is private.resolve_contacts, which is
// covered by 18_resolve_contacts.test.sql. This adds only the HTTP shape.
//
// Raw phone numbers arrive here and are passed straight to Postgres, which
// hashes them with a pepper that never leaves the database. Nothing raw is
// stored or logged.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BATCH = 500;

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

  let phones: unknown;
  try {
    ({ phones } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (!Array.isArray(phones) || phones.some((p) => typeof p !== "string")) {
    return new Response(JSON.stringify({ error: "phones must be string[]" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (phones.length > MAX_BATCH) {
    return new Response(
      JSON.stringify({ error: `at most ${MAX_BATCH} phones per request` }),
      { status: 413, headers: { "content-type": "application/json" } },
    );
  }

  // service_role: private.resolve_contacts is revoked from every client role,
  // and the caller's own identity is not needed — resolution is the same for
  // everyone, and it creates nothing.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Confirm the caller is a real signed-in user before doing any work.
  const caller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  // R2: no .schema("private") — PostgREST exposes only public and
  // graphql_public, so the private function is reached through its
  // service_role-only public wrapper.
  const { data, error } = await admin
    .rpc("rpc_resolve_contacts", { p_phones: phones });

  if (error) {
    console.error("resolve_contacts failed", error.message);
    return new Response(JSON.stringify({ error: "resolution failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ matches: data ?? [] }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
