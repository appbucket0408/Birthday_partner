// Drains private.notification_outbox to FCM. Everything about WHICH reminders
// are due lives in the database and is covered by 17_reminders.test.sql; this
// file is transport only.
//
// FCM credentials are absent until a Firebase project exists. Rather than fail,
// the function runs in dry-run mode: it reports what it would have sent and
// leaves the rows unsent, so the pipeline is exercisable before credentials.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  accessToken,
  isDeadToken,
  reminderBody,
  type ServiceAccount,
} from "./fcm.ts";

type Reminder = {
  outbox_id: number;
  token: string;
  platform: string;
  subject_name: string;
  subject_person_id: number;
  offset_days: number;
  occasion_date: string;
};


Deno.serve(async (req: Request): Promise<Response> => {
  // This is a machine endpoint — cron calls it, never a user. The publishable
  // key is a valid JWT, so JWT verification alone would let anyone who unpacks
  // the app trigger a drain: burning claim leases now, and FCM quota later.
  const expected = Deno.env.get("DRAIN_SECRET");
  if (!expected || req.headers.get("x-drain-secret") !== expected) {
    return new Response(JSON.stringify({ error: "not authorised" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return new Response(JSON.stringify({ error: "function is misconfigured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
  const admin = createClient(url, serviceKey);

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
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");

  if (!saRaw) {
    // Dry run. Note the rows in this batch are already CLAIMED for their
    // 10-minute lease -- next_reminder_batch claims as it reads -- so an
    // immediate second call reports zero. Expected, not a bug.
    return new Response(
      JSON.stringify({ dryRun: true, would_send: batch.length, sent: 0, failed: 0 }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  const sa = JSON.parse(saRaw) as ServiceAccount;

  // Minted ONCE for the batch, outside the loop. A failure here is NOT a
  // per-message failure: no message was attempted, so nothing may be marked
  // failed. Returning 500 leaves the claim lease to expire in ten minutes
  // and the next drain picks the rows up untouched, with `attempts` intact.
  let bearer: string;
  try {
    bearer = await accessToken(sa, Date.now());
  } catch (e) {
    console.error("fcm token mint failed", e);
    return new Response(JSON.stringify({ error: "auth failed" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  let sent = 0;
  let failed = 0;

  for (const r of batch) {
    // One reminder yields one row per registered device. mark_reminder_sent sets
    // sent_at on the shared outbox row, and next_reminder_batch filters on
    // `sent_at is null` — so once ANY device succeeds, a device that failed in the
    // same batch is never retried. Accepted at pilot scale; the real fix is
    // per-device delivery tracking.
    try {
      const res = await fetch(
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
                title: "Birthday reminder",
                body: reminderBody(r.subject_name, r.offset_days),
              },
              data: { person_id: String(r.subject_person_id) },
            },
          }),
        },
      );

      if (!res.ok) {
        if (isDeadToken(res.status)) {
          // UNREGISTERED: the OS revoked this token. Deleting the row is the
          // only thing that stops every future reminder for this user being
          // claimed and burned against a corpse. The user re-registers on
          // next launch -- registerThisDevice runs on every timeline arrival.
          const { error: delError } = await admin
            .from("device_tokens").delete().eq("token", r.token);
          if (delError) {
            console.error("stale token delete failed", delError.message);
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
});
