# Task 1 Report: Make phone OTP work locally

## Status: DONE

## Step 1 — Proof it was broken

```
$ curl -s -X POST 'http://127.0.0.1:54321/auth/v1/otp' \
    -H 'apikey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    -H 'content-type: application/json' \
    -d '{"phone":"+919999000001"}'

{"code":400,"error_code":"phone_provider_disabled","msg":"Unsupported phone provider"}
```

Note: the actual failure mode was `phone_provider_disabled` ("Unsupported phone
provider"), not an `enable_signup`-specific rejection — with no SMS provider
configured at all, GoTrue refuses the request before signup policy is even
evaluated. This is still the correct evidence that phone OTP could not work
at all before this change.

## Step 2/2b — Config changes (bigger than the brief anticipated)

The brief's exact steps (`enable_signup = true` + a `[auth.sms.test_otp]`
block) were applied verbatim first. But after restarting with only those two
changes, `supabase start` printed:

```
WARN: no SMS provider is enabled. Disabling phone login
```

and the OTP request still failed with the same `phone_provider_disabled`
error — confirmed empirically, not assumed. **GoTrue requires at least one
SMS provider to be nominally `enabled` before it will accept *any* phone
signup, even for numbers that are fully served out of the `test_otp` map.**
This is not documented in the brief, and is easy to miss because the CLI's
own warning is the only signal.

Fix: enabled the (already-scaffolded, currently-unused) `[auth.sms.twilio]`
block with fake, local-only placeholder credentials. Since every phone
number the app will use locally is listed in `test_otp`, GoTrue never
actually reaches out to Twilio — the credentials are never dereferenced.

