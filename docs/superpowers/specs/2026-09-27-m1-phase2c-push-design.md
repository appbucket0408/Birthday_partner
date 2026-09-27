# M1 Phase 2c — push, the half that can be built

**Date:** 2026-09-27
**Status:** approved, not implemented
**Milestone:** M1 Phase 2c (push only; the SMS half stays deferred)

## 1. What this phase is

The reminder pipeline has been complete on the database side since M1 Phase 1:
`pg_cron` fans out at 03:00 UTC into `private.notification_outbox`, rows are
claimed under a ten-minute lease by `private.next_reminder_batch`, and
`mark_reminder_sent` / `mark_reminder_failed` close them out. All of it is under
pgTAP. What has never existed is the last hop — an actual push arriving on a
phone.

Three things stand between the queue and a device:

1. No Firebase project, so no FCM credentials and no `google-services.json`.
2. No client ever writes a row to `device_tokens`. The table, its RLS and
   `public.register_device_token` have existed since 20260824000005 and are
   reachable by nothing: `SettingsRepositoryImpl` carries
   `String? get _currentDeviceToken => null`, a deliberate stub.
3. Nothing triggers the drain. `enqueue_reminders` runs nightly and fills the
   outbox; `drain_reminders` is only ever called by hand.

This phase closes all three. A Firebase project now exists
(`birthdaypartner-e7b7b`, project number 559698994238), which is what unblocked
it.

## 2. What is deliberately still out

**SMS, entirely.** Phone OTP still runs on `[auth.sms.test_otp]`, and no
transactional SMS provider exists. Indian DLT registration — entity, header and
per-template approval — is a multi-day external process that has not been
started. `send_invite` remains unwritten, which is also why M3 Phase 1b's
confirm token still has no delivery path.

**iOS.** There is no paid Apple Developer Program membership, so no APNs auth
key can be minted, so FCM cannot deliver to iOS at all. Push also never works in
the simulator, so there is no partial iOS verification available either.
Registering the iOS app in Firebase without an APNs key would produce a config
file that looks complete and delivers nothing — worse than its absence. iOS is
therefore not registered in this phase. `firebase_options.dart` will carry
Android only, and adding iOS later is a re-run of `flutterfire configure`.

**Per-device delivery accounting.** Already noted inside `drain_reminders`:
`mark_reminder_sent` stamps `sent_at` on the shared outbox row, and
`next_reminder_batch` filters on `sent_at is null`, so once any one of a user's
devices succeeds, a device that failed in the same batch is never retried. This
is accepted at pilot scale. It is recorded here so it stays a decision rather
than becoming an inherited accident.

## 3. Hosted Supabase, and what that costs

The hosted project is the deployment target for this phase, chosen after the
trade-off below was put and reaffirmed.

**The cost is that device sign-in does not work on hosted.** Hosted GoTrue has
no SMS provider, and phone OTP is the app's only front door — `claim_profile`
trusts the session phone and the entire graph is keyed on
`people.phone_e164_hash`, so no other credential substitutes. A real Android
device therefore cannot sign in against hosted, cannot reach
`register_device_token`, and cannot write a `device_tokens` row.

**`supabase config push` must never run.** `config.toml` carries this warning
above its test-OTP block, and it is correct:

> `supabase db push` does not touch this file, but `supabase config push` DOES
> apply config.toml (this `[auth.sms]` block included) to a hosted project.

Twelve real-format phone numbers whose OTP is a hardcoded `"123456"` would land
on an internet-facing auth endpoint. This project has already reproduced two
account-takeover bugs on this exact surface. The same hazard applies to entering
those numbers into the hosted dashboard's test-OTP feature by hand: it is the
same backdoor, typed instead of pushed. **Neither is done.** Hosted auth is
configured in the dashboard, by hand, without test numbers.

Consequences for deployment, therefore:

- `supabase db push` and `supabase functions deploy` are used. `config push` is
  not, and a repo check is added so it cannot happen by muscle memory (§8).
- Hosted secrets are set with `supabase secrets set`, never committed.

### 3.1 Split verification

Because no single environment can run the whole loop, verification is split, and
this is a real gap rather than a technicality:

