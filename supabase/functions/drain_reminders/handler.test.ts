
import { assertEquals } from "jsr:@std/assert@1";
import { bodySaysUnregistered, type DrainDeps, handleDrain } from "./handler.ts";
import { reminderBody, resetTokenCache, wishBody } from "./fcm.ts";

const SECRET = "test-drain-secret";

function post(secret: string | null = SECRET): Request {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (secret !== null) headers["x-drain-secret"] = secret;
  return new Request("http://localhost/drain_reminders", {
    method: "POST",
    headers,
    body: "{}",
  });
}

type Calls = {
  rpc: { fn: string; params: Record<string, unknown> }[];
  deleted: string[];
  fetched: string[];
  /// The JSON body of every FCM send, so a test can pin the message shape.
  sentBodies: unknown[];
};

function deps(opts: {
  batch?: unknown[];
  serviceAccount?: string;
  fcmStatus?: number;
  fcmBody?: string;
  tokenStatus?: number;
} = {}): { deps: DrainDeps; calls: Calls } {
  const calls: Calls = { rpc: [], deleted: [], fetched: [], sentBodies: [] };
  const env: Record<string, string | undefined> = {
    DRAIN_SECRET: SECRET,
    SUPABASE_URL: "http://localhost",
    SUPABASE_SERVICE_ROLE_KEY: "service-key",
    FCM_SERVICE_ACCOUNT: opts.serviceAccount,
  };
  return {
    calls,
    deps: {
      env: (k) => env[k],
      now: () => 1_700_000_000_000,
      admin: {
        rpc: (fn, params) => {
          calls.rpc.push({ fn, params });
          if (fn === "rpc_next_reminder_batch") {
            return Promise.resolve({ data: opts.batch ?? [], error: null });
          }
          return Promise.resolve({ error: null });
        },
        deleteDeviceToken: (token) => {
          calls.deleted.push(token);
          return Promise.resolve({ error: null });
        },
      },
      fetchImpl: ((url: string | URL, init?: RequestInit) => {
        calls.fetched.push(String(url));
        if (String(url).includes("fcm.googleapis.com")) {
          calls.sentBodies.push(JSON.parse(String(init?.body)));
        }
        if (String(url).includes("oauth2.googleapis.com")) {
          return Promise.resolve(
            new Response(
              JSON.stringify({ access_token: "tok", expires_in: 3600 }),
              { status: opts.tokenStatus ?? 200 },
            ),
          );
        }
        return Promise.resolve(
          new Response(opts.fcmBody ?? "{}", { status: opts.fcmStatus ?? 200 }),
        );
      }) as unknown as typeof fetch,
    },
  };
}

const reminder = (over: Record<string, unknown> = {}) => ({
  outbox_id: 1,
  token: "device-token-abc",
  platform: "android",
  subject_name: "Asha",
  subject_person_id: 42,
  offset_days: 0,
  occasion_date: "2026-09-27",
  ...over,
});

Deno.test("a call with no secret is refused, and reads nothing", async () => {
  const { deps: d, calls } = deps();
  const res = await handleDrain(post(null), d);
  assertEquals(res.status, 401);
  assertEquals(calls.rpc.length, 0, "an unauthorised call must not claim a batch");
});

Deno.test("a call with the wrong secret is refused", async () => {
  const { deps: d, calls } = deps();
  assertEquals((await handleDrain(post("nope"), d)).status, 401);
  assertEquals(calls.rpc.length, 0);
});

Deno.test("with no service account it dry-runs and claims nothing extra", async () => {
  const { deps: d, calls } = deps({ batch: [reminder()] });
  const res = await handleDrain(post(), d);
  assertEquals(await res.json(), {
    dryRun: true,
    would_send: 1,
    sent: 0,
    failed: 0,
  });
  assertEquals(calls.fetched.length, 0, "dry run must not reach the network");
  assertEquals(calls.rpc.map((c) => c.fn), ["rpc_next_reminder_batch"]);
});

