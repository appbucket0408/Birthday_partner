# Hosted deploy and real-device push test (2026-10-18)

Supersedes `2026-09-27-m1-phase2c-deploy-runbook.md`. That one covered the
drain alone; this covers the whole current backend (every migration through
`20261018000004`, all six Edge Functions, both notification kinds) and adds a
step-by-step real Android device test.

Every command here is run **by the project owner**, by hand. Nothing in this
repository runs them.

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
backdoor, typed instead of pushed. Also never run `db push --include-seed` or
`db reset --linked`: the seed files include `local_dev_otp.sql`, which makes
*every* number accept `123456`.

Hosted auth is configured in the dashboard, manually, with no test numbers.

---

## Part 1 — Deploy

### 1. Create and link the project

```bash
supabase login                                   # interactive, opens a browser
supabase projects create birthday-app --region ap-south-1   # or use the dashboard
supabase link --project-ref <ref>
```

Keep the database password you set; it is not recoverable and not stored here.

### 2. Push the schema

```bash
supabase migration list     # read-only: shows which migrations hosted lacks
supabase db push            # applies supabase/migrations/ only
```

There are 49 migrations; the latest is `20261018000006_notification_inbox.sql`.
The ones added since the last runbook, all applied by the same `db push`:

| Migration | What it adds |
|---|---|
| `20261018000001_wish_photos` | Photo on a wish; the private `wish_photos` bucket |
| `20261018000002_public_feed` | `feed_page()`: the feed is public among members |
| `20261018000003_wish_notifications` | `kind = 'wish'` in the outbox, the enqueue trigger on `wishes`, `profiles.wish_notifications_enabled`, the extended batch |
| `20261018000004_smoke_push` | `rpc_queue_test_push()`, service-role only, for `smoke-push.sh` |
| `20261018000005_phone_pepper_required` | Removes the public placeholder pepper; hashing refuses to run until step 3 is done |
| `20261018000006_notification_inbox` | The in-app Notifications screen: `my_notifications()`, `my_unseen_notification_count()`, `mark_notifications_seen()` |

Verify in the SQL editor:

```sql
select version from supabase_migrations.schema_migrations
order by version desc limit 6;              -- ends 20261018000006

select * from private.drain_config;         -- exists, EMPTY (step 6 fills it)

select jobname, schedule from cron.job order by jobname;
-- birthday-reminder-fanout  0 3 * * *
-- reminder-drain            */10 * * * *
-- (plus the gift expiry job)
```

### 3. Set the phone-hash pepper — BEFORE anyone signs up

Every phone number is stored only as an HMAC keyed by `private.config`'s
`phone_pepper`. After `db push` a fresh project has **no** pepper: migration
`20261018000005` removes the old public placeholder, and hashing refuses to
run without a real value. Skip this step and nothing leaks; the first
sign-up simply fails at its last step (`claim_profile` errors, and the
database logs `phone_pepper is not configured`).

Set it once. Changing it **after** real sign-ups orphans every stored phone
hash: contacts stop matching members, and nothing errors.

```bash
openssl rand -hex 32 > ~/secrets/candlewish-phone-pepper   # keep it with your other secrets
```

```sql
select count(*) from public.people;          -- must be 0 when you do this

insert into private.config (key, value)
values ('phone_pepper', '<contents of ~/secrets/candlewish-phone-pepper>')
on conflict (key) do update set value = excluded.value;
```

If `db push` printed a **WARNING** that the placeholder was left in place,
this project already hashed real data with the public key. Stop and plan a
deliberate re-key; do not just overwrite it, or every stored hash is
orphaned.

### 4. Set the function secrets

Firebase Console → project **`birthdaypartner-e7b7b`** → Project Settings →
Service Accounts → **Generate new private key**. It must be this project:
it is the one `android/app/google-services.json` points at. A key from any
other Firebase project makes every send fail with 403/404
(`SENDER_ID_MISMATCH`), and nothing looks wrong until a phone stays silent.

Save the key **outside** this repository. It can send push to every
installation of the app; never commit it, print it, or paste it into a chat.

