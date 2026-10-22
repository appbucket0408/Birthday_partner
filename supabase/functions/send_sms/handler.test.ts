import { assertEquals } from "jsr:@std/assert@1";
import { Webhook } from "standardwebhooks";
import { destination, handleSendSms, type SendSmsDeps } from "./handler.ts";

// A real standard-webhooks secret (base64 of 32 bytes), in the dashboard's
// "v1,whsec_" form, so the tests exercise the real signature check rather
// than a stub that always says yes.
const SECRET_B64 = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
const SECRET = `v1,whsec_${SECRET_B64}`;

function signed(payload: unknown, secretB64 = SECRET_B64): Request {
  const body = JSON.stringify(payload);
  const id = "msg_test";
  const now = new Date();
  const signature = new Webhook(secretB64).sign(id, now, body);
  return new Request("http://localhost/send_sms", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "webhook-id": id,
      "webhook-timestamp": String(Math.floor(now.getTime() / 1000)),
      "webhook-signature": signature,
    },
    body,
  });
}

type Sent = { url: string; headers: Headers; body: Record<string, unknown> };

/// A fake provider. Unless told otherwise it answers each provider's own
/// success shape, picked by URL.
function deps(opts: {
  env?: Record<string, string | undefined>;
  status?: number;
  body?: unknown;
  throwOnFetch?: boolean;
} = {}): { deps: SendSmsDeps; sent: Sent[] } {
  const sent: Sent[] = [];
  const env: Record<string, string | undefined> = {
    SEND_SMS_HOOK_SECRET: SECRET,
    SMS_PROVIDER: "msg91",
    MSG91_AUTH_KEY: "auth-key",
    MSG91_TEMPLATE_ID: "tmpl-1",
    FAST2SMS_API_KEY: "f2s-key",
    FAST2SMS_SENDER_ID: "CNDLWS",
    FAST2SMS_MESSAGE_ID: "171234",
    ...opts.env,
  };
  return {
    sent,
    deps: {
      env: (k) => env[k],
      fetchImpl: ((url: string | URL, init?: RequestInit) => {
        if (opts.throwOnFetch) return Promise.reject(new Error("network down"));
        sent.push({
          url: String(url),
          headers: new Headers(init?.headers),
          body: JSON.parse(String(init?.body)),
        });
        const success = String(url).includes("fast2sms")
          ? { return: true, request_id: "r1", message: ["Message sent successfully"] }
          : { type: "success", message: "ok" };
        return Promise.resolve(
          new Response(JSON.stringify(opts.body ?? success), {
            status: opts.status ?? 200,
          }),
        );
      }) as typeof fetch,
    },
  };
}

const PAYLOAD = {
  user: { id: "u1", phone: "919876543210" },
  sms: { otp: "482913" },
};

Deno.test("a signed request for an Indian number sends the OTP via the MSG91 flow", async () => {
  const d = deps();
  const res = await handleSendSms(signed(PAYLOAD), d.deps);

  assertEquals(res.status, 200);
  assertEquals(d.sent.length, 1);
  assertEquals(d.sent[0].url, "https://control.msg91.com/api/v5/flow");
  assertEquals(d.sent[0].headers.get("authkey"), "auth-key");
  assertEquals(d.sent[0].body, {
    template_id: "tmpl-1",
    short_url: "0",
    recipients: [{ mobiles: "919876543210", otp: "482913" }],
  });
});

Deno.test("the template variable name is configurable", async () => {
  const d = deps({ env: { MSG91_OTP_VAR: "var1" } });
  await handleSendSms(signed(PAYLOAD), d.deps);
  assertEquals(d.sent[0].body.recipients, [
    { mobiles: "919876543210", var1: "482913" },
  ]);
});

Deno.test("an unsigned or wrongly signed request is refused without sending", async () => {
  const d = deps();
  const otherKey = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));

  const forged = await handleSendSms(signed(PAYLOAD, otherKey), d.deps);
  const unsigned = await handleSendSms(
    new Request("http://localhost/send_sms", {
      method: "POST",
      body: JSON.stringify(PAYLOAD),
    }),
    d.deps,
  );

  assertEquals(forged.status, 401);
  assertEquals(unsigned.status, 401);
  assertEquals(d.sent.length, 0);
});

Deno.test("a non-Indian number is refused before any SMS is paid for", async () => {
  const d = deps();
  const res = await handleSendSms(
    signed({ user: { phone: "14155550100" }, sms: { otp: "482913" } }),
    d.deps,
  );

  assertEquals(res.status, 400);
  assertEquals(d.sent.length, 0);
  const body = await res.json();
  assertEquals(body.error.message, "Only Indian mobile numbers (+91) are supported.");
});

Deno.test("on a phone change the code goes to the NEW number in sms.phone", async () => {
  const d = deps();
  await handleSendSms(
    signed({
      user: { phone: "" },
      sms: { otp: "482913", phone: "+917000000001" },
    }),
    d.deps,
  );
  assertEquals(
    (d.sent[0].body.recipients as { mobiles: string }[])[0].mobiles,
    "917000000001",
  );
});

