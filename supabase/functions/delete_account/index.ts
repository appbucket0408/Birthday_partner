// Settings -> delete account. A client cannot delete its own auth user; only
// the admin API can, so this exists purely to do that on the caller's behalf.
//
// The caller is identified from their session and NEVER from a request body —
// accepting an id here would let any signed-in user delete anyone.
//
// Cascade, verified against the live foreign keys: profiles goes, and with it
// their outgoing celebrations, the wishes they authored, their device tokens,
// blocks and queued reminders. Their people row SURVIVES with profile_id set
// to null, because it was built from other people's address books and deleting
// it would break every celebration edge pointing at it. Not being imported at
// all is a different request -- that is private.suppress_person.
//
// KNOWN LIMIT: gifts.sender_profile_id is ON DELETE RESTRICT. No gifts exist in
// M1 so this succeeds today, but once M3 ships, a user who has sent a gift
// cannot be deleted until M3 decides what happens to their gifts.
import { createClient } from "jsr:@supabase/supabase-js@2";

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
  const { error } = await admin.auth.admin.deleteUser(userData.user.id);

  if (error) {
    // Do not echo the driver text: once M3 exists this is where a
    // gifts-RESTRICT violation will surface, and it names internal tables.
    console.error("deleteUser failed", error.message);
    return new Response(JSON.stringify({ error: "delete failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
