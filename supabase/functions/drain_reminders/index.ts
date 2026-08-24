// Drains private.notification_outbox to FCM. Everything about WHICH reminders
// are due lives in the database and is covered by 17_reminders.test.sql; this
// file is transport only.
//
// FCM_SERVER_KEY is absent until a Firebase project exists. Rather than fail,
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
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

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
  const fcmKey = Deno.env.get("FCM_SERVER_KEY");

  if (!fcmKey) {
    // Dry run still calls rpc_next_reminder_batch above, which already
    // claimed these rows for its 10-minute lease. We report what we would
    // have sent and stop, but we do NOT release the claim — so an immediate
    // second dry run (or a real drain) will see would_send/batch shrink
    // until the lease expires. That's expected, not a bug: the claim lives
    // in the database and exists to stop two drains racing on the same row.
    return new Response(
      JSON.stringify({ dryRun: true, would_send: batch.length, sent: 0, failed: 0 }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  let sent = 0;
  let failed = 0;

  for (const r of batch) {
    try {
      const res = await fetch("https://fcm.googleapis.com/fcm/send", {
        method: "POST",
        headers: {
          "Authorization": `key=${fcmKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          to: r.token,
          notification: { title: "Birthday reminder", body: body(r) },
        }),
      });

      if (!res.ok) {
        await admin.rpc("rpc_mark_reminder_failed", {
          p_outbox_id: r.outbox_id,
          p_error: `fcm ${res.status}`,
        });
        failed++;
        continue;
      }

      await admin.rpc("rpc_mark_reminder_sent", {
        p_outbox_id: r.outbox_id,
      });
      sent++;
    } catch (e) {
      await admin.rpc("rpc_mark_reminder_failed", {
        p_outbox_id: r.outbox_id,
        p_error: String(e).slice(0, 500),
      });
      failed++;
    }
  }

  return new Response(JSON.stringify({ sent, failed }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
