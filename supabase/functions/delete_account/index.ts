// Settings -> delete account. A client cannot delete its own auth user; only
// the admin API can, so this exists purely to do that on the caller's behalf.
//
// The caller is identified from their session and NEVER from a request body —
// accepting an id here would let any signed-in user delete anyone.
//
// Cascade, verified against the live foreign keys: profiles goes, and with it
// their outgoing celebrations, the wishes they authored, their device tokens,
// blocks and queued reminders. Their people row SURVIVES with profile_id set
// to null, so every OTHER profile's celebration edge into it keeps working --
// deleting it would break every one of those edges. Not being imported at all
// is a different request -- that is private.suppress_person.
//
// The surviving row is scrubbed, not left as-is: migration 20260827000005's
// before-delete trigger on public.profiles replaces the person's display_name
// with a neutral placeholder, nulls their birth_month/day/year (which also
// stops private.enqueue_reminders from ever queueing a future reminder for
// them -- it requires birth_month IS NOT NULL), deletes any reminder already
// queued for them, and deletes their own delivery address
// (public.addresses.owner_person_id -> people, zero rows in M1). That is what
// makes "delete my account" actually mean the app stops knowing this
// person's birthday, rather than merely unlinking a still-fully-populated row.
//
// KNOWN LIMITS -- two of the ten foreign keys into public.profiles are
// ON DELETE RESTRICT, and both are currently inert only because M1 ships no
// gifts:
//   - gifts.sender_profile_id: once M3 ships and a user has sent one gift,
//     deleting their account fails until M3 decides whether a sender's gifts
//     are reassigned, anonymised, or deletion is refused.
//   - address_access_log.staff_profile_id: worse than the above, because that
//     table is deliberately immutable (an audit trail its own subject can
//     edit is not an audit trail), so reassignment/anonymisation are not
//     options here the way they are for gifts. A staff member who has ever
//     opened the ops console could never be deleted once a single gift, and
//     therefore a single access-log row, exists.
//
// KNOWN LIMIT -- the JWT window: a deleted user's access token stays
// signature-valid until it expires (jwt_expiry, 3600s by default). Their
// auth.sessions rows cascade-delete, so a refresh fails, and every RLS policy
// keys off auth.uid() against a now-missing profile, so the token is
// practically inert for the remaining window -- but this is unfixable with
// signed, statelessly-verified JWTs, only documented.
//
// A concurrent double-call is also worth knowing about: the loser's
// admin.deleteUser call 404s against an already-deleted user and this
// function returns 500 "delete failed" even though the account IS deleted.
// A client must treat that 500 as "re-check whether the account still
// exists", not as proof the delete did not happen.
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