```bash
supabase secrets set \
  FCM_SERVICE_ACCOUNT="$(cat ~/secrets/birthdaypartner-service-account.json)" \
  DRAIN_SECRET="$(openssl rand -hex 32 | tee ~/secrets/candlewish-drain-secret)"
```

Step 6 needs the identical `DRAIN_SECRET`, which is why it is also written to
a file. There is no `FCM_PROJECT_ID`: it is the `project_id` inside the JSON.

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` and
`SUPABASE_DB_URL` are injected into hosted functions automatically; do not
set them.

### 5. Deploy all six Edge Functions

```bash
supabase functions deploy claim_profile
supabase functions deploy resolve_contacts
supabase functions deploy add_celebrations
supabase functions deploy delete_account
supabase functions deploy confirm
supabase functions deploy drain_reminders
```

`functions deploy` reads `config.toml`'s `[functions.*]` blocks (a functions
setting, not `[auth.*]`, so no `config push` is involved):

- `confirm` and `drain_reminders` deploy with **JWT verification off**.
  `drain_reminders` is called by the cron, which sends only `x-drain-secret`;
  with JWT verification on, every cron call was refused by the gateway before
  the handler ran, and nothing ever drained by itself. The handler's
  `DRAIN_SECRET` check is its guard.
- The other four keep JWT verification on.

Confirm in Dashboard → Edge Functions that `drain_reminders` shows
**"Enforce JWT" off**.

### 6. Point the cron at the drain

SQL editor, with the ref and the **same** secret as step 4:

```sql
insert into private.drain_config (function_url, drain_secret)
values ('https://<ref>.supabase.co/functions/v1/drain_reminders',
        '<contents of ~/secrets/candlewish-drain-secret>')
on conflict (id) do update
  set function_url = excluded.function_url,
      drain_secret = excluded.drain_secret;
```

Until this row exists the cron is a deliberate no-op, not a failure.

### 7. Verify the drain — in the right place

```sql
-- NOT cron.job_run_details. net.http_post queues asynchronously and never
-- raises, so the cron reports success even when the URL is wrong or the
-- function is dead. The response table is the only honest record.
select id, status_code, content::text, created
from net._http_response
order by id desc
limit 5;
```

Within ten minutes you should see `200` with a body like
`{"dryRun":false,"sent":0,"failed":0}`. Anything else: see
[Diagnosing](#diagnosing) below.

### 8. Confirm auth is still closed

```bash
./supabase/check-no-config-push.sh        # must print PASS
grep -n 'enable_confirmations' supabase/config.toml
```

In the dashboard: Auth → Providers → Phone has **no** test numbers.

---

## Part 2 — Real Android device, end to end

### What is possible today, and what is blocked

Hosted has **no SMS provider**, and phone OTP is the app's front door:

| | Today |
|---|---|
| Sign in by phone OTP | ❌ Blocked: no SMS is ever sent. |
| Sign up a brand-new account by email | ❌ Blocked: setup then insists on verifying a phone by SMS. |
| Sign in by email to an account **pre-created with a confirmed phone** | ✅ Works. Setup sees the verified phone and skips the SMS step. |
| Push registration, reminders, wish notifications, tap routing | ✅ Fully testable once signed in. |

So the device test uses one or two accounts you pre-create as admin.

#### One-time dashboard setup for email sign-in

1. Auth → Providers → **Email**: enabled. You can leave "Allow new users to
   sign up" off; these accounts already exist.
2. Auth → Email Templates → **Magic Link** *and* **Confirm signup**: replace
   the body with the contents of `supabase/templates/email_otp.html`. The app
   asks for a 6-digit code, and hosted's default templates send a link
   instead. (Locally `config.toml` sets this; hosted needs it by hand.)
3. Hosted's built-in email only delivers to **members of your Supabase
   organization**, a few per hour. Use your own address(es), or configure
   custom SMTP.

#### Pre-create the test account(s)

Use a phone number **you own**: it becomes the account's identity, and
anyone importing that number as a contact will match this account.

```bash
SUPABASE_URL=https://<ref>.supabase.co
read -rs SERVICE_ROLE_KEY     # paste the service-role key; not echoed, not in history

curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","email_confirm":true,
       "phone":"91XXXXXXXXXX","phone_confirm":true}'
```

For the wish test you also want a second account (the **author**). It needs
no phone or device; create it the same way with another email and number.

### Step 1 — Build and install against hosted

```bash
fvm flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<the anon / publishable key>
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug key for now
(`android/app/build.gradle.kts`), which is fine for a device test. The anon
key is designed to ship in the app; the service-role key must never be a
`--dart-define`.

### Step 2 — Sign in

1. Open the app → **email** → your address → enter the 6-digit code.
2. Profile setup: name, handle, birthday. There should be **no** phone step.
   If one appears, the account was not created with `phone_confirm: true`.
3. You land on the Dashboard. Android asks for notification permission:
   **Allow**. (Refuse it twice and Android 13+ never asks again; only
   Settings → Apps → Candlewish → Notifications can undo that.)

### Step 3 — Confirm the device registered

```sql
select p.handle, d.platform, d.last_seen_at
from public.device_tokens d
join public.profiles p on p.id = d.profile_id
order by d.last_seen_at desc
limit 5;
```

One `android` row for your handle. None: see [Diagnosing](#diagnosing).

Note your profile id for the next steps:

```sql
select id, handle from public.profiles where handle = '<your handle>';
```

### Step 4 — Force a birthday reminder

Easiest, using the script (it never prints secrets):

```bash
read -rs SERVICE_ROLE_KEY; export SERVICE_ROLE_KEY
export SUPABASE_URL=https://<ref>.supabase.co
export DRAIN_SECRET="$(cat ~/secrets/candlewish-drain-secret)"
./supabase/functions/smoke-push.sh <your-profile-uuid> reminder
```

Expected: `queued outbox row N`, then `drain HTTP 200:
{"dryRun":false,"sent":1,"failed":0}`, and the notification arrives:
**"Candlewish 🎂 / It's <your name>'s birthday today."**

Or by hand in the SQL editor:

```sql
select private.queue_test_push('<your-profile-uuid>', 'reminder');
select private.trigger_drain();     -- or wait for the */10 cron
```

Or through the real fan-out, which also exercises the date matching. Make
the author account's birthday tomorrow and celebrate them:

```sql
select private.claim_person('<author-profile-uuid>', '+91XXXXXXXXXX');  -- the author's number
update public.profiles
set birth_month = extract(month from current_date + 1)::smallint,
    birth_day   = extract(day   from current_date + 1)::smallint
where id = '<author-profile-uuid>';
insert into public.celebrations (celebrator_profile_id, person_id, source)
select '<your-profile-uuid>', p.id, 'contacts'
from public.people p where p.profile_id = '<author-profile-uuid>'
on conflict do nothing;
select private.enqueue_reminders();   -- returns 1: a T-1 reminder queued
select private.trigger_drain();
```

→ **"<author>'s birthday is tomorrow."**

### Step 5 — Force a wish notification

A wish notification needs a real wish, posted about you by someone else.
With the author account claimed (step 4's `claim_person`), and celebrating
you:

```sql
insert into public.celebrations (celebrator_profile_id, person_id, source)
select '<author-profile-uuid>', p.id, 'contacts'
from public.people p where p.profile_id = '<your-profile-uuid>'
on conflict do nothing;

insert into public.wishes (author_profile_id, subject_person_id, body, occasion_year)
select '<author-profile-uuid>', p.id, 'Happy birthday from the device test!',
       extract(year from current_date)::int
from public.people p where p.profile_id = '<your-profile-uuid>';

-- the trigger queued exactly one row:
select id, kind, wish_id, attempts, sent_at
from private.notification_outbox
where kind = 'wish' order by id desc limit 3;

select private.trigger_drain();
```

→ **"Candlewish 🎂 / <author> left you a birthday wish."**

To send it again later: `./supabase/functions/smoke-push.sh <your-profile-uuid> wish`.

To check the switch: Settings → **New wishes** off, post another wish (a
different `occasion_year`, since it's one wish per person per year), and
confirm no new `kind = 'wish'` row appears.

### Step 6 — What you should see

Run steps 4 and 5 once in each state:

| App state | Expected |
|---|---|
| **Background** (Home pressed, app in recents) | System notification. Status bar shows the white candle, not a white square; the shade tints it coral. Title "Candlewish 🎂". |
| **Foreground** (app open on screen) | A heads-up banner with the same icon, title and text, shown by the app itself. |
| **Killed** (swiped out of recents) | System notification, same as background. |

Tapping it, in every state:

| Kind | Opens |
|---|---|
| Reminder | That person's page (yours, for the smoke reminder). From killed, the app starts, passes the splash, then lands there. |
| Wish | **Your own wall, with that wish opened on top.** Back returns to the wall. If the wish was deleted meanwhile, you land on the wall alone. |

Then Settings → Apps → Candlewish → Notifications should list two channels,
**Birthday reminders** and **New wishes**, each switchable on its own. A
**Miscellaneous** channel appears only on a device that ran an older build;
it goes away with a reinstall.

OEM caveat: Xiaomi, Oppo, Vivo and some Samsung battery modes stop FCM for
killed apps, and Settings → **Force stop** blocks every push until the app is
opened again. If only the killed state fails, retest on a Pixel or with
battery optimisation off for Candlewish before suspecting the code.

### Diagnosing

Start at the two honest records:

```sql
-- What the drain returned to the cron:
select id, status_code, content::text, created
from net._http_response order by id desc limit 5;

-- What happened to each notification:
select id, kind, recipient_profile_id, attempts, claimed_at, sent_at, last_error
from private.notification_outbox order by id desc limit 20;
```

| Symptom | Meaning | Fix |
|---|---|---|
| `401` `{"error":"not authorised"}` | The handler refused: `drain_config.drain_secret` ≠ the `DRAIN_SECRET` secret | Re-run step 6 with the exact secret |
| `401` `{"msg":"…authorization header…"}` | The **gateway** refused: `drain_reminders` deployed with JWT verification on | Redeploy (step 5) from this repo, or turn "Enforce JWT" off in the dashboard |
| `404` "Function not found" | Wrong URL in `drain_config`, or not deployed | Check the ref in step 6; `supabase functions deploy drain_reminders` |
| `200` `{"dryRun":true,…}` | `FCM_SERVICE_ACCOUNT` not set | Step 4 |
| Sign-up fails at the last step; logs say `phone_pepper is not configured` | Step 3 was skipped. Nothing was hashed with a weak key | Do step 3, then retry the sign-up |
| `500` "service account is unusable" / "auth failed" | Bad JSON, or the key was revoked. The claims are given back, so nothing is lost | New key, step 4 |
| No rows in `net._http_response` | The cron has not fired, or `drain_config` is empty (a silent no-op) | Wait 10 min; check `select * from private.drain_config` and `cron.job` |
| `last_error = 'fcm 404'` plus "deleted unregistered device token" in the function logs | The phone's token was revoked (reinstall, cleared data). The row was deleted on purpose | Open the app; reaching the Dashboard re-registers |
| `last_error = 'fcm 403'` / `'fcm 401'` | The key is from a different Firebase project than the app, or lacks the messaging role | Use a key from `birthdaypartner-e7b7b` |
| `attempts = 5`, `sent_at` null | Gave up after five tries; see `last_error` | Fix the cause, then `update private.notification_outbox set attempts = 0, claimed_at = null where id = <id>;` |
| Outbox row exists but is never claimed | The recipient has no `device_tokens` row | Step 3 |
| No `device_tokens` row | Permission refused, the app never reached the Dashboard, or registration failed | Allow notifications in Android settings and reopen the app; check logcat for `birthday` |
| No `kind = 'wish'` row after a wish | Expected when: you wrote it yourself, the subject never claimed a profile, **New wishes** is off, you blocked the author, or it's a cake post | — |
| Arrives, but as a white square | Device runs a build from before the notification icon | Reinstall the current build |

Function logs: Dashboard → Edge Functions → `drain_reminders` → Logs. They
record counts and errors, never message text or tokens.
