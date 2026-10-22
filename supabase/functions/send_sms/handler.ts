// The Send SMS Auth Hook: GoTrue generates the OTP and calls this function
// to deliver it, instead of using a built-in provider. Built-in providers
// (Twilio and friends) cost about Rs 7 per SMS to India; the Indian
// providers here cost about Rs 0.25, and India requires DLT-registered
// templates for branded SMS anyway.
//
// SMS_PROVIDER picks the route:
//   fast2sms_quick  Fast2SMS Quick SMS: no DLT registration needed, generic
//                   sender. Usable before DLT approval.
//   fast2sms_dlt    Fast2SMS DLT route: your approved sender ID + template.
//   msg91           MSG91 Flow API: your approved sender ID + template.
// Switching provider is a secrets change, not a code change.
//
// Deliberately separate from index.ts for the same reason as
// drain_reminders/handler.ts: importing index.ts runs Deno.serve.
//
// Hosted only. Locally, config.toml points [auth.hook.send_sms] at the
// pg-function local_dev.send_sms, which sends nothing.
import { Webhook } from "standardwebhooks";

/// The parts of the hook payload this function reads. GoTrue also sends the
/// full user object; nothing else in it is needed.
type HookPayload = {
  user?: { phone?: string };
  sms?: { otp?: string; phone?: string };
};

export type SendSmsDeps = {
  env: (k: string) => string | undefined;
  fetchImpl: typeof fetch;
};

/// GoTrue gives up on a hook after a few seconds; answer before it does, so
/// the user sees our error rather than a generic timeout.
const PROVIDER_TIMEOUT_MS = 4000;

/// Indian mobile numbers only: 91, then ten digits starting 6-9. Anything
/// else is refused BEFORE it costs money. SMS pumping fraud works by making
/// an app text premium-rate numbers abroad; this app's users are in India,
/// so a foreign number is never a real sign-up.
const INDIAN_MOBILE = /^91[6-9]\d{9}$/;

/// The number to text: digits only, country code first (91XXXXXXXXXX).
/// sms.phone wins over user.phone: on a phone CHANGE (an email account
/// linking its phone, PhoneLinkCubit) user.phone is still the old number,
/// or empty, and the code must go to the new one.
export function destination(p: HookPayload): string | null {
  const raw = p.sms?.phone || p.user?.phone || "";
  const digits = raw.replace(/^\+/, "");
  return INDIAN_MOBILE.test(digits) ? digits : null;
}

/// One provider: the env it needs, and how to send one OTP. `send` returns
/// null on success or a reason for the log (never shown to the user).
type Provider = {
  required: string[];
  send: (
    phone: string,
    otp: string,
    env: (k: string) => string | undefined,
    fetchImpl: typeof fetch,
  ) => Promise<string | null>;
};

/// Fast2SMS takes the 10-digit number without the country code.
function tenDigits(phone: string): string {
  return phone.slice(2);
}

/// Fast2SMS answers {"return": true, ...} on success and
/// {"return": false, "message": ...} otherwise, sometimes with HTTP 200.
async function fast2sms(
  body: Record<string, string>,
  env: (k: string) => string | undefined,
  fetchImpl: typeof fetch,
): Promise<string | null> {
  const res = await fetchImpl("https://www.fast2sms.com/dev/bulkV2", {
    method: "POST",
    headers: {
      "authorization": env("FAST2SMS_API_KEY")!,
      "accept": "application/json",
      "content-type": "application/json",
    },
    // sms_details makes the response carry per_sms_rate and amount_debited,
    // logged below: the only way to see what each OTP actually costs.
    body: JSON.stringify({ ...body, sms_details: "1" }),
    signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
  });
  const result = await res.json().catch(() => ({})) as {
    return?: boolean;
    message?: unknown;
    sms_details?: { per_sms_rate?: unknown; amount_debited?: unknown };
  };
  if (!res.ok || result.return !== true) {
    return `fast2sms ${res.status}: ${JSON.stringify(result.message ?? null)}`;
  }
  // Only the two price fields: sms_details also echoes the full recipient
  // number (valid_numbers), which must not reach the logs.
  console.log(
    "fast2sms cost",
    result.sms_details?.per_sms_rate ?? "?",
    "debited",
    result.sms_details?.amount_debited ?? "?",
  );
  return null;
}

