# M1 Phase 2c — hosted deploy runbook

> **Superseded** by `2026-10-18-push-deploy-runbook.md`, which covers the
> current backend (every migration, all six functions, the phone-hash pepper,
> the drain's JWT setting) and a real-device test. Kept for history; do not
> follow this one.

**Spec:** `docs/superpowers/specs/2026-09-27-m1-phase2c-push-design.md`

Run in order. Steps 1–3 need credentials only the project owner has.

## ⛔ DO NOT RUN `supabase config push`

Not once, not with `--dry-run`, not "just to see the diff".

`supabase/config.toml` carries `[auth.sms.test_otp]`: real-format Indian
phone numbers whose OTP is the hardcoded string `123456`. `db push` does not
touch that file. **`config push` applies it**, which would place every one of
them on an internet-facing GoTrue as a working backdoor. This project has
already reproduced two account-takeover bugs on this exact surface.

How many there are is asserted by `supabase/check-no-config-push.sh`, which
also fails if the count changes without that script changing in the same
commit. Do not restate the number here; it drifted once already.

The same hazard applies by hand: **do not** add test phone numbers in the
hosted dashboard's Auth → Providers → Phone → Test OTP panel. It is the same
backdoor, typed instead of pushed.

Hosted auth is configured in the dashboard, manually, with no test numbers.
`supabase/check-no-config-push.sh` guards the repo against a scripted
invocation; nothing can guard your shell.

## 1. Create the hosted project

Either create it at supabase.com/dashboard and note the project ref, or:

```bash
supabase login                      # interactive, opens a browser
supabase projects create birthday-app --region ap-south-1
```

The CLI prompts for a database password. Set one you keep — it is not
recoverable, and it is not stored in this repo.

## 2. Link and push the schema

```bash
supabase link --project-ref <ref>
supabase db push
```

`db push` applies `supabase/migrations/` only. Confirm afterwards that the
two new migrations landed:

```sql
select * from private.drain_config;               -- exists, EMPTY
select jobname, schedule from cron.job;           -- reminder-drain, */10 * * * *
```

## 3. Set the function secrets

The FCM service-account key is generated at Firebase Console → Project
Settings → Service Accounts → **Generate new private key**. Save it outside
this repository. It can send push to every installation of this app; it is
never committed, never printed, and never pasted into a chat.

```bash
supabase secrets set \
  FCM_SERVICE_ACCOUNT="$(cat ~/secrets/birthdaypartner-service-account.json)" \
  DRAIN_SECRET="$(openssl rand -hex 32)"
```

Keep the `DRAIN_SECRET` value — step 5 needs the identical string.

There is no `FCM_PROJECT_ID`. The project id is the `project_id` field
inside the service-account JSON; two sources for one value is two things to
drift apart.

## 4. Deploy the function

```bash
supabase functions deploy drain_reminders
```

## 5. Point the cron at it

Run in the SQL editor, substituting the ref and the **same** secret from
step 3:

```sql
insert into private.drain_config (function_url, drain_secret)
values ('https://<ref>.supabase.co/functions/v1/drain_reminders',
        '<the DRAIN_SECRET value>')
on conflict (id) do update
  set function_url = excluded.function_url,
      drain_secret = excluded.drain_secret;
```

Until this row exists the cron is a deliberate no-op, not a failure.

## 6. Verify delivery — and look in the right place

```sql
-- NOT cron.job_run_details. net.http_post queues asynchronously and never
-- raises, so the cron reports success even when the URL is wrong or the
-- function is dead. The response table is the only honest record.
select id, status_code, created
from net._http_response
order by id desc
limit 5;
```

A `401` means `drain_secret` does not match the `DRAIN_SECRET` secret. A
`404` means the function URL is wrong. No rows at all means the cron has not
fired yet — it runs at `*/10`.

## 7. Confirm auth is still closed

```bash
grep -n 'enable_confirmations' supabase/config.toml   # must be true
./supabase/check-no-config-push.sh                    # must print PASS
                                                      # (checks the command AND the count)
```

Then, in the hosted dashboard, confirm Auth → Providers → Phone has **no**
test numbers configured, and that email signup is disabled.

## What this runbook cannot give you

A real device cannot sign in against hosted: there is no SMS provider, and
phone OTP is the app's only front door. Push registration is therefore
verified **locally over LAN**, and the hosted deploy is verified with a
`device_tokens` row seeded by the service role. The seam between those two
halves is exercised by nothing. See spec §3.1 and §9.
