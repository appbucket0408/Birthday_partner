// The drain's logic, with every outside dependency injected. Deliberately
// separate from index.ts: importing index.ts executes Deno.serve and binds a
// port, so a test that imported it would start a server. Guarding that with
// `import.meta.main` would be the other option, and a worse one -- if the
// edge runtime ever loaded this module through a wrapper, the guard would be
// false and the function would silently stop serving in production.
// Drains private.notification_outbox to FCM. Everything about WHICH reminders
// are due lives in the database and is covered by 17_reminders.test.sql; this
// file is transport only.
//
// FCM credentials are absent until a Firebase project exists. Rather than fail,
// the function runs in dry-run mode: it reports what it would have sent and
// leaves the rows unsent, so the pipeline is exercisable before credentials.
import {
  accessToken,
  invalidateToken,
  isDeadToken,
  isRejectedBearer,
  reminderBody,
  type ServiceAccount,
  wishBody,
  celebrationBody,
  joinedBody,
  welcomeBody,
  wallBody,
} from "./fcm.ts";

/// One row of rpc_next_reminder_batch. The outbox carries two kinds
/// (20261018000003): a birthday 'reminder', and a 'wish' someone left on the
/// recipient's wall. `kind` is optional here on purpose: a batch from a
/// database that predates that migration has no such column, and every row
/// it returns is a reminder.
type Reminder = {
  outbox_id: number;
  token: string;
  platform: string;
  subject_name: string;
  subject_person_id: number;
  offset_days: number | null;
  occasion_date: string | null;
  kind?: string;
  author_name?: string | null;
  wish_id?: number | null;
  subject_count?: number | null;
};

type Outgoing = {
  body: string;
  channel: string;
  data: Record<string, string>;
};

/// What to send for one row, or null for a kind this drain does not know.
/// Unknown is refused rather than guessed at: a row from a newer schema
/// rendered as a reminder would tell someone a birthday is "in null days".
///
/// Each kind has its own Android channel, created by the app at startup
/// (PushRepositoryImpl), so a user can silence wishes in the OS settings
/// without losing birthday reminders -- the same split as the two Settings
/// switches. `data` carries only ids; the app validates and rebuilds the
/// route from them (routeForPayload).
export function outgoingFor(r: Reminder): Outgoing | null {
  const kind = r.kind ?? "reminder";
  if (kind === "reminder" && r.offset_days !== null) {
    return {
      body: reminderBody(r.subject_name, r.offset_days),
      channel: "birthday_reminders",
      data: { person_id: String(r.subject_person_id) },
    };
  }
  if (kind === "wish" && r.wish_id != null) {
    return {
      body: wishBody(r.author_name ?? null),
      channel: "wishes",
      // person_id is the recipient's OWN person: the wall the wish is on.
      data: {
        person_id: String(r.subject_person_id),
        wish_id: String(r.wish_id),
      },
    };
  }
  if (kind === "celebration") {
    return {
      body: celebrationBody(r.subject_name),
      channel: "wishes",
      // person_id is the celebrator: their page offers Celebrate back.
      data: { person_id: String(r.subject_person_id) },
    };
  }
  if (kind === "joined" && r.occasion_date) {
    return {
      body: joinedBody(r.subject_name, r.occasion_date),
      channel: "birthday_reminders",
      data: { person_id: String(r.subject_person_id) },
    };
  }
  // screen: the app routes these to a tab, not the person page.
  if (kind === "welcome" && r.subject_count) {
    return {
      body: welcomeBody(r.subject_count),
      channel: "wishes",
      data: { person_id: String(r.subject_person_id), screen: "celebrates" },
    };
  }
  if (kind === "wall") {
    return {
      body: wallBody(),
      channel: "birthday_reminders",
      data: { person_id: String(r.subject_person_id), screen: "dashboard" },
    };
  }
  return null;
}


/// FCM v1 reports an unregistered token as UNREGISTERED (or
/// INVALID_ARGUMENT for a malformed one) in the response body. The 404
/// status alone is ambiguous: a project path that does not resolve returns
/// 404 for every message in the batch, and acting on the status alone would
/// delete every device token in it.
export async function bodySaysUnregistered(res: Response): Promise<boolean> {
  try {
    const text = await res.clone().text();
    return /UNREGISTERED|INVALID_ARGUMENT/.test(text);
  } catch (e) {
    // Unreadable body: refuse to delete. A token kept alive in error costs
    // wasted sends; a token deleted in error costs the user every reminder
    // until they next open the app.
    console.error("could not read FCM error body", e);
    return false;
  }
}