| Half | Environment | Why there |
|---|---|---|
| App registration: permission → FCM token → `register_device_token` → row | **Local**, device over LAN | Test OTP works, so a real phone can genuinely sign in |
| Transport: drain → OAuth2 → FCM → notification on the device | **Hosted** | The real target; `device_tokens` row seeded with the service role |

Both halves are proven on a real Android phone. **The seam between them is not
proven by any run**: nothing exercises a token written by the app being drained
by the hosted function. That is stated again in §9 and must not be described as
end-to-end coverage.

## 4. The client

### 4.1 Firebase registration

`flutterfire configure --project=birthdaypartner-e7b7b --platforms=android`,
producing:

- `android/app/google-services.json` — **committed**. It holds a client API key
  that ships inside the APK regardless; it is not a secret, and gitignoring it
  would only break every other clone of the repo.
- `lib/firebase_options.dart` — committed.

Gradle wiring: `com.google.gms.google-services` added to the plugins block in
`android/settings.gradle.kts` with `apply false`, and applied in
`android/app/build.gradle.kts`. Both files use the Kotlin DSL; the plugin id and
version go in the existing `plugins { }` blocks rather than a legacy
`buildscript` block.

Dependencies: `firebase_core`, `firebase_messaging`. `main.dart` gains
`await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
before `ApiClient.init()`.

`main_ops.dart` does **not** initialise Firebase. The ops console is a web
target with no push, and pulling Firebase into it would add weight to a bundle
whose size §3 of the M4 spec deliberately constrained.

### 4.2 `PushRepository`, and a correction to `SettingsRepository`

`SettingsRepositoryImpl` currently owns `deleteThisDeviceToken()` together with
the `_currentDeviceToken => null` stub. Device-token lifecycle is not a settings
concern; settings merely triggers one end of it. This phase extracts a narrow
repository in the project's existing interface-plus-impl shape:

```dart
abstract class PushRepository {
  Future<bool> requestPermission();
  Future<void> registerThisDevice();
  Stream<String> get tokenRefreshes;
  Future<void> deleteThisDeviceToken();
}
```

`SettingsCubit` depends on `PushRepository` for the token deletion and keeps
`SettingsRepository` for `profiles.reminders_enabled`. This is a targeted
improvement to code the phase is already changing, not speculative refactoring:
the stub being removed is the reason the class had the method at all.

Registered in `app.dart` via `RepositoryProvider` with no
`?? ConcreteImpl(...)` fallback, matching every other repository here.

### 4.3 Lifecycle

**Permission** is requested after onboarding completes — on arrival at
`/timeline` for a profile that has just been set up — not at launch. Android 13+
treats `POST_NOTIFICATIONS` as a runtime permission, and a prompt on the first
cold frame, before the user knows what the app is, is the reliable way to be
denied permanently. A denial is not an error state: the app works, reminders
simply do not arrive, and the settings screen remains the place to reconsider.

**Registration** calls `register_device_token(p_token, p_platform)` with
`p_platform = 'android'`. The function already exists, is granted only to
`authenticated`, and already deletes any prior row holding that token, so a
handed-down phone or a reinstall reassigns cleanly.

**Refresh:** `FirebaseMessaging.instance.onTokenRefresh` re-registers. Without
this, a token rotated by the OS leaves the user silently unreachable while the
stale row keeps satisfying `next_reminder_batch`'s `exists` check, so reminders
are claimed and burned against a dead token.

**Sign-out** deletes this device's row before the session is cleared — the
ordering `SettingsCubit` already implements, for the reason already documented
there: once the session is gone, `device_tokens_all_own` no longer matches and
the delete silently affects nothing. This phase is what makes that path
non-vacuous for the first time.

### 4.4 Tap-to-open

A tapped reminder routes to `/person/:personId`, which already exists. The
payload needs the person id, and `next_reminder_batch` does not return it today
— it returns `subject_name` but not `subject_person_id`, even though the outbox
row has it.

**Migration note:** Postgres cannot `create or replace` a function whose return
table has changed. The migration must `drop function private.next_reminder_batch(int)`
and its public wrapper `rpc_next_reminder_batch` first, then recreate both, then
re-apply the `revoke`/`grant` pair — a `drop` takes the ACL with it, and a
recreated function defaults to `execute` for `public`. Getting this wrong
re-opens the function to `anon`.

## 5. Notification content is attacker-controlled

`20260824000005_device_tokens.sql` states the requirement:

> Phase 2 MUST NOT place an unsanitised `display_name` in a notification title
> or body; this is the path that makes it exploitable.

`drain_reminders` violates it today:

```ts
if (r.offset_days === 0) return `It's ${r.subject_name}'s birthday today.`;
```

`subject_name` is `people.display_name`, free text the attacker chooses. It is
inert only because the function is in dry-run. **Supplying FCM credentials is
the act that arms this**, which makes it this phase's problem and not a later
one.

The reachable attack, as the migration describes it: an attacker who obtains a
victim's device token — leaked log, shared device, compromised client — calls
`register_device_token` to move it onto their own account, then creates a
celebrated person whose `display_name` is arbitrary text with a birthday of
today. The pipeline delivers that text to the victim's device as a trusted
notification, while the victim stops receiving their own reminders because the
token no longer points at them.

Mitigation, applied in the drain before the name reaches any string template:

- Clamp to **64 code points**, counted by iterating the string rather than by
  `.length`, so an emoji or a Devanagari cluster is not cut mid-character.
  64 is comfortably above any real name and far below a payload that could hide
  a sentence after the visible portion.
- Strip control characters (`C0`/`C1`), newlines, and the Unicode
  bidirectional overrides `U+202A`–`U+202E` and `U+2066`–`U+2069`. Newlines are
  what let a name impersonate a second line of app-authored text; the bidi
  controls are what let it visually reorder one.
- Replace a name that sanitises to the empty string with the literal
  `Someone`, rather than emitting `It's 's birthday today.`

This narrows but does not eliminate the class: a name that is plain, printable
and short can still read as a sentence. Closing that needs a title/body split
that never interpolates into app-authored prose, which is out of scope here and
carried forward in §10.

## 6. The drain's credentials

FCM HTTP v1 authenticates with a short-lived OAuth2 bearer minted from a service
account, expiring hourly. The current `FCM_ACCESS_TOKEN` env var is a
placeholder the function's own comment already disowns; as a deployment it would
deliver for about an hour and then fail silently into `attempts`.

**Chosen: mint in-function.** The service-account JSON is held in a single
Supabase secret, `FCM_SERVICE_ACCOUNT`, containing the file verbatim. The
function builds the RS256 JWT assertion with WebCrypto, exchanges it at
`oauth2.googleapis.com/token` for the
`https://www.googleapis.com/auth/firebase.messaging` scope, and caches the
result in module scope. A cached token is reused while more than **five
minutes** remain before its expiry, so a warm instance mints roughly once an
hour rather than once per drain, and never hands FCM a token that expires
mid-batch.

