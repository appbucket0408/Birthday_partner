# Candlewish

Never miss the birthdays of the people you celebrate. Candlewish imports the
people you know from your contacts, reminds you before their day, and lets you
leave wishes and photos on their wall.

- **App:** Flutter (`lib/`), Bloc/Cubit state, go_router navigation.
- **Backend:** Supabase (`supabase/`): Postgres with RLS, Edge Functions,
  Storage, pg_cron reminders, FCM push.
- **Ops console:** a separate Flutter entry point, `lib/main_ops.dart`.

## Running locally

Flutter is pinned with FVM (`.fvmrc`).

```bash
supabase start                     # local stack on 127.0.0.1:54321
supabase db reset                  # migrations + seed
fvm flutter run \
  --dart-define=SUPABASE_ANON_KEY=<local anon key from `supabase status`>
```

`SUPABASE_URL` defaults to the local stack. On an Android emulator pass
`--dart-define=SUPABASE_URL=http://10.0.2.2:54321`, or use the VS Code launch
config, which runs `adb reverse` first.

Local sign-in uses the test numbers in `supabase/config.toml`
(`[auth.sms.test_otp]`), and every code is `123456`.

## Tests

```bash
fvm flutter test                   # app + contract tests (needs supabase start)
supabase test db                   # pgTAP suites in supabase/tests/database
supabase/functions/test.sh         # Edge Function tests
```

## Deploying

See `docs/superpowers/execution/2026-09-27-m1-phase2c-deploy-runbook.md`.
**Never run `supabase config push`**: `config.toml` carries local-only test
OTP numbers that would become a backdoor on a hosted project.