export const PROVIDERS: Record<string, Provider> = {
  fast2sms_quick: {
    required: ["FAST2SMS_API_KEY"],
    send: (phone, otp, env, fetchImpl) =>
      fast2sms({
        route: "q",
        message: `${otp} is your Candlewish sign-in code. Do not share it with anyone.`,
        numbers: tenDigits(phone),
      }, env, fetchImpl),
  },
  fast2sms_dlt: {
    // FAST2SMS_MESSAGE_ID is the DLT message id from Fast2SMS's DLT Manager;
    // its template has exactly one {#var#}, the code.
    required: ["FAST2SMS_API_KEY", "FAST2SMS_SENDER_ID", "FAST2SMS_MESSAGE_ID"],
    send: (phone, otp, env, fetchImpl) =>
      fast2sms({
        route: "dlt",
        sender_id: env("FAST2SMS_SENDER_ID")!,
        message: env("FAST2SMS_MESSAGE_ID")!,
        variables_values: otp,
        numbers: tenDigits(phone),
      }, env, fetchImpl),
  },
  msg91: {
    required: ["MSG91_AUTH_KEY", "MSG91_TEMPLATE_ID"],
    send: async (phone, otp, env, fetchImpl) => {
      const res = await fetchImpl("https://control.msg91.com/api/v5/flow", {
        method: "POST",
        headers: {
          "authkey": env("MSG91_AUTH_KEY")!,
          "accept": "application/json",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          template_id: env("MSG91_TEMPLATE_ID"),
          short_url: "0",
          // The variable name in the MSG91 template, written there as ##otp##.
          recipients: [{ mobiles: phone, [env("MSG91_OTP_VAR") || "otp"]: otp }],
        }),
        signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
      });
      // MSG91 answers 200 with {"type":"error"} for some failures (bad
      // template, no balance), so the status alone is not proof of sending.
      const result = await res.json().catch(() => ({})) as {
        type?: string;
        message?: string;
      };
      if (!res.ok || result.type !== "success") {
        return `msg91 ${res.status}: ${result.message ?? "(no message)"}`;
      }
      return null;
    },
  },
};

/// The GoTrue hook error shape. GoTrue shows `message` to the client.
function hookError(status: number, message: string): Response {
  return new Response(
    JSON.stringify({ error: { http_code: status, message } }),
    { status, headers: { "content-type": "application/json" } },
  );
}

/// Last four digits only: enough to match a support complaint to a log line,
/// not enough to make the log a list of users' numbers.
function masked(phone: string): string {
  return `******${phone.slice(-4)}`;
}

export async function handleSendSms(
  req: Request,
  deps: SendSmsDeps,
): Promise<Response> {
  // The dashboard shows the secret as "v1,whsec_<base64>"; the library wants
  // only the base64 part.
  const secret = (deps.env("SEND_SMS_HOOK_SECRET") ?? "")
    .replace("v1,whsec_", "");
  const providerName = deps.env("SMS_PROVIDER") ?? "";
  const provider = PROVIDERS[providerName];
  if (!secret || !provider || provider.required.some((k) => !deps.env(k))) {
    // Failing loudly, not succeeding silently: a 200 here would tell GoTrue
    // the code was sent, and the user would wait for an SMS that never comes.
    console.error(
      `send_sms is misconfigured (SMS_PROVIDER=${providerName || "unset"})`,
    );
    return hookError(500, "SMS sending is not configured.");
  }

  // The body must be verified as the exact bytes that were signed, so read it
  // as text and parse only after verification.
  const body = await req.text();
  let payload: HookPayload;
  try {
    payload = new Webhook(secret).verify(
      body,
      Object.fromEntries(req.headers),
    ) as HookPayload;
  } catch {
    // Not from GoTrue. Without this check anyone who found the URL could
    // spend the SMS balance texting arbitrary numbers.
    return hookError(401, "Invalid hook signature.");
  }

  const otp = payload.sms?.otp;
  if (!otp || !/^\d{4,10}$/.test(otp)) {
    return hookError(400, "No code to send.");
  }
  const phone = destination(payload);
  if (!phone) {
    return hookError(400, "Only Indian mobile numbers (+91) are supported.");
  }

  let failure: string | null;
  try {
    failure = await provider.send(phone, otp, deps.env, deps.fetchImpl);
  } catch (e) {
    failure = `${providerName} unreachable: ${String(e)}`;
  }
  if (failure) {
    console.error("otp not sent", masked(phone), failure);
    return hookError(502, "Could not send the code. Please try again.");
  }

  console.log("otp sent", providerName, masked(phone));
  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