Deno.test(
  "a reminder is sent on the birthday_reminders channel, branded, with its "
    + "body and person_id unchanged",
  async () => {
    resetTokenCache();
    const { deps: d, calls } = deps({
      batch: [reminder()],
      serviceAccount: await serviceAccountJson(),
    });

    await handleDrain(post(), d);

    // The whole message, not a field at a time: the app's channel, its tap
    // routing (data.person_id) and the copy all ride on this one shape.
    assertEquals(calls.sentBodies, [{
      message: {
        token: "device-token-abc",
        notification: {
          title: "Candlewish 🎂",
          body: reminderBody("Asha", 0),
        },
        android: { notification: { channel_id: "birthday_reminders" } },
        data: { person_id: "42" },
      },
    }]);
  },
);

// A wish row as rpc_next_reminder_batch returns it (20261018000003):
// subject_person_id is the recipient's own person, the wall the wish is on.
const wishRow = (over: Record<string, unknown> = {}) =>
  reminder({
    kind: "wish",
    subject_name: "Me Myself",
    subject_person_id: 7,
    offset_days: null,
    occasion_date: null,
    author_name: "Asha",
    wish_id: 99,
    ...over,
  });

Deno.test(
  "a wish is sent on the wishes channel, naming its author, routed to the "
    + "recipient's wall and the wish",
  async () => {
    resetTokenCache();
    const { deps: d, calls } = deps({
      batch: [wishRow()],
      serviceAccount: await serviceAccountJson(),
    });

    const res = await handleDrain(post(), d);

    assertEquals(calls.sentBodies, [{
      message: {
        token: "device-token-abc",
        notification: {
          title: "Candlewish 🎂",
          body: "Asha left you a birthday wish.",
        },
        android: { notification: { channel_id: "wishes" } },
        data: { person_id: "7", wish_id: "99" },
      },
    }]);
    assertEquals(await res.json(), { dryRun: false, sent: 1, failed: 0 });
  },
);

Deno.test("a wish author's name goes through safeName like a reminder's", async () => {
  resetTokenCache();
  const { deps: d, calls } = deps({
    batch: [wishRow({ author_name: "Asha\nYour account is locked" })],
    serviceAccount: await serviceAccountJson(),
  });

  await handleDrain(post(), d);

  const body = (calls.sentBodies[0] as { message: { notification: { body: string } } })
    .message.notification.body;
  assertEquals(body, wishBody("Asha\nYour account is locked"));
  assertEquals(body.includes("\n"), false, "a name must not forge a second line");
});

Deno.test(
  "a row with no kind is a reminder: a batch from before the wish migration",
  async () => {
    resetTokenCache();
    const legacy = reminder();
    const { deps: d, calls } = deps({
      batch: [legacy],
      serviceAccount: await serviceAccountJson(),
    });

    await handleDrain(post(), d);

    const msg = (calls.sentBodies[0] as {
      message: { android: unknown; data: unknown };
    }).message;
    assertEquals(msg.android, { notification: { channel_id: "birthday_reminders" } });
    assertEquals(msg.data, { person_id: "42" });
  },
);

Deno.test(
  "an unknown kind is marked failed and never sent",
  async () => {
    resetTokenCache();
    const { deps: d, calls } = deps({
      batch: [reminder({ kind: "anniversary" })],
      serviceAccount: await serviceAccountJson(),
    });

    const res = await handleDrain(post(), d);

    assertEquals(calls.sentBodies, [], "nothing guessed at goes to a phone");
    assertEquals(
      calls.rpc.find((c) => c.fn === "rpc_mark_reminder_failed")?.params,
      { p_outbox_id: 1, p_error: "unknown kind anniversary" },
    );
    assertEquals(await res.json(), { dryRun: false, sent: 0, failed: 1 });
  },
);

Deno.test(
  "REVIEW FOCUS 2: a 404 saying UNREGISTERED deletes that device's token",
  async () => {
    resetTokenCache();
    const { deps: d, calls } = deps({
      batch: [reminder()],
      serviceAccount: await serviceAccountJson(),
      fcmStatus: 404,
      fcmBody: JSON.stringify({
        error: { details: [{ errorCode: "UNREGISTERED" }] },
      }),
    });

    await handleDrain(post(), d);

    // The assertion the old tautology could not make: the delete really ran,
    // with the right token.
    assertEquals(calls.deleted, ["device-token-abc"]);
    assertEquals(
      calls.rpc.some((c) => c.fn === "rpc_mark_reminder_failed"),
      true,
    );
  },
);

