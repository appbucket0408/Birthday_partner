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
    // Email-only sessions cannot be claimed: the whole graph is keyed on a
    // verified phone number.
    return new Response(JSON.stringify({ error: "session has no verified phone" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // GoTrue stores the phone without a leading '+'; phone_hash is computed over
  // the E.164 form the app sends everywhere else, so normalise here.
  const e164 = phone.startsWith("+") ? phone : `+${phone}`;

  const admin = createClient(url, serviceKey);
  const { data, error } = await admin.rpc("rpc_claim_person", {
    p_profile_id: userData.user.id,
    p_phone: e164,
  });

  if (error) {
    console.error("rpc_claim_person failed", error.message);
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
