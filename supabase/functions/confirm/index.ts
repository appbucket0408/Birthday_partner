// The recipient's confirm page (spec §4). GET renders the address form (or
// the neutral 404, or the already-confirmed notice) keyed by confirm_token;
// POST will call rpc_confirm_gift in Task 4. Unauthenticated by design -- the
// token IS the capability, and the recipient has no Supabase session.
import { createClient } from "jsr:@supabase/supabase-js@2";

// Every string used more than once, or that Task 4's result pages reuse,
// lives here once. Exported so Task 4 can import COPY.alreadyConfirmed and
// COPY.invalidLink for its own result pages rather than re-typing them.
export const COPY = {
  formHeading: "Confirm your delivery address",
  alreadyConfirmed: "This gift is already confirmed.",
  invalidLink: "This link is not valid.",
  confirmedHeading: "Delivery confirmed",
  refundedHeading: "We can't deliver there yet",
  genericFailureHeading: "Something went wrong",
  formError: "Please fill in the required fields.",
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The gift columns this handler is allowed to read, spelled out so a column
// added to `gifts` later (amount_minor included) cannot leak by default
// (spec §4.6). Never `select *`.
const GIFT_COLUMNS =
  "sender_profile_id, product_id, occasion_date, message, status, confirm_token_used_at";

function esc(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function page(title: string, bodyHtml: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${esc(title)}</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 480px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; }
  h1 { font-size: 1.25rem; }
  .message { font-style: italic; }
  label { display: block; margin-top: 1rem; font-weight: 600; }
  input { width: 100%; padding: 0.5rem; margin-top: 0.25rem; box-sizing: border-box; font-size: 1rem; }
  button { margin-top: 1.5rem; padding: 0.75rem 1.5rem; font-size: 1rem; }
  .error { color: #b00020; font-weight: 600; }
</style>
</head>
<body>
${bodyHtml}
</body>
</html>`;
}

function respond(title: string, bodyHtml: string, status = 200): Response {
  return new Response(page(title, bodyHtml), {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

// The ONE code path for "this link does not lead to a confirmable gift right
// now". Called with no arguments and no branching inside it, so an unknown
// token, a malformed token, a missing token, and a real token whose gift is
// not `awaiting_confirm` all produce byte-identical output (spec §4.3): there
// is only one literal to drift, and only one call site can ever diverge it.
function renderNeutral404(): Response {
  return respond(
    COPY.invalidLink,
    `<h1>${esc(COPY.invalidLink)}</h1>`,
    404,
  );
}

function renderAlreadyConfirmed(): Response {
  return respond(COPY.alreadyConfirmed, `<h1>${esc(COPY.alreadyConfirmed)}</h1>`);
}

// Spec §4.3's "Confirmed" outcome. The city rendered is the recipient's own
// typed input (escaped), not a re-read of the row -- see the POST handler's
// comment on why the returned status, not a city comparison, drives which of
// this and renderRefunded is chosen.
function renderConfirmed(city: string): Response {
  const body =
    `<h1>${esc(COPY.confirmedHeading)}</h1><p>Thank you — the cake is on its way to ${
      esc(city)
    }.</p>`;
  return respond(COPY.confirmedHeading, body);
}

// Spec §4.3's "City outside the service area -> refunded" outcome.
// private.confirm_gift already declined the gift, released the slot and
// refunded it before returning this row normally (it deliberately does not
// raise -- see the POST handler's comment), so this page is purely
// informational.
function renderRefunded(city: string): Response {
  const body = `<h1>${esc(COPY.refundedHeading)}</h1><p>We do not deliver to ${
    esc(city)
  } yet, so the gift has been refunded.</p>`;
  return respond(COPY.refundedHeading, body);
}

// The catch-all for an RPC failure that isn't one of the three mapped cases.
// private.confirm_gift's driver text names internal tables, so it is logged
// via console.error at the call site and never reaches this page -- the same
// rule delete_account/index.ts:92 follows.
function renderGenericFailure(): Response {
  return respond(
    COPY.genericFailureHeading,
    `<h1>${esc(COPY.genericFailureHeading)}</h1><p>Please try again later.</p>`,
    500,
  );
}

function renderForm(
  token: string,
  occasionDate: string,
  message: string | null,
  senderName: string,
  productName: string,
  errorMessage?: string,
  values?: {
    line1: string;
    line2: string;
    city: string;
    pincode: string;
    label: string;
  },
): Response {
  const messageHtml = message
    ? `<p class="message">&ldquo;${esc(message)}&rdquo;</p>`
    : "";
  const errorHtml = errorMessage
    ? `<p class="error">${esc(errorMessage)}</p>`
    : "";
  // Sticky values so a rejected submission (Task 4) doesn't make the
  // recipient retype everything; GET's first render passes none of this,
  // so every field falls back to blank/"Home" exactly as before.
  const v = values ?? { line1: "", line2: "", city: "", pincode: "", label: "Home" };

  const body = `
<h1>${esc(COPY.formHeading)}</h1>
<p>${esc(senderName)} has sent you ${esc(productName)} for ${esc(occasionDate)}.</p>
${messageHtml}
${errorHtml}
<form method="post" action="/functions/v1/confirm">
  <input type="hidden" name="token" value="${esc(token)}" />
  <label>Address line 1
    <input type="text" name="line1" value="${esc(v.line1)}" required />
  </label>
  <label>Address line 2 (optional)
    <input type="text" name="line2" value="${esc(v.line2)}" />
  </label>
  <label>City
    <input type="text" name="city" value="${esc(v.city)}" required />
  </label>
  <label>Pincode
    <input type="text" name="pincode" value="${esc(v.pincode)}" required />
  </label>
  <label>Label
    <input type="text" name="label" value="${esc(v.label || "Home")}" />
  </label>
  <button type="submit">Confirm delivery</button>
</form>`;

  return respond(COPY.formHeading, body);
}

type ConfirmableGift = {
  occasionDate: string;
  message: string | null;
  senderName: string;
  productName: string;
};

type LoadResult =
  | { ok: true; data: ConfirmableGift }
  | { ok: false; response: Response };

// Shared by GET (render the fresh form) and POST's validation-failure branch
// (re-render the form with an error, spec's requirement that a blank
// submission never reach the RPC): resolves the token to the gift's current
// phase and, only if it is awaiting_confirm, the sender/product names the
// form needs. Every branch here is a terminal Response for the caller to
// return as-is -- callers must not add their own status branching on top.
async function loadConfirmableGift(
  // deno-lint-ignore no-explicit-any
  admin: any,
  token: string,
): Promise<LoadResult> {
  const { data: gift, error } = await admin
    .from("gifts")
    .select(GIFT_COLUMNS)
    .eq("confirm_token", token)
    .maybeSingle();

  if (error) {
    console.error("confirm: gift lookup failed", error.message);
    return { ok: false, response: renderNeutral404() };
  }
  if (!gift) {
    return { ok: false, response: renderNeutral404() };
  }

  // A recipient who taps their own link twice deserves a straight answer --
  // holding the token is itself evidence of legitimacy (spec §4.3). Checked
  // BEFORE the status check below: confirm_token_used_at is set only once,
  // at the moment a real confirmation happens, so this branch never fires
  // for a token that was merely created and never used.
  if (gift.confirm_token_used_at !== null) {
    return { ok: false, response: renderAlreadyConfirmed() };
  }

  // Every other non-awaiting_confirm status (still `draft`, or `expired`, or
  // any other state a token can be minted against before payment) folds into
  // the same neutral 404 as an unknown token -- see renderNeutral404's
  // comment. This is deliberately NOT specialised per status: doing so would
  // let a prober learn which unpaid state a real token is in.
  if (gift.status !== "awaiting_confirm") {
    return { ok: false, response: renderNeutral404() };
  }

  const [{ data: sender, error: senderError }, { data: product, error: productError }] =
    await Promise.all([
      admin
        .from("profiles")
        .select("display_name")
        .eq("id", gift.sender_profile_id)
        .maybeSingle(),
      admin
        .from("products")
        .select("name")
        .eq("id", gift.product_id)
        .maybeSingle(),
    ]);

  if (senderError || productError || !sender || !product) {
    // The gift row itself was found and is awaiting_confirm, so this is an
    // internal inconsistency (a dangling FK should be impossible given the
    // schema's `references ... on delete restrict`), not a bad token --
    // it must not be folded into the neutral 404, which exists solely to
    // hide token validity.
    console.error(
      "confirm: sender/product lookup failed",
      senderError?.message,
      productError?.message,
    );
    return {
      ok: false,
      response: new Response("something went wrong", { status: 500 }),
    };
  }

  return {
    ok: true,
    data: {
      occasionDate: gift.occasion_date,
      message: gift.message,
      senderName: sender.display_name,
      productName: product.name,
    },
  };
}

function requireEnv(): { supabaseUrl: string; serviceKey: string } | null {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return null;
  }
  return { supabaseUrl, serviceKey };
}

async function handleGet(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const token = url.searchParams.get("token");

  if (!token || !UUID_RE.test(token)) {
    return renderNeutral404();
  }

  const env = requireEnv();
  if (!env) {
    console.error("confirm: function is misconfigured");
    return new Response("server misconfigured", { status: 500 });
  }

  const admin = createClient(env.supabaseUrl, env.serviceKey);

  const loaded = await loadConfirmableGift(admin, token);
  if (!loaded.ok) {
    return loaded.response;
  }

  return renderForm(
    token,
    loaded.data.occasionDate,
    loaded.data.message,
    loaded.data.senderName,
    loaded.data.productName,
  );
}

async function handlePost(req: Request): Promise<Response> {
  // The recipient's browser posts application/x-www-form-urlencoded (the
  // only content type renderForm's <form> ever sends).
  const params = new URLSearchParams(await req.text());
  const token = params.get("token");

  if (!token || !UUID_RE.test(token)) {
    return renderNeutral404();
  }

  const env = requireEnv();
  if (!env) {
    console.error("confirm: function is misconfigured");
    return new Response("server misconfigured", { status: 500 });
  }

  const admin = createClient(env.supabaseUrl, env.serviceKey);

  const line1 = (params.get("line1") ?? "").trim();
  const line2 = params.get("line2") ?? "";
  const city = (params.get("city") ?? "").trim();
  const pincode = (params.get("pincode") ?? "").trim();
  const label = (params.get("label") ?? "").trim() || "Home";

  // Validate BEFORE calling the RPC: a blank submission must not reach the
  // database at all, so the gift's status is left untouched. Re-fetching via
  // loadConfirmableGift (rather than trusting the posted token blindly) also
  // means a blank submission against a bad/foreign token still gets the
  // neutral 404 or already-confirmed page instead of a form it has no right
  // to see re-rendered.
  if (!line1 || !city || !pincode) {
    const loaded = await loadConfirmableGift(admin, token);
    if (!loaded.ok) {
      return loaded.response;
    }
    return renderForm(
      token,
      loaded.data.occasionDate,
      loaded.data.message,
      loaded.data.senderName,
      loaded.data.productName,
      COPY.formError,
      { line1, line2, city, pincode, label },
    );
  }

  const { data: gift, error } = await admin.rpc("rpc_confirm_gift", {
    p_confirm_token: token,
    p_line1: line1,
    p_line2: line2,
    p_city: city,
    p_pincode: pincode,
    p_label: label,
  });

  if (error) {
    // Not awaiting confirmation right now -- indistinguishable from an
    // unknown token, so this folds into the SAME neutral 404 Task 3 uses
    // (spec §4.3), not a copy of its output.
    if (error.code === "23514") {
      return renderNeutral404();
    }
    if (error.message === "this confirmation link has already been used") {
      return renderAlreadyConfirmed();
    }
    if (error.message === "unknown confirmation link") {
      return renderNeutral404();
    }
    // Anything else: private.confirm_gift's driver text names internal
    // tables, so it is logged, never rendered -- the same rule
    // delete_account/index.ts:92 follows.
    console.error("confirm: rpc_confirm_gift failed", error.code, error.message);
    return renderGenericFailure();
  }

  if (!gift) {
    console.error("confirm: rpc_confirm_gift returned no row");
    return renderGenericFailure();
  }

  // Out of area is NOT an error: private.confirm_gift declines the gift,
  // releases the slot and refunds it, then returns the row normally rather
  // than raising -- raising here would roll all three back
  // (20260822000008_gift_lifecycle.sql:166-177). So the page is chosen from
  // the RETURNED status, never by re-comparing the city in this handler.
  if (gift.status === "confirmed") {
    return renderConfirmed(city);
  }
  if (gift.status === "refunded") {
    return renderRefunded(city);
  }

  console.error("confirm: rpc_confirm_gift returned unexpected status", gift.status);
  return renderGenericFailure();
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "GET") {
    return await handleGet(req);
  }

  if (req.method === "POST") {
    return await handlePost(req);
  }

  return new Response("method not allowed", { status: 405 });
});
