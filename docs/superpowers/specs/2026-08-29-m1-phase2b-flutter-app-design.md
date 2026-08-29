# M1 Phase 2b — App: Identity and Graph

Date: 2026-08-29
Status: Approved for implementation planning
Parent spec: `docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md` §9, Phase 2
Predecessor: Phase 2a (app-facing backend surfaces), merged to `main` at `5f8afa4`

## 1. What Phase 2b is

Phase 2a finished the backend the app talks to. Phase 2b is the app: the first
code in this repository that a person can hold.

It ends with a signed-in user who has imported their contacts and can see a
Celebrating timeline grouped by how soon each birthday falls — running against
local Supabase, with the OTP test provider and push registration stubbed.

The parent spec ended its Phase 2 with "reminders land on a real device". That
goal is deferred to **Phase 2c**, because it depends on a Firebase project, FCM
credentials and a paid SMS provider — none of which exist, and none of which are
code. Deferring them keeps two external blockers off the critical path instead of
stalling the build partway through.

## 2. Scope

**In:** the slice-0 backend prerequisites (§4), the Flutter scaffold, phone OTP
onboarding, contacts import, the Celebrating timeline, and Settings.

**Out, to Phase 3:** person page, wish wall, profile with its header counts and
track record. Also the parent spec's single end-to-end test — it ends in
"wish → profile counts tick", so it cannot be written until Phase 3 exists.