Deno.test("missing configuration fails loudly instead of pretending to send", async () => {
  for (const missing of ["SEND_SMS_HOOK_SECRET", "SMS_PROVIDER", "MSG91_AUTH_KEY", "MSG91_TEMPLATE_ID"]) {
    const d = deps({ env: { [missing]: undefined } });
    const res = await handleSendSms(signed(PAYLOAD), d.deps);
    assertEquals(res.status, 500, missing);
    assertEquals(d.sent.length, 0, missing);
  }
});

Deno.test("MSG91 refusing (even with HTTP 200) is reported as a failure", async () => {
  const soft = deps({ body: { type: "error", message: "Insufficient balance" } });
  const hard = deps({ status: 401, body: { type: "error" } });
  const down = deps({ throwOnFetch: true });

  assertEquals((await handleSendSms(signed(PAYLOAD), soft.deps)).status, 502);
  assertEquals((await handleSendSms(signed(PAYLOAD), hard.deps)).status, 502);
  assertEquals((await handleSendSms(signed(PAYLOAD), down.deps)).status, 502);
});

Deno.test("a payload without a usable OTP is refused", async () => {
  const d = deps();
  const res = await handleSendSms(
    signed({ user: { phone: "919876543210" }, sms: {} }),
    d.deps,
  );
  assertEquals(res.status, 400);
  assertEquals(d.sent.length, 0);
});

Deno.test("destination accepts only Indian mobiles, with or without +", () => {
  assertEquals(destination({ user: { phone: "+919876543210" } }), "919876543210");
  assertEquals(destination({ user: { phone: "919876543210" } }), "919876543210");
  assertEquals(destination({ user: { phone: "915876543210" } }), null); // 5xxx: not a mobile
  assertEquals(destination({ user: { phone: "9198765432" } }), null); // too short
  assertEquals(destination({ user: { phone: "449876543210" } }), null); // UK
  assertEquals(destination({}), null);
});

Deno.test("fast2sms_quick sends the code as a Quick SMS to the 10-digit number", async () => {
  const d = deps({ env: { SMS_PROVIDER: "fast2sms_quick" } });
  const res = await handleSendSms(signed(PAYLOAD), d.deps);

  assertEquals(res.status, 200);
  assertEquals(d.sent[0].url, "https://www.fast2sms.com/dev/bulkV2");
  assertEquals(d.sent[0].headers.get("authorization"), "f2s-key");
  assertEquals(d.sent[0].body, {
    route: "q",
    message: "482913 is your Candlewish sign-in code. Do not share it with anyone.",
    numbers: "9876543210",
    sms_details: "1",
  });
});

Deno.test("fast2sms_dlt sends through the approved sender and DLT message id", async () => {
  const d = deps({ env: { SMS_PROVIDER: "fast2sms_dlt" } });
  const res = await handleSendSms(signed(PAYLOAD), d.deps);

  assertEquals(res.status, 200);
  assertEquals(d.sent[0].body, {
    route: "dlt",
    sender_id: "CNDLWS",
    message: "171234",
    variables_values: "482913",
    numbers: "9876543210",
    sms_details: "1",
  });
});

Deno.test("fast2sms answering return:false (even with HTTP 200) is a failure", async () => {
  const d = deps({
    env: { SMS_PROVIDER: "fast2sms_quick" },
    body: { return: false, status_code: 412, message: "Invalid Authentication" },
  });
  assertEquals((await handleSendSms(signed(PAYLOAD), d.deps)).status, 502);
});

Deno.test("each provider refuses to run without its own settings", async () => {
  const cases: [string, string][] = [
    ["fast2sms_quick", "FAST2SMS_API_KEY"],
    ["fast2sms_dlt", "FAST2SMS_SENDER_ID"],
    ["fast2sms_dlt", "FAST2SMS_MESSAGE_ID"],
  ];
  for (const [provider, missing] of cases) {
    const d = deps({ env: { SMS_PROVIDER: provider, [missing]: undefined } });
    const res = await handleSendSms(signed(PAYLOAD), d.deps);
    assertEquals(res.status, 500, `${provider} without ${missing}`);
    assertEquals(d.sent.length, 0);
  }
  const unknown = deps({ env: { SMS_PROVIDER: "twilio" } });
  assertEquals((await handleSendSms(signed(PAYLOAD), unknown.deps)).status, 500);
});

Deno.test("the full phone number never reaches the logs, even when the provider echoes it", async () => {
  const lines: string[] = [];
  const origLog = console.log, origErr = console.error;
  console.log = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  console.error = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  try {
    const ok = deps({
      env: { SMS_PROVIDER: "fast2sms_quick" },
      body: {
        return: true,
        sms_details: {
          per_sms_rate: "7.0000",
          amount_debited: "7.0000",
          valid_numbers: ["9876543210"],
        },
      },
    });
    const failed = deps({
      env: { SMS_PROVIDER: "fast2sms_quick" },
      body: { return: false, message: "bad" },
    });
    await handleSendSms(signed(PAYLOAD), ok.deps);
    await handleSendSms(signed(PAYLOAD), failed.deps);
  } finally {
    console.log = origLog;
    console.error = origErr;
  }
  const all = lines.join("\n");
  assertEquals(all.includes("9876543210"), false, all);
  assertEquals(all.includes("482913"), false, "the OTP must not be logged either");
  assertEquals(all.includes("fast2sms cost 7.0000 debited 7.0000"), true, all);
});