/// What the handler needs from the outside world. Injected so the whole
/// drain -- the secret guard, the dead-token delete, the send accounting --
/// is testable without a server, a database or Google. Before this existed
/// index.ts had NO tests at all: the dead-token branch was "covered" by
/// isDeadToken(404) === true, a predicate over an integer literal that
/// cannot fail if the delete call is missing, misspelled, or unreachable.
export type DrainDeps = {
  env: (k: string) => string | undefined;
  admin: {
    rpc: (fn: string, params: Record<string, unknown>) => Promise<
      { data?: unknown; error?: { message: string } | null }
    >;
    deleteDeviceToken: (token: string) => Promise<{ error?: { message: string } | null }>;
  };
  fetchImpl: typeof fetch;
  now: () => number;
};

export async function handleDrain(
  req: Request,
  deps: DrainDeps,
): Promise<Response> {
  // This is a machine endpoint — cron calls it, never a user. The publishable
  // key is a valid JWT, so JWT verification alone would let anyone who unpacks
  // the app trigger a drain: burning claim leases now, and FCM quota later.
  const expected = deps.env("DRAIN_SECRET");
  if (!expected || req.headers.get("x-drain-secret") !== expected) {
    return new Response(JSON.stringify({ error: "not authorised" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const url = deps.env("SUPABASE_URL");
  const serviceKey = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return new Response(JSON.stringify({ error: "function is misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
  const admin = deps.admin;

  // R2: public wrapper, not .schema("private") — see 20260824000006.
  // NOTE: this must stay a POST (supabase-js .rpc() default). The underlying
  // private.next_reminder_batch is data-modifying — it claims the rows it
  // returns with a 10-minute lease (stamping claimed_at) so two concurrent
  // drains can't double-send. A GET would run in a read-only transaction and
  // fail at RUNTIME, not at deploy, so never add `{ get: true }` here.
  const { data, error } = await admin
    .rpc("rpc_next_reminder_batch", { p_limit: 100 });

  if (error) {
    console.error("next_reminder_batch failed", error.message);
    return new Response(JSON.stringify({ error: "batch read failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const batch = (data ?? []) as Reminder[];

  // FCM HTTP v1. The legacy fcm.googleapis.com/fcm/send endpoint with a
  // `key=SERVER_KEY` header was shut down by Google in 2024 and no longer
  // accepts traffic -- do not reintroduce it.
  //
  // One secret, holding the service-account JSON verbatim. There is no
  // separate FCM_PROJECT_ID: the project id is the file's own `project_id`,
  // and two sources for one value is two things to drift apart.
  const saRaw = deps.env("FCM_SERVICE_ACCOUNT");

  if (!saRaw) {
    // Dry run. Note the rows in this batch are already CLAIMED for their
    // 10-minute lease -- next_reminder_batch claims as it reads -- so an
    // immediate second call reports zero. Expected, not a bug.
    return new Response(
      JSON.stringify({ dryRun: true, would_send: batch.length, sent: 0, failed: 0 }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  // Abandoning the batch is NOT free. next_reminder_batch burns an attempt
  // as it claims, so simply returning 500 leaves every row one attempt
  // poorer; the cron re-claims ten minutes later and within about an hour
  // they all cross `attempts < 5` and vanish from the batch forever, with
  // last_error null because nothing was ever marked failed. Give the
  // attempts back on every path that gives up before trying to send.
  const ids = batch.map((r) => r.outbox_id);
  async function abandon(reason: string, e: unknown): Promise<Response> {
    console.error(reason, e);
    if (ids.length > 0) {
      const { error: relError } = await admin.rpc("rpc_release_reminder_claims", {
        p_ids: ids,
      });
      if (relError) {
        console.error("release_reminder_claims failed", relError.message);
      }
    }
    return new Response(JSON.stringify({ error: reason }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  let sa: ServiceAccount;
  try {
    const parsed = JSON.parse(saRaw) as Partial<ServiceAccount>;
    // Validated field by field, not trusted. `project_id` is interpolated
    // straight into the FCM URL: if it were undefined the request would go to
    // /v1/projects/undefined/messages:send, every message would 404, and the
    // 404 branch below would delete EVERY device token in the batch.
    for (const k of ["project_id", "client_email", "private_key"] as const) {
      if (typeof parsed[k] !== "string" || parsed[k]!.length === 0) {
        throw new Error(`service account is missing ${k}`);
      }
    }
    sa = parsed as ServiceAccount;
  } catch (e) {
    return await abandon("service account is unusable", e);
  }

  // Minted ONCE for the batch, outside the loop. A failure here is NOT a
  // per-message failure: no message was attempted, so nothing may be marked
  // failed -- and the claims are released so the attempt is not burned.
  let bearer: string;
  try {
    bearer = await accessToken(sa, deps.now(), deps.fetchImpl);
  } catch (e) {
    return await abandon("auth failed", e);
  }

  let sent = 0;
  let failed = 0;

  for (const r of batch) {
    // One reminder yields one row per registered device. mark_reminder_sent sets
    // sent_at on the shared outbox row, and next_reminder_batch filters on
    // `sent_at is null` — so once ANY device succeeds, a device that failed in the
    // same batch is never retried. Accepted at pilot scale; the real fix is
    // per-device delivery tracking.
    const outgoing = outgoingFor(r);
    if (outgoing === null) {
      const { error: failError } = await admin.rpc("rpc_mark_reminder_failed", {
        p_outbox_id: r.outbox_id,
        p_error: `unknown kind ${r.kind}`,
      });
      if (failError) {
        console.error("mark_reminder_failed failed", r.outbox_id, failError.message);
      }
      failed++;
      continue;
    }

    try {
      const res = await deps.fetchImpl(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${bearer}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: r.token,
              notification: {
                title: "Candlewish 🎂",
                body: outgoing.body,
              },
              // The app creates both channels at startup
              // (PushRepositoryImpl). Without one Android files a background
              // notification under FCM's generic "Miscellaneous" channel,
              // which the user can only silence wholesale. The manifest's
              // default_notification_channel_id is birthday_reminders, the
              // fallback for an app build that predates the wishes channel.
              android: {
                notification: { channel_id: outgoing.channel },
              },
              data: outgoing.data,
            },
          }),
        },
      );

      if (!res.ok) {
        // The CREDENTIAL was rejected, not the device. Drop the cached
        // bearer so the next drain mints a fresh one: without this a key
        // revoked mid-life keeps being served from cache for up to ~55
        // minutes while every message fails. Never delete the device token
        // here -- the device is fine and we are not.
        if (isRejectedBearer(res.status)) {
          invalidateToken(sa);
        }
        // A 404 is FCM's UNREGISTERED. Google's own guidance is to key on
        // the response body's errorCode, not the status line, because a 404
        // is also what a project path that does not resolve returns -- so
        // the body is checked before anything is deleted. sa.project_id is
        // validated non-empty above, which closes the /projects/undefined/
        // case that would otherwise 404 every message and delete every
        // token in the batch.
        if (isDeadToken(res.status) && await bodySaysUnregistered(res)) {
          // UNREGISTERED: the OS revoked this token. Deleting the row is the
          // only thing that stops every future reminder for this user being
          // claimed and burned against a corpse. The user re-registers on
          // next launch -- registerThisDevice runs on every timeline arrival.
          const { error: delError } = await admin.deleteDeviceToken(r.token);
          if (delError) {
            console.error("stale token delete failed", delError.message);
          } else {
            // Deleting a user's device token is consequential and was
            // previously silent unless it FAILED. Log every removal.
            console.error("deleted unregistered device token", r.outbox_id);
          }
        }
        const { error: failError } = await admin.rpc("rpc_mark_reminder_failed", {
          p_outbox_id: r.outbox_id,
          p_error: `fcm ${res.status}`,
        });
        if (failError) {
          console.error("mark_reminder_failed failed", r.outbox_id, failError.message);
        }
        failed++;
        continue;
      }

      const { error: sentError } = await admin.rpc("rpc_mark_reminder_sent", {
        p_outbox_id: r.outbox_id,
      });
      if (sentError) {
        // The push went out but we could not record it. Counting this as failed
        // would be a lie in the other direction; surface it instead.
        console.error("mark_reminder_sent failed", r.outbox_id, sentError.message);
        failed++;
        continue;
      }
      sent++;
    } catch (e) {
      const { error: failError } = await admin.rpc("rpc_mark_reminder_failed", {
        p_outbox_id: r.outbox_id,
        p_error: String(e).slice(0, 500),
      });
      if (failError) {
        console.error("mark_reminder_failed failed", r.outbox_id, failError.message);
      }
      failed++;
    }
  }

  return new Response(JSON.stringify({ dryRun: false, sent, failed }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