`FCM_PROJECT_ID` is dropped as a separate variable: the project id is the
`project_id` field of the service-account JSON, and two sources for one value
is two things to get out of step.

Rejected: `google-auth-library` via an `npm:` specifier — same outcome, heavier
cold start and more supply chain for one signature. Also rejected: a second cron
refreshing a token into a settings table — more moving parts, and a live
credential at rest in the database.

The legacy `fcm.googleapis.com/fcm/send` endpoint with a `key=SERVER_KEY` header
was shut down by Google in 2024 and must not be reintroduced; the existing
comment saying so stays.

**Dry-run is retained.** With no credentials present the function still reports
what it would have sent. That is what makes the pipeline exercisable in CI and
on a machine with no secrets, and it is how every prior phase tested this.

## 7. Triggering the drain

A `pg_net` cron calls the deployed function on a short interval, carrying the
`x-drain-secret` header the function already requires. The secret check predates
this phase and is the right one: the publishable key is a valid JWT, so JWT
verification alone would let anyone who unpacks the APK trigger a drain and burn
claim leases.

Target URL and secret are read at call time from a single-row table,
`private.drain_config (function_url text, drain_secret text)`, rather than being
written into the migration. The migration creates the table empty; the values
are inserted per environment by an operator and are therefore never committed.
The cron body reads the row, and **does nothing when the table is empty** — an
unconfigured environment must be a no-op, not a cron that fires every ten
minutes against `null` and fills the Postgres log with errors.