**Out, to Phase 2c:** real FCM delivery, the `pg_net` drain cron and its
`verify_jwt` decision (parent carry-forward #3), the paid SMS provider, and the
first real-device test of either.

## 3. Decisions

| Question | Decision | Why |
|---|---|---|
| Real-device push in this phase | No — Phase 2c | Needs a Firebase project and FCM credentials, which are setup, not code. Blocking the app on them stalls everything; deferring them stalls nothing. |
| Visual design | One seed-colour Material 3 theme, decided here | The parent spec already declines golden tests in M1 because the visual design is unsettled, so a later restyle costs nothing. Figma would add per-screen cost for fidelity M1 does not need. |
| Edge Function coverage | One Deno test, for `add_celebrations` only | Its status vocabulary is the contract this phase bakes into the client and the ledger names it the most expensive to get wrong. The other four stay covered only from the Dart side; closing the whole gap is not this phase's job. |
| Build order | Vertical slices, spec order, repository before screen | Keeps a runnable app at every checkpoint and puts the RLS-facing work ahead of UI within each slice — M0 and 2a both proved that is where the defects live. |
| Flutter version | 3.35.2, pinned in `.fvmrc` | Greenfield app; no reason to inherit another project's 3.24.3 pin. |
| Isolation | A branch in the main checkout, no git worktree | Worktrees cost this project twice: M0's removal nearly destroyed the execution ledger, and 2a's isolation meant the session could not merge its own work. |
| Local database | None, per parent spec §3 | Unchanged. The timeline reads through the Supabase client with a per-session cache. |

## 4. Slice 0 — backend prerequisites

This phase is not pure Flutter. Two backend items must land before the client
depends on them.

### 4.1 Inline birthday edit (parent carry-forward #4)

Parent spec §7.3 requires editing a contact's birthday inline on a timeline row.
**No surface exists.** `public.people` has no UPDATE policy, and
`private.upsert_person` only fills NULLs and only when `profile_id` is null.

New migration adding `public.rpc_update_person_birthday(p_person_id bigint,
p_birth_month smallint, p_birth_day smallint, p_birth_year smallint)`,
`security definer`.

Two conditions, both load-bearing:

1. The caller must hold a `celebrations` edge to `p_person_id`. Without it, a
   sequential bigint person id is an open write target.
2. The person must be **unclaimed** (`profile_id is null`). Without this, any
   celebrator could rewrite a real user's date of birth. A claimed user's own
   birthday always wins.

Written test-first in pgTAP, per M0's discipline. New `private` functions, if
any, extend the allowlist in `01_private.test.sql` — the standing obligation
that caught five leaked functions in M0.

### 4.2 One Deno test for `add_celebrations`

Covering the status vocabulary
(`added|duplicate|suppressed|invalid_phone|invalid_name|self|failed`), the
`added + skipped + failed + duplicates == contacts.length` invariant,
`results.length == contacts.length`, `MAX_BATCH` (500 → 413),
`MAX_NAME_LENGTH` (128), and the missing-authorization 401.

## 5. Application architecture

The house `api/` shape and the three global const files, with the parent spec's
two deliberate departures preserved.

```
lib/
├─ main.dart
├─ app.dart                MaterialApp.router, theme, top-level providers
├─ core/
│  ├─ app_colors.dart  app_text_styles.dart  app_spacing.dart
│  ├─ app_strings.dart     ALL user-facing copy; no literals in screens
│  ├─ logger.dart
│  └─ result.dart          sealed Result<T> / AppFailure
├─ router/app_router.dart  go_router; redirect guard on auth + onboarding state
├─ api/
│  ├─ api_client.dart      Supabase singleton
│  ├─ api_endpoints.dart   Edge Function names
│  ├─ api_params.dart      RPC argument and column-key constants
│  ├─ api_connectivity.dart
│  └─ api_error_mapper.dart  PostgrestException / FunctionException → AppFailure
├─ models/
│  ├─ birthday.dart        month + day required together, year nullable
│  ├─ profile.dart  person.dart  celebration.dart
│  └─ import_outcome.dart  the add_celebrations status vocabulary as an enum
├─ repositories/           interface + impl each
│  ├─ auth_repository       OTP, session, claim_profile, sign out, delete account
│  ├─ graph_repository      celebrations + people reads, birthday edit, un-celebrate
│  ├─ contacts_repository   device contacts, E.164 normalisation, resolve, add
│  └─ settings_repository   reminders_enabled
└─ features/               each: cubit + state + screen, layout inline
   ├─ onboarding/  contacts_import/  timeline/  settings/
```

**Two departures from the house convention, both inherited from the parent spec
§6 rather than chosen here:** the Supabase Dart client instead of dio (auth, RLS
and token refresh come with it), and per-feature repositories instead of a single
`api_service_interface`, which at seven screens becomes a god object.

**Widget style:** no one-off sub-widget classes. Screens own their layout; only
genuinely reused or genuinely oversized pieces are extracted.

Packages: `flutter_bloc`, `go_router`, `supabase_flutter`, `flutter_contacts`,
`phone_numbers_parser`, `fluttertoast`, `bloc_test`.

## 6. Screens and flows

### 6.1 Onboarding

`signInWithOtp(phone)` → `verifyOTP` → `POST /claim_profile` → profile setup.

`claim_profile` requires a verified phone on the session and returns
`person_id`; **409 means the profile already claimed a different number** and
needs its own error branch, not a generic failure toast.

**The `profiles` row already exists by this point.** `private.handle_new_user`
fires on `auth.users` insert and creates it with a placeholder handle
(`'u' || <uuid without dashes>`) and `display_name = 'New user'`. There is no
insert policy on `profiles` and the app does not need one: profile setup is an
**UPDATE**, and every column it writes — `display_name`, `handle`, `city`,
`birth_month` / `birth_day` / `birth_year` — is already in the `authenticated`
column grant list.

**Onboarding-complete signal, read by the router guard:
`profiles.birth_month is not null`.** The placeholder handle and display_name are
both non-null from the trigger, so neither can distinguish a fresh account from a
finished one; the birthday is required by this screen and is null until it
completes. The guard therefore has three states: no session → OTP; session but
`birth_month is null` → profile setup; otherwise → timeline.

The country captured here is what E.164 normalisation uses during import.

Cubit states cover: idle, sending, awaiting code, verifying, retry-with-cooldown,
and each terminal failure distinctly.

### 6.2 Contacts import

Prominent-disclosure screen **before** the OS permission prompt. Play requires
it, and permission declarations are historically where releases get blocked.

Then: read contacts via `flutter_contacts` → normalise to E.164 with
`phone_numbers_parser` against the onboarding country → dedupe →
`resolve_contacts` in chunks of ≤500 to badge who is already a user → the user
picks → fill missing birthdays → `add_celebrations` in chunks of ≤500.

**Chunking is mandatory, not an optimisation.** Parent carry-forward #5 measured
500 sequential awaited RPCs at ~6.2s on warm loopback. The screen shows real
progress across chunks.

Results are zipped **positionally** against the picked list, which the Edge
Function guarantees by returning one entry per input index — including repeat
occurrences, under status `duplicate`.

**Privacy rule for the summary, load-bearing:** `suppressed` must be
indistinguishable from every other skip. Someone who asked to be removed must not
have that fact revealed to whoever imported them. The skipped row shows a count
and no reason.

Remaining statuses map to: added; `duplicate` (a repeat of the same number in
this import); `self` (your own number, the single likeliest "failure" in a real
address book, so it reads as a note rather than an error);
`invalid_phone` / `invalid_name` (fixable, names the contact);
`failed` (retryable, does not name the contact).

### 6.3 Celebrating timeline

`celebrations` embedded with `people`, grouped Today / This week / This month on
`birth_month` and `birth_day`. **Feb 29 falls on Feb 28 in non-leap years**,
matching the reminder fan-out — a timeline that disagrees with the notification
is worse than either alone.

Row actions: edit birthday inline (§4.1's RPC) and stop celebrating (a plain
`DELETE`; `celebrations_delete_own` survived the 2a write lockdown).

**Nickname edit is in scope for this phase.** It is the one remaining
`authenticated` write on `celebrations` (`grant update (nickname)`), and it is
what makes an imported contact recognisable when the address-book name is
unhelpful. Per parent carry-forward #7 the guard trigger now rejects a nickname
edit if the target has since blocked you, so the client needs a real error branch
on what otherwise looks like a purely cosmetic path.

Empty state routes back into import.

### 6.4 Settings

Notification toggle writing `profiles.reminders_enabled` (granted in 2a).

Sign out **deletes this device's `device_tokens` row**. Push is stubbed in 2b, so
there is usually no row to delete — the code path ships anyway, because a
signed-out device still receiving someone's reminders is exactly the failure the
parent spec §6 names.

Delete account calls `delete_account`, behind a confirmation that states what
parent carry-forward #8 makes true: deletion strands a scrubbed person row, so
bystanders' edges survive as a "Deleted user" and re-importing that number mints
a new row beside it.

## 7. Testing

| Layer | Tool | Covers |
|---|---|---|
| New RPC | pgTAP, test-first | Both §4.1 conditions, including the unclaimed-person rule |
| `add_celebrations` | Deno | §4.2 |
| Cubits | `bloc_test` against fakes | OTP retry, import chunking and progress, timeline grouping |
| Repositories | Contract tests against **real local Supabase** | RLS, grants, Edge Function contracts |
| Widgets | `flutter_test` | OTP entry, import selection, timeline grouping only |

Repository tests hitting real local Supabase rather than fakes is the parent
spec's deliberate call, and M0 is the evidence: `private.can_see_person` broke
three separate ways, and a fake repository would have passed every one.

No golden tests. No end-to-end test — it belongs to Phase 3.

Two M0 lessons that apply to every assertion written here: a green suite is not
evidence until the new assertion has been watched to FAIL with the fix reverted;
and a test that fails to reproduce a defect is not evidence of absence until the
test itself has been checked.

## 8. Build order

Vertical slices. Each feature's repository is contract-tested against real local
Supabase before its screen is written.

0. **Backend prerequisites** — §4.1 migration and pgTAP, §4.2 Deno test.
1. **Scaffold** — `.fvmrc`, `pubspec.yaml`, `core/`, `api/`, `router/`, theme,
   local Supabase wiring, app boots to a placeholder.
2. **Onboarding** — auth repository, then the OTP and profile-setup screens.
3. **Contacts import** — contacts repository, then disclosure, pick and
   fill-birthdays screens.
4. **Timeline** — graph repository, then the grouped list with its row actions.
5. **Settings** — settings repository, then toggle, sign out, delete account.

## 9. Risks carried into this phase

1. **Four of five Edge Functions still have zero automated coverage** (parent
   carry-forward #1). This phase closes only `add_celebrations`.
2. **`enable_confirmations = true` is guarded by nothing** (carry-forward #2) —
   no test, no lint, no CI — and `supabase init` or a CLI upgrade rewrites
   `config.toml`. It is the fix for total account takeover. Any config.toml edit
   in this phase must re-verify it.
3. **`upsert_person`'s insert is not `on conflict`** (carry-forward #5), so two
   users importing the same new number concurrently produce a 23505 that reaches
   the client as a generic `failed`.
4. **`display_name` is unbounded at the database layer** (carry-forward #6); the
   128-char limit lives only in the Edge Function.
5. **No CORS/OPTIONS handling in any function** (carry-forward #11). Fine for
   Flutter mobile; it would break a Flutter web build, which the ops console in
   M4 will be.

## 10. Not in Phase 2b

No person page, wish wall or profile. No cake, catalog, payment or address
confirmation. No ops console. No real FCM delivery, no drain cron, no paid SMS.
No local database, no golden tests, no realtime subscriptions. No notification
when someone starts celebrating you — still deliberately absent.

## 11. Open questions

1. **Firebase project, FCM credentials and SMS provider** remain unresolved.
   They now block Phase 2c rather than this phase.
2. **`verify_jwt` for `drain_reminders`** (carry-forward #3) must be decided
   before the drain is ever scheduled. Not touched here.
3. **Handle uniqueness UX** — the schema enforces a unique `handle`, and every
   account starts with a valid placeholder one, so onboarding is renaming rather
   than naming. It still needs a taken-handle branch on the 23505. Whether that
   is a live availability check or submit-and-recover is a Phase 2b
   implementation-plan decision, not a spec one.