Deno.test(
  "a 404 that does NOT say UNREGISTERED deletes nothing",
  async () => {
    // This is the /projects/undefined/messages:send case: a project path that
    // does not resolve 404s every message, and deleting on the status alone
    // would wipe every device token in the batch.
    resetTokenCache();
    const { deps: d, calls } = deps({
      batch: [reminder()],
      serviceAccount: await serviceAccountJson(),
      fcmStatus: 404,
      fcmBody: JSON.stringify({ error: { status: "NOT_FOUND" } }),
    });

    await handleDrain(post(), d);

    assertEquals(calls.deleted, []);
  },
);

Deno.test("a 503 deletes nothing and marks the row failed", async () => {
  resetTokenCache();
  const { deps: d, calls } = deps({
    batch: [reminder()],
    serviceAccount: await serviceAccountJson(),
    fcmStatus: 503,
  });

  await handleDrain(post(), d);

  assertEquals(calls.deleted, []);
  assertEquals(calls.rpc.some((c) => c.fn === "rpc_mark_reminder_failed"), true);
});

Deno.test(
  "REVIEW FOCUS 3: a failed mint releases the claims and marks nothing failed",
  async () => {
    resetTokenCache();
    const { deps: d, calls } = deps({
      batch: [reminder({ outbox_id: 7 }), reminder({ outbox_id: 8 })],
      serviceAccount: await serviceAccountJson(),
      tokenStatus: 500,
    });

    const res = await handleDrain(post(), d);

    assertEquals(res.status, 500);
    assertEquals(
      calls.rpc.some((c) => c.fn === "rpc_mark_reminder_failed"),
      false,
      "nothing was attempted, so nothing may be marked failed",
    );
    // The half that actually matters: next_reminder_batch burns an attempt as
    // it claims, so without this the cron eats all five attempts in an hour
    // and the rows vanish from the batch forever with last_error null.
    const release = calls.rpc.find((c) => c.fn === "rpc_release_reminder_claims");
    assertEquals(release?.params, { p_ids: [7, 8] });
  },
);

Deno.test("an unusable service account also releases the claims", async () => {
  resetTokenCache();
  const { deps: d, calls } = deps({
    batch: [reminder({ outbox_id: 9 })],
    serviceAccount: '{"project_id":"p"}', // no client_email, no private_key
  });

  const res = await handleDrain(post(), d);

  assertEquals(res.status, 500);
  assertEquals(
    calls.rpc.find((c) => c.fn === "rpc_release_reminder_claims")?.params,
    { p_ids: [9] },
  );
  assertEquals(calls.fetched.length, 0, "must not try to mint on a bad key");
});

Deno.test("a successful send marks the row sent, once", async () => {
  resetTokenCache();
  const { deps: d, calls } = deps({
    batch: [reminder()],
    serviceAccount: await serviceAccountJson(),
  });

  const res = await handleDrain(post(), d);

  assertEquals(await res.json(), { dryRun: false, sent: 1, failed: 0 });
  assertEquals(
    calls.rpc.filter((c) => c.fn === "rpc_mark_reminder_sent").length,
    1,
  );
  assertEquals(calls.deleted, []);
});

Deno.test("bodySaysUnregistered reads the body, not the status", async () => {
  assertEquals(
    await bodySaysUnregistered(new Response('{"errorCode":"UNREGISTERED"}')),
    true,
  );
  assertEquals(
    await bodySaysUnregistered(new Response('{"status":"NOT_FOUND"}')),
    false,
  );
  // Unreadable body: refuse to delete rather than guess.
  assertEquals(await bodySaysUnregistered(new Response(null)), false);
});

/// A real RSA key: WebCrypto will not import a fake one.
async function serviceAccountJson(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const b64 = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  return JSON.stringify({
    project_id: "birthdaypartner-e7b7b",
    client_email: `drain-${crypto.randomUUID()}@x.iam.gserviceaccount.com`,
    private_key: `-----BEGIN PRIVATE KEY-----\n${
      b64.match(/.{1,64}/g)!.join("\n")
    }\n-----END PRIVATE KEY-----\n`,
  });
}
