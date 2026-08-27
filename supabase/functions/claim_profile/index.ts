// Onboarding's last step. Takes the phone the caller VERIFIED during OTP —
// read from their session, never from the request body — and claims the person
// row for it. Accepting a phone from the body would let a signed-in user claim
// someone else's number and inherit every celebration edge pointing at it.
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

  const phone = userData.user.phone;
  if (!phone) {
    // A session with no phone: an anonymous sign-in, or an email-only user.
    // Neither can be claimed — the whole graph is keyed on a verified number.
    return new Response(JSON.stringify({ error: "session has no verified phone" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // GoTrue stores the phone without a leading '+'; phone_hash is computed over
  // the E.164 form the app sends everywhere else, so normalise here.
  const e164 = phone.startsWith("+") ? phone : `+${phone}`;

  // Assert the shape rather than trusting it. private.phone_hash is a raw HMAC
  // with no normalisation of its own, so ANY deviation hashes to a different
  // value — which mints a brand-new person row and silently orphans every
  // celebration edge pointing at the user's real number. That failure is
  // invisible at runtime, so it has to fail loudly here instead.
  if (!/^\+[1-9]\d{6,14}$/.test(e164)) {
    console.error("session phone is not E.164 after normalisation");
    return new Response(JSON.stringify({ error: "session phone is malformed" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const admin = createClient(url, serviceKey);
  const { data, error } = await admin.rpc("rpc_claim_person", {
    p_profile_id: userData.user.id,
    p_phone: e164,
  });

  if (error) {
    console.error("rpc_claim_person failed", error.message);

    // people.profile_id is UNIQUE, so a user who already claimed one number and
    // now claims a DIFFERENT one violates people_profile_id_key. That is a
    // caller state, not a server fault: as a 500 the app cannot tell it from a
    // transient failure and retries forever. M1 ships no change-number flow, so
    // this is unreachable from the app today; it becomes reachable the moment
    // one exists, and M2 has to decide what renumbering does to the old person
    // row and the edges still pointing at it.
    if (error.code === "23505") {
      return new Response(
        JSON.stringify({ error: "profile already claimed a different number" }),
        { status: 409, headers: { "content-type": "application/json" } },
      );
    }

    return new Response(JSON.stringify({ error: "claim failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  if (data === null) {
    // claim_person's upsert always RETURNS a row, so this is unreachable today.
    // It is guarded because its sibling private.upsert_person deliberately
    // returns null for suppressed numbers: if claim ever honours suppression,
    // an unguarded null would ship a 200 the app reads as onboarding-complete.
    console.error("rpc_claim_person returned no person id");
    return new Response(JSON.stringify({ error: "claim failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ person_id: data }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
