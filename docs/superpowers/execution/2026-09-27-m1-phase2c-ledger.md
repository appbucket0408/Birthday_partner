# M1 Phase 2c (push) — execution ledger

**Spec:** `docs/superpowers/specs/2026-09-27-m1-phase2c-push-design.md`
**Plan:** `docs/superpowers/plans/2026-09-27-m1-phase2c-push.md`
**Branch:** `m1-phase2c-push`, cut from `main` @ `97e5a16`
**Execution:** inline (`superpowers:executing-plans`), 8 code tasks + verification

## What now works that did not before

A reminder pipeline that had been complete on the database side since M1
Phase 1 and had never delivered anything now runs end to end up to the final
FCM hop, and the app registers real device tokens from real hardware.

| | Before | After |
|---|---|---|
| Firebase | no project | `birthdaypartner-e7b7b`, Android app registered |
| `device_tokens` rows ever written | 0 | real token from device RZCW50T4FEV |
| `deleteThisDeviceToken` | guarded no-op behind `_currentDeviceToken => null` | observed deleting the row on sign-out |
| drain credentials | `FCM_ACCESS_TOKEN`, a placeholder valid ~1 hour | OAuth2 minted in-function, cached with a 5-minute margin |
| notification body | raw `display_name` | sanitised: control chars, newlines, bidi overrides, 64 code points |
| what triggers the drain | nothing | `pg_cron` → `private.trigger_drain()` → `pg_net` → the function |
| tapped reminder | no payload, nowhere to go | `/person/:personId` from a validated positive int |

## Suite counts

| Suite | Before | After |
|---|---|---|
| pgTAP | 32 files / 295 | **34 files / 305** |
| Deno edge functions | 18 | **33** |
| Flutter non-contract | 250 | **261** |
| Flutter contract | 53 | **52** (one deleted, see Ruling 3) |
| `flutter analyze` | clean | clean |
| APK / ops web build | ok | ok |
| `check-no-config-push.sh` | did not exist | PASS |

`supabase/config.toml:272` `enable_confirmations = true` verified intact.

## Proven on the device (RZCW50T4FEV, Android, over `adb reverse`)

1. `FirebaseApp initialization successful`, then `Supabase init completed` on
   the handset — the app reached the Mac's local stack.
2. Phone OTP → onboarding, against local GoTrue with the project's own
   `[auth.sms.test_otp]` number.
3. **On arrival at the timeline**, the Android 13+ `POST_NOTIFICATIONS`
   dialog appeared. This is the single most important observation in this
   phase: see Ruling 4.
4. Allow → `device_tokens` gained a real FCM token, `platform = 'android'`.
5. Sign out → that row went `1 → 0`.
6. Drain against the real token: `{"dryRun":true,"would_send":1}`; the row
   claimed, `attempts` 1, `sent_at` null.
7. Sanitiser against a hostile `display_name` actually stored in the
   database (`Asha\nYour account was suspended. Tap to verify.‮…`):
   no newline, no bidi control, exactly 64 code points in the name.
8. Cron path: `trigger_drain()` → `net._http_response` status **200**. The
   first firing reported `would_send: 0`; releasing the claim lease and
   re-firing gave `would_send: 1`, so the zero was the documented ten-minute
   lease, demonstrated rather than assumed.

## Not proven by anything

- **The FCM hop itself.** No notification has been delivered to a handset.
  It needs `FCM_SERVICE_ACCOUNT`, which only the project owner can generate.
  Everything upstream of that one call is proven.
- **Anything hosted.** No hosted Supabase project exists yet; creating one
  needs `supabase login` and a database password the owner sets. The spec's
  §3.1 split verification therefore has only its local half done.
- **iOS.** Not registered, not built, not attempted. No Apple Developer
  membership, so no APNs key can exist.
- **A token rotated by the OS in the field.** `onTokenRefresh` re-registers
  and is covered by construction, not by observation.
- **`config push` being avoided.** The check guards the repo's contents, not
  an operator's shell.

## Rulings

1. **Gradle wiring accepted as generated.** `flutterfire configure` wired
   `com.google.gms.google-services` itself at 4.4.4 and placed it *before*
   the Flutter plugin; the plan said 4.4.2 and *after*. The real constraint
   is that it follow `com.android.application`, which it does. Proven by the
   APK build.
2. **`firebase.json` committed.** Generated at the repo root, contains no
   secret, and is what makes a re-run of `flutterfire configure` idempotent.
3. **A contract test deleted, as a recorded coverage loss.**
   `settings_repository_test.dart`'s "deleteThisDeviceToken on a user with no
   registered token is a no-op" asserted the Phase 2b *stub*. It could not
   move to `PushRepository` — that impl needs a platform channel. The device
   run closed the gap instead.
4. **`lazy: false` on the timeline's `BlocProvider`, plus a test for it.**
   The plan said only to wrap the body in a provider. Done literally, the
   suite went green **and the feature was dead**: `BlocProvider` defaults to
   lazy, nothing in `_TimelineView` reads `PushCubit` (a denial renders
   nothing, by design), so `create` never ran and no device would ever have
   registered. This is the M4 Phase 1 blocker class exactly. The widget test
   added here was watched to fail (`Expected <1>, Actual <0>`) with
   `lazy: false` removed.
