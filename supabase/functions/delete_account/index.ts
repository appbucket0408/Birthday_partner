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
// KNOWN LIMIT -- gifts.sender_profile_id, PARTIALLY ADDRESSED (M3 Phase 1a
// pre-merge fix round). This was written when M1 shipped no gifts, so the
// RESTRICT below was inert; M3 shipped gifts, so it no longer is. Reproduced
// on the live DB: a user who had ever drafted a gift could NEVER delete
// their account again -- not even after the hold lapsed, since
// private.expire_stale_gifts moves a lapsed draft to 'expired' and keeps the
// row.
//
// Fixed for the two states that carry no payment, no delivery and no
// counterparty obligation: rpc_delete_own_draft_gifts (below, before
// admin.deleteUser) deletes the caller's own 'draft' and 'expired' gifts,
// so an abandoned or lapsed hold no longer blocks erasure.
//
// STILL a real limit for every other status: a 'paid' gift and beyond is a
// real transaction with a counterparty, and deleting the sender's account
// out from under it is NOT safe to do silently. That case still refuses
// deletion below (accountHasActiveGifts) -- M3 Phase 2, which ships
// payments, must decide whether such a sender's gifts are reassigned,
// anonymised, or deletion is refused outright, and must revisit this
// function then.
//
// address_access_log.staff_profile_id is untouched by this fix and remains
// a KNOWN LIMIT: that table is deliberately immutable (an audit trail its
// own subject can edit is not an audit trail), so reassignment/anonymisation
// are not options here the way they are for gifts. A staff member who has
// ever opened the ops console could never be deleted once a single
// access-log row exists.
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

  // Clear the one class of gifts that must never block deletion: a draft or
  // expired hold is free, unconfirmed, and has no counterparty obligation.
  // This must run BEFORE deleteUser, not as a fallback after it fails --
  // deleteUser is a single all-or-nothing GoTrue call, so any RESTRICT
  // violation it hits aborts the whole delete, and there is no way to
  // "retry after clearing gifts" once that has already happened.
  const { error: giftsError } = await admin.rpc(
    "rpc_delete_own_draft_gifts",
    { p_profile_id: userData.user.id },
  );
  if (giftsError) {
    // Same driver-text rule as below: this is our own RPC, not GoTrue, but
    // it still touches internal table/column names in its error text.
    console.error("rpc_delete_own_draft_gifts failed", giftsError.message);
    return new Response(JSON.stringify({ error: "delete failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  // Profile and wish photos live in Storage, which no foreign key reaches:
  // deleting the user would orphan them. Removed first, and a failure stops
  // the delete -- a "deleted" account whose photo is still stored is the one
  // outcome worse than a retry. Removed a page at a time: list() returns at
  // most `limit` objects, and years of wish photos can exceed one page.
  const folder = userData.user.id;
  let removeError: { message: string } | null = null;
  for (const bucket of ["avatars", "wish_photos"]) {
    while (!removeError) {
      const { data: photos, error: listError } = await admin.storage
        .from(bucket)
        .list(folder, { limit: 1000 });
      if (listError) {
        removeError = listError;
        break;
      }
      if (!photos || photos.length === 0) break;
      removeError = (await admin.storage
        .from(bucket)
        .remove(photos.map((p) => `${folder}/${p.name}`))).error;
    }
  }
  if (removeError) {
    console.error("photo cleanup failed", removeError.message);
    return new Response(JSON.stringify({ error: "delete failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const { error } = await admin.auth.admin.deleteUser(userData.user.id);

  if (error) {
    // Do not echo the driver text -- it names internal tables. But a caller
    // that still fails here (after draft/expired gifts were just cleared
    // above) is in a genuinely different situation than any other failure:
    // they hold a gift in a status this function deliberately does not
    // touch (paid and beyond -- a real transaction with a counterparty, not
    // safe to silently delete). That is distinguishable from "something
    // went wrong" without revealing which table or constraint fired, so the
    // client gets a code it can act on (e.g. "finish or cancel your gift
    // before deleting your account") instead of a dead end. Anything else
    // (a genuinely unexpected error) keeps the old generic shape.
    console.error("deleteUser failed", error.message);
    const looksLikeActiveGift = error.message?.includes("gifts") ?? false;
    return new Response(
      JSON.stringify({
        error: looksLikeActiveGift ? "account_has_active_gifts" : "delete failed",
      }),
      {
        status: looksLikeActiveGift ? 409 : 500,
        headers: { "content-type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
