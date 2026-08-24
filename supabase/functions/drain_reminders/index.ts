// Drains private.notification_outbox to FCM. Everything about WHICH reminders
// are due lives in the database and is covered by 17_reminders.test.sql; this
// file is transport only.
//
// FCM credentials are absent until a Firebase project exists. Rather than fail,
// the function runs in dry-run mode: it reports what it would have sent and
// leaves the rows unsent, so the pipeline is exercisable before credentials.
import { createClient } from "jsr:@supabase/supabase-js@2";

type Reminder = {
  outbox_id: number;
  token: string;
  platform: string;
  subject_name: string;
  offset_days: number;
  occasion_date: string;
};

function body(r: Reminder): string {
  if (r.offset_days === 0) return `It's ${r.subject_name}'s birthday today.`;
  if (r.offset_days === 1) return `${r.subject_name}'s birthday is tomorrow.`;
  return `${r.subject_name}'s birthday is in ${r.offset_days} days.`;
}

Deno.serve(async (): Promise<Response> => {
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
  // `key=SERVER_KEY` header was shut down by Google in 2024 and no longer accepts
  // traffic — do not reintroduce it.
  //
  // PHASE 2 MUST REPLACE FCM_ACCESS_TOKEN. v1 authenticates with a short-lived
  // OAuth2 bearer token minted from a service-account key (JWT assertion exchanged
  // at oauth2.googleapis.com/token), and those tokens expire hourly. A static env
  // var is a deliberate placeholder so this path has the right shape and can be
  // exercised with a stub — it is not a deployment strategy.
  const fcmProject = Deno.env.get("FCM_PROJECT_ID");
  const fcmToken = Deno.env.get("FCM_ACCESS_TOKEN");

  if (!fcmProject || !fcmToken) {
    // Dry run. Note the rows in this batch are already CLAIMED for their
    // 10-minute lease — next_reminder_batch claims as it reads — so an immediate
    // second call reports zero. Expected, not a bug.
    return new Response(
      JSON.stringify({ dryRun: true, would_send: batch.length, sent: 0, failed: 0 }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
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
        `https://fcm.googleapis.com/v1/projects/${fcmProject}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${fcmToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: r.token,
              notification: { title: "Birthday reminder", body: body(r) },
            },
          }),
        },
      );

      if (!res.ok) {
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