`private`, not `public`, for the same reason the outbox is: PostgREST cannot see
the private schema, so a table holding a bearer secret has no API surface to
mis-police. No RLS policies; `service_role` and the cron's own definer context
are the only readers.

Cadence is a ten-minute interval rather than a single daily run. The fan-out is
day-granular, but a lone daily drain means one transient FCM failure delays a
reminder by a day, and the ten-minute claim lease already assumes re-entry on
roughly that scale.

## 8. Testing

**Deno** (`drain_reminders`): OAuth2 minting against a stubbed token endpoint,
including that a cached token is reused and an expired one is re-minted;
sanitisation, including a name that is entirely control characters; the dry-run
branch when credentials are absent; the live branch against a stubbed FCM; and
that a non-2xx from FCM records `mark_reminder_failed` rather than counting as
sent.

**pgTAP:** the recreated `next_reminder_batch` returns `subject_person_id`; its
ACL after the drop-and-recreate still excludes `anon` and `authenticated`, and
so does the recreated `rpc_next_reminder_batch` wrapper — a `drop` discards the
ACL and a fresh function is executable by `public`, so this assertion is the
whole point of testing a migration that drops rather than replaces; the drain
cron row exists with the expected schedule; `private.drain_config` is invisible
to PostgREST; and the cron body is a no-op against an empty `drain_config`.

**Flutter,** against a fake `PushRepository`: registration on sign-in; re-
registration on refresh; deletion on sign-out; a permission denial leaving the
app usable; and a tapped payload routing to `/person/:personId` through the real
`buildRouter`, not an inline test router — the M3 Phase 1b lesson.

**A repo check**, `supabase/check-no-config-push.sh`, run alongside the other
verification commands: it fails if any tracked file invokes
`supabase config push` while `[auth.sms.test_otp]` is present in `config.toml`.
It guards the repo's contents, which is all a repo check can do — see §9.

**On a real Android device,** split per §3.1.

## 9. Not verified by any suite

- **The seam between the two verification halves.** No run exercises a token
  written by the app on one environment being drained by the function on the
  other.
- **Delivery to iOS.** Not registered, not built, not attempted.
- **A token rotated by the OS in the field.** `onTokenRefresh` is tested against
  a fake; nothing proves Android actually rotates and that the new token
  reaches the row.
- **`config push` being avoided.** The check tests the repo's contents, not an
  operator's shell history.
- **Any reminder arriving from the nightly fan-out end to end.** Verification
  seeds the outbox directly; `enqueue_reminders` at 03:00 UTC on hosted is not
  observed in this phase.

## 10. Risks

1. **Notification prose can still be impersonated** by a short, plain,
   printable `display_name`. Sanitisation narrows the class; only a
   title/body split that never interpolates into app-authored text closes it.
2. **A hosted project with no SMS provider is a dead front door.** Nothing but
   the drain can be exercised there until SMS lands, and an unused hosted
   project is easy to misremember as working.
3. **The service-account key is a real credential** with permission to send push
   to every installation. It is never committed, never printed, and lives only
   in a Supabase secret and outside the repo on the user's machine.
4. **A ten-minute drain against a lease of the same length** leaves no margin if
   a drain runs long; a slow batch can be re-claimed while still in flight.
   Bounded by `attempts < 5`, but it can duplicate a send.
5. **`google-services.json` being committed will look like a leak** to anyone
   reviewing later. §4.1 records why it is not, so the decision is not
   re-litigated from first principles.

## 11. Carried forward

1. The SMS half of Phase 2c: provider selection, DLT registration, `send_invite`,
   and M3 Phase 1b's undelivered confirm token.
2. iOS: Apple Developer membership, APNs key, iOS app registration.
3. Per-device delivery accounting (§2).
4. A title/body split for notification content (§10.1).
5. The hosted `config push` problem, properly solved — a config layout where
   test OTP cannot reach a hosted project even if the command is run.

## 12. Open questions

1. Who creates the hosted Supabase project — the user in the dashboard, handing
   over the project ref, or the CLI, which requires a database password the user
   sets? Not blocking §4, which is entirely local.
2. Whether the drain's ten-minute cadence should be tightened once real volume
   exists, or widened to reduce cost.