5. **`PushCubit` filed under `features/push/`,** not `features/settings/` as
   the plan said — its only caller is the timeline.
6. **The ordering test adapted, not duplicated.** The plan told me to add a
   sign-out ordering assertion and claimed it "could not fail" before this
   phase. Both halves were wrong: it already existed at
   `settings_cubit_test.dart:171` with a shared `calls` list, and it was
   never vacuous at the cubit level. The shared list now threads through
   `_FakePush`. Watched to fail with the two awaits reversed.
7. **My own OAuth scope test was wrong and fixed, not the code.** It asserted
   the scope appeared in the request body; in the JWT-bearer flow the scope
   lives base64url-encoded *inside* the assertion. The test now decodes the
   payload and checks `scope`, `aud`, `iss` and `exp - iat`. Strictly
   stronger — the original would have passed for an assertion requesting no
   scope at all.
8. **`pemToPkcs8` returns an `ArrayBuffer`.** Deno 2.9 makes `Uint8Array`
   generic over `ArrayBufferLike`, which fails `importKey`'s `BufferSource`
   overload.
9. **The `config push` guard rewritten; the plan's version was broken.** It
   failed on its first run against a clean tree, because the loudest mention
   of the command in this repo is `config.toml`'s own warning *forbidding*
   it. A comment filter alone did not fix it either — the specs and ledgers
   are markdown prose. It now searches only files that can execute and skips
   comment lines within those. Watched through all four states.
10. **`adb reverse` instead of LAN.** This Mac has no usable wifi LAN address
    (only `192.0.0.2`, an IANA special-purpose interface). USB forwarding is
    better anyway: no wifi dependency, and `SUPABASE_URL` stays a literal
    localhost.
11. **The device run was performed here, not handed over.** The plan reserved
    Task 9 for the human partner and forbade running the app; the partner
    then said a device was connected and to proceed.

## Final whole-branch review

A fresh reviewer (separate context, most capable model) found **one Critical
and nine Important**. Eight were fixed in one pass, each with a test watched
to fail first; one was escalated rather than fixed; one was judged a
duplicate of work already done.

| | Finding | Outcome |
|---|---|---|
| C1 | `next_reminder_batch` burns an attempt **as it claims**, so every abandon path still destroyed reminders — and `index.ts` carried a comment asserting the opposite. A failed mint returned 500 marking nothing failed, the cron re-claimed every 10 min, and within ~1 hour every pending row crossed `attempts < 5` and vanished forever with `last_error` null. | Fixed: `private.release_reminder_claims` |
| I2 | U+2028/U+2029 not stripped — mandatory line breaks to Android's ICU breaker, so a name could still forge the second line. LRM/RLM/ALM also missing. | Fixed |
| I3 | `trim()` does not remove U+200B, so a name of pure zero-width characters defeated the `Someone` fallback and rendered `It's 's birthday today.` | Fixed |
| I4 | `index.ts` had **no tests**. Review Focus 2 was evidenced by `isDeadToken(404) === true` — a predicate over an integer that cannot fail if the delete is missing. | Fixed: handler extracted to `handler.ts`, 10 tests |
| I5 | A notification tapped from a **cold start** never reached the person page: `getInitialMessage` resolves before the session, and the router bounces `SessionUnknown` to `/splash`, then to `/timeline`. | Fixed: `navigateWhenSessionResolves` |
| I6 | A bare 404 deleted device tokens with no body check; a service account missing `project_id` would have made the URL `/projects/undefined/` and deleted **every** token in the batch, silently. | Fixed |
| I7 | The bearer cache was global and never invalidated, so a revoked key kept being served for ~55 minutes. | Fixed: keyed on `client_email`, dropped on 401/403 |
| I8 | Four hard-coded-OTP phone numbers in `config.toml`. | **Escalated, not fixed** — see below |
| I9 | `trigger_drain`'s configured path was executed by nothing; only the empty-config guard was tested. | Fixed: 3 assertions |
| I10 | Re-prompting on every timeline arrival spends Android 13's second and final refusal within seconds of the first. | Fixed: status checked before asking |

Fixing I10 surfaced something the review did not catch: the analyzer rejected
the non-exhaustive switch, revealing `AuthorizationStatus.deniedPermanently`
— the exact state a second refusal produces. Without mapping it to `denied`
the cubit would have called `requestPermission()` forever against an OS that
will never show a prompt again.

**I8 was escalated rather than fixed.** Commit `670ff21` added four
`[auth.sms.test_otp]` numbers, including two that look like real personal
mobiles. They arrived in the working tree from outside the session — only the
spec file was staged, so they were already in the index — which is consistent
with them having been added deliberately to test OTP on a real handset.
Reverting would destroy that; keeping them silently would bury a real hazard.
The decision belongs to the project owner.

## Carried forward

1. The SMS half of Phase 2c: provider, DLT registration, `send_invite`, and
   M3 Phase 1b's still-undelivered confirm token.
2. iOS: Apple Developer membership, APNs key, registration.
3. The hosted deploy — see `2026-09-27-m1-phase2c-deploy-runbook.md`.
4. Per-device delivery accounting: once any device succeeds, a device that
   failed in the same batch is never retried.
5. A title/body split so notification text never interpolates into
   app-authored prose. Sanitisation narrows the class; it does not close it.
6. `23514` overload at `lib/gifting/draft_cubit.dart:68`, from M4.