First pass used `auth_token = "env(SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN)"`
(matching the file's existing pattern) with the env var exported manually
before `supabase start`. This is fragile: Bash tool invocations don't
persist shell state between calls, and a future `supabase start` in a shell
that hasn't exported that var reintroduces `WARN: environment variable is
unset` (confirmed — it reappeared on the very next command). Since this
value is a fake credential that's never used for a real API call, hiding it
behind an unset env var bought no security benefit and added a real
footgun. Replaced it with a literal placeholder string
(`local_test_token`) directly in `config.toml`, then did a clean
`supabase stop && supabase start` with the env var explicitly `unset` to
prove the config is now fully self-contained — no warning, no external
dependency.

Final `[auth.sms]` / `[auth.sms.twilio]` diff:

```toml
[auth.sms]
# Phone is the app's front door and the whole graph is keyed on a verified
# number, so signup by SMS has to be allowed.
enable_signup = true
enable_confirmations = false
template = "Your code is {{ .Code }}"
max_frequency = "5s"

# Use pre-defined map of phone number to OTP for testing.
# [auth.sms.test_otp]
# 4152127777 = "123456"

# Local test numbers. No SMS provider is configured, and the M1 spec's decision
# is to build the full OTP flow against these and swap in a real provider at
# first real-device test. These are LOCAL ONLY — config.toml is not applied to a
# hosted project by `supabase db push`.
[auth.sms.test_otp]
919999000001 = "123456"
919999000002 = "123456"
919999000003 = "123456"

...

[auth.sms.twilio]
# GoTrue requires an SMS provider to be enabled before it will accept any
# phone signups, even ones served entirely from [auth.sms.test_otp] above.
# These are fake, local-only placeholder credentials: every number this app
# uses locally is listed in test_otp, so GoTrue never actually calls Twilio.
enabled = true
account_sid = "local_test_sid"
message_service_sid = "local_test_msid"
auth_token = "local_test_token"
```

## Which `test_otp` key format worked — determined empirically

**Unprefixed keys (no leading `+`) worked, matching Supabase's own
commented-out example (`4152127777 = "123456"`), not the E.164-with-`+`
form the Flutter app will send.**

How this was determined: after enabling the Twilio provider (fixing the
"no provider" blocker above), the very first OTP+verify attempt used
`919999000001 = "123456"` in `test_otp` (unprefixed) against a request body
of `{"phone":"+919999000001"}` (with `+`, as the app will send). It
succeeded on the first try — `/verify` returned a full session with
`user.phone` = `"919999000001"` (no `+`). GoTrue evidently normalizes/strips
the `+` from the E.164 number it receives before matching against the
`test_otp` map and before storing `auth.users.phone`, so:

- The app can (and should) keep sending E.164 with `+` in its API calls —
  that's unaffected.
- `config.toml`'s `test_otp` keys, and any code that needs to reason about
  the stored `phone` value, must use the **unprefixed** form
  (`919999000001`, not `+919999000001`).

The `+`-prefixed key form was not additionally tested as a negative control
(would have required another full `stop`/`start` cycle) since the
unprefixed form matched Supabase's documented example and worked
unambiguously on the first successful attempt post-fix; the returned
`user.phone` field is independent corroborating evidence of the same
normalization.

## Step 4 — End-to-end proof

Request:
```
POST /auth/v1/otp
{"phone":"+919999000001"}
```
Response:
```json
{"message_id":"test-otp"}
```

Request:
```
POST /auth/v1/verify
{"phone":"+919999000001","token":"123456","type":"sms"}
```
Response (access_token redacted to first 12 chars):
```json
{
  "access_token": "eyJhbGciOiJ...<redacted>",
  "token_type": "bearer",
  "expires_in": 3600,
  "expires_at": 1787816288,
  "refresh_token": "pyktzoavluah",
  "user": {
    "id": "5df88251-2920-4e4b-8b57-247a858a1d1b",
    "aud": "authenticated",
    "role": "authenticated",
    "email": "",
    "phone": "919999000001",
    "phone_confirmed_at": "2026-08-27T06:38:08.521001Z",
    "confirmation_sent_at": "2026-08-27T06:38:08.488605Z",
    "confirmed_at": "2026-08-27T06:38:08.521001Z",
    "last_sign_in_at": "2026-08-27T06:38:08.522948945Z",
    "app_metadata": {"provider": "phone", "providers": ["phone"]},
    "user_metadata": {
      "email_verified": false,
      "phone_verified": false,
      "sub": "5df88251-2920-4e4b-8b57-247a858a1d1b"
    },
    "identities": [{
      "identity_id": "9b7fe300-c230-47b7-a7e8-d69e5bd5e109",
      "id": "5df88251-2920-4e4b-8b57-247a858a1d1b",
      "user_id": "5df88251-2920-4e4b-8b57-247a858a1d1b",
      "identity_data": {"email_verified": false, "phone_verified": false, "sub": "5df88251-2920-4e4b-8b57-247a858a1d1b"},
      "provider": "phone",
      "last_sign_in_at": "2026-08-27T06:38:08.451652Z",
      "created_at": "2026-08-27T06:38:08.451669Z",
      "updated_at": "2026-08-27T06:38:08.451669Z"
    }],
    "created_at": "2026-08-27T06:38:08.447496Z",
    "updated_at": "2026-08-27T06:38:08.524385Z",
    "is_anonymous": false
  }
}
```

## Signup trigger confirmation

```
$ docker exec supabase_db_birthday_app psql -U postgres -d postgres -tAc \
    "select handle, display_name from public.profiles order by created_at desc limit 1;"

u5df8825129204e4b8b57247a858a1d1b|New user
```

`handle` = `u` + the user's UUID with dashes stripped
(`5df88251-2920-4e4b-8b57-247a858a1d1b`), `display_name` = `New user` —
matches the expected shape exactly, confirming `private.handle_new_user`
fired on signup.

## Step 5 — Suite unaffected

```
$ supabase db reset && supabase test db
...
All tests successful.
Files=19, Tests=168,  1 wallclock secs (...)
Result: PASS
```

Matches the pre-task baseline (`Files=19, Tests=168, PASS`) exactly, with no
`WARN: environment variable is unset` this time (confirms the config is now
fully self-contained, no external env var dependency). No schema was
touched by this task.

## Commit

```
git add supabase/config.toml
git commit -m "feat(auth): enable phone OTP locally with a test-code map"
```

## Summary for downstream tasks / the Flutter app

- `enable_signup = true` alone is not sufficient locally — an SMS provider
  must also be `enabled = true` in config, even a fake/unused one, or GoTrue
  rejects every phone request with `phone_provider_disabled` regardless of
  `test_otp`. This is now handled in `[auth.sms.twilio]` with harmless
  placeholder credentials; no action needed by later tasks or the app.
- **`test_otp` keys must be unprefixed** (`919999000001`), not E.164 with a
  `+`. The app should keep sending `+919999000001` etc. in its API calls —
  GoTrue normalizes it — but anything reading/comparing the stored
  `auth.users.phone` value (including any later task's fixtures or
  assertions) should expect the unprefixed form.

---

## Review round 1 — fix-up

Review verdict: spec ✅ / quality Approved. The deviation (enabling
`[auth.sms.twilio]` with placeholder credentials) was agreed to be
necessary, correctly diagnosed, and honestly reported. Two comment-only
findings were raised; no code or config *values* changed.

### F1 (Important) — restored the deleted guardrail

Replacing `auth_token = "env(SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN)"` with a
literal had silently dropped the upstream
`# DO NOT commit your Twilio auth token to git. Use environment variable
substitution instead:` comment. Every other secret field in this file
(SendGrid pass, Apple OAuth secret, S3 keys) still uses the `env(...)` +
do-not-commit pattern; this was the only place it had been abandoned. Risk:
when a real Twilio account is wired in at first real-device test, the
natural edit is these same three lines in place, and the warning that would
have stopped someone typing a real token as a literal was gone.

Restored, directly above `auth_token`:

```toml
# DO NOT put a real Twilio auth token here as a literal. When a real provider is
# configured, switch this back to env(SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN) —
# every other secret in this file uses that pattern.
```

### F2 (Minor) — documented the undo path

Added one line inside the existing `[auth.sms.twilio]` explanatory comment
(not a separate block) naming what to do when a real provider arrives:

```toml
# To move to a real provider: replace the three placeholder values below, switch
# auth_token to env(...) substitution, and decide whether [auth.sms.test_otp]
# stays for local development or goes.
```

### Final `[auth.sms.twilio]` block

```toml
[auth.sms.twilio]
# GoTrue requires an SMS provider to be enabled before it will accept any
# phone signups, even ones served entirely from [auth.sms.test_otp] above.
# These are fake, local-only placeholder credentials: every number this app
# uses locally is listed in test_otp, so GoTrue never actually calls Twilio.
# To move to a real provider: replace the three placeholder values below, switch
# auth_token to env(...) substitution, and decide whether [auth.sms.test_otp]
# stays for local development or goes.
enabled = true
account_sid = "local_test_sid"
message_service_sid = "local_test_msid"
# DO NOT put a real Twilio auth token here as a literal. When a real provider is
# configured, switch this back to env(SUPABASE_AUTH_SMS_TWILIO_AUTH_TOKEN) —
# every other secret in this file uses that pattern.
auth_token = "local_test_token"
```

### Verify — nothing functional moved

`supabase stop && supabase start` — clean restart, no `WARN` (proves the
comment-only edit still parses and the provider is still recognized as
enabled):

```
Started supabase local development setup.
```

OTP request for `+919999000001`:
```json
{"message_id":"test-otp"}
```
Verify with `123456` — returned a full session (access_token present,
truncated here):
```json
{"access_token":"eyJhbGciOiJFUzI1NiIs...", ...}
```

`supabase test db`:
```
All tests successful.
Files=19, Tests=168,  1 wallclock secs (...)
Result: PASS
```

Matches baseline exactly — `Files=19, Tests=168, PASS`.

### Commit

```
git add supabase/config.toml
git commit -m "docs(config): restore the do-not-commit warning on the SMS provider"
```
