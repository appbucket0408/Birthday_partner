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

function renderForm(
  token: string,
  occasionDate: string,
  message: string | null,
  senderName: string,
  productName: string,
): Response {
  const messageHtml = message
    ? `<p class="message">&ldquo;${esc(message)}&rdquo;</p>`
    : "";

  const body = `
<h1>${esc(COPY.formHeading)}</h1>
<p>${esc(senderName)} has sent you ${esc(productName)} for ${esc(occasionDate)}.</p>
${messageHtml}
<form method="post" action="/functions/v1/confirm">
  <input type="hidden" name="token" value="${esc(token)}" />
  <label>Address line 1
    <input type="text" name="line1" required />
  </label>
  <label>Address line 2 (optional)
    <input type="text" name="line2" />
  </label>
  <label>City
    <input type="text" name="city" required />
  </label>
  <label>Pincode
    <input type="text" name="pincode" required />
  </label>
  <label>Label
    <input type="text" name="label" value="Home" />
  </label>
  <button type="submit">Confirm delivery</button>
</form>`;

  return respond(COPY.formHeading, body);
}

async function handleGet(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const token = url.searchParams.get("token");

  if (!token || !UUID_RE.test(token)) {
    return renderNeutral404();
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("confirm: function is misconfigured");
    return new Response("server misconfigured", { status: 500 });
  }

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: gift, error } = await admin
    .from("gifts")
    .select(GIFT_COLUMNS)
    .eq("confirm_token", token)
    .maybeSingle();

  if (error) {
    console.error("confirm: gift lookup failed", error.message);
    return renderNeutral404();
  }
  if (!gift) {
    return renderNeutral404();
  }

  // A recipient who taps their own link twice deserves a straight answer --
  // holding the token is itself evidence of legitimacy (spec §4.3). Checked
  // BEFORE the status check below: confirm_token_used_at is set only once,
  // at the moment a real confirmation happens, so this branch never fires
  // for a token that was merely created and never used.
  if (gift.confirm_token_used_at !== null) {
    return renderAlreadyConfirmed();
  }

  // Every other non-awaiting_confirm status (still `draft`, or `expired`, or
  // any other state a token can be minted against before payment) folds into
  // the same neutral 404 as an unknown token -- see renderNeutral404's
  // comment. This is deliberately NOT specialised per status: doing so would
  // let a prober learn which unpaid state a real token is in.
  if (gift.status !== "awaiting_confirm") {
    return renderNeutral404();
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
    return new Response("something went wrong", { status: 500 });
  }

  return renderForm(
    token,
    gift.occasion_date,
    gift.message,
    sender.display_name,
    product.name,
  );
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "GET") {
    return await handleGet(req);
  }

  if (req.method === "POST") {
    // Task 4 implements this.
    return new Response("not implemented", { status: 501 });
  }

  return new Response("method not allowed", { status: 405 });
});
