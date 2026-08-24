# M1 — Reminders and the Social Loop

Date: 2026-08-24
Status: Approved for implementation planning
Supersedes: the M1 and M2 rows of the product spec's §9 build order

## 1. What M1 is

M0 built the database and proved it. M1 builds the app that makes it useful,
and the loop that makes it social:

> A reminder arrives. You tap it. You wish them. Your profile and theirs both
> record it.

M1 ships that loop end to end. No cake is sold — gifting is M3 — but the app is
useful to a user with one contact, which is the reminder-first thesis from the
product spec §2.

## 2. Scope change from the product spec

The product spec's build order put the person page and wish wall in M2. M1 now
absorbs them, because a reminder with nowhere to tap is just a notification, and
because the Instagram-style profile below is meaningless until wishes exist to
count. M1 also gains a screen the product spec never had: **the profile**.

Net effect: M1 is roughly twice the milestone the product spec described, and
what remains of M2 is small enough to fold into a later milestone. §9 of the
product spec is updated to match.

## 3. Decisions

| Question | Decision | Why |
|---|---|---|
| Phone verification | Build the full OTP flow against Supabase's local test SMS provider | The paid provider becomes a config swap at first real-device test. Nothing stalls and no bill is incurred to write screens. Phone is not substitutable: the whole graph is keyed on `people.phone_e164_hash`. |
| State management | `flutter_bloc` Cubits as the viewmodel layer | Explicit loading/error/data states, which OTP, import and timeline all need; `bloc_test` covers the required repository tests. Matches the house `view → viewmodel → service → api` layering. |
| Contacts import | Bulk resolve, **create on select** | `resolve_contacts` hashes server-side and matches only. A `people` row is minted only when the user picks someone, so importing does not mint thousands of rows for non-consenting contacts. |
| Birthday storage | `birth_month` + `birth_day` required together, `birth_year` nullable | Device contacts routinely carry a birthday with no year. Reminders only ever need month and day; age is the optional extra. |
| Feb 29 in non-leap years | Fires on **Feb 28** | Keeps the celebration inside February rather than sliding into March. |
| Reminder delivery | `pg_cron` → `private.notification_outbox` → thin Edge Function → FCM | Puts the scheduling logic, where the bugs are, under pgTAP. Keeps Edge Functions thin wrappers, matching M0. |
| Celebrates list | Full list, Instagram parity, blocked users excluded | This is the growth mechanic: seeing who remembered you is what makes you remember them. |
| Local database | None | The timeline reads through the Supabase client with a per-session cache. A local store would be speculative in M1. |

## 4. Data model changes

### 4.1 Birthday model

On **both** `public.people` and `public.profiles`, replace the single `date`
column (`birthday` / `date_of_birth`) with:

- `birth_month smallint`
- `birth_day smallint`
- `birth_year smallint` — nullable

Constraints:

- month between 1 and 12; day between 1 and 31
- day valid for the month, with **February allowing 29** so a year-less leap
  birthday is storable
- month and day are present together or absent together
- when `birth_year` is present: between 1900 and the current year, and Feb 29
  only pairs with an actual leap year

Index `(birth_month, birth_day)`. This makes the reminder query an equality
lookup — cron computes today, today+1 and today+7 and matches month and day
directly. No date arithmetic, and no December-to-January wraparound problem.

Rewires `private.upsert_person`, `private.claim_person` and
`private.sync_person_from_profile`, and drops `people_birthday_sane` and
`profiles_dob_sane`.

**Blast radius, measured:** 2 migrations, 5 test files and `seed.sql` — 22
references, and `tests.create_person`'s signature changes. M0's 96 assertions
passing afterwards is Phase 1's acceptance gate, not a footnote.

### 4.2 Push and reminder tables

`public.device_tokens` — `profile_id`, `token` (unique), `platform`,
`last_seen_at`. Owner-only RLS: the app registers its own token directly,
because a user's own device token needs no server mediation.

`private.notification_outbox` — deliberately **not** in `public`. Nothing
client-side reads it, and the `private` schema is invisible to PostgREST, so it
cannot be reached through the API at all. Columns: recipient profile, subject
person, `offset_days` (7 / 1 / 0), `occasion_date`, `sent_at`, `attempts`,
`last_error`, and:

    unique (recipient_profile_id, subject_person_id, occasion_date, offset_days)

That constraint **is** the no-double-send guarantee. A cron re-run or a retry is
inherently safe rather than safe by convention.

### 4.3 Policy changes

1. **New `celebrations_select_incoming`** on `public.celebrations`: read edges
   where `person_id = private.my_person_id()`, excluding any celebrator the
   viewer has blocked. Without this the Celebrates count is unreadable —
   `celebrations_select_own` exposes only outgoing edges.
2. **Fix `wishes_select_visible`** to
   `author_profile_id = auth.uid() OR can_see_person(subject_person_id)`.
   As written in M0, un-celebrating someone erases your own past wish to them
   from your history. A track record that forgets is not a track record.
3. **Extend the private-schema function allowlist** in `01_private.test.sql` for
   any new `private` function, per the standing M0 obligation.

Names for both lists need no new policy. `private.can_see_person` already has a
third branch — "they celebrate me" — built in M0 for the person page, which
makes celebrators readable.

### 4.4 Stats

`public.my_birthday_stats()`, `security invoker` so RLS still applies, returning
one row per year with three counts, defined exactly:

- **wishes sent** — rows in `wishes` where I am the author
- **wishes received** — rows in `wishes` where the subject is my person
- **birthdays celebrated** — *distinct* subject people I wished that year, which
  differs from wishes sent once a cake post and a typed message can both land on
  the same person in the same year

PostgREST aggregate support is inconsistent across versions, and a function is
testable in pgTAP as a real user rather than as `postgres`.

## 5. Backend surfaces

| Surface | Job |
|---|---|
| `resolve_contacts` (Edge Function) | Batch phone → hash → **match only**, honouring `private.suppressions`. Creates nothing. |
| `drain_reminders` (Edge Function) | Read unsent `notification_outbox` rows, send to FCM, stamp `sent_at` or record `attempts` / `last_error`. |
| `pg_cron` reminder fan-out | Daily. For T-7, T-1, T-0, insert one outbox row per celebration edge whose subject's `birth_month`/`birth_day` matches that target date, addressed to the **celebrator**, then trigger the drain. Edges whose subject has no birthday recorded are skipped, not queued with a null date. |

Raw phone numbers transit to `resolve_contacts` over TLS and are never stored
raw and never written to disk. The pepper stays in `private.config`, which is
the reason hashing cannot happen on the device.

## 6. Application architecture

```
lib/
├─ core/          app_colors, app_text_styles, app_strings, app_spacing, logger
├─ api/           api_connectivity, api_endpoints, api_params,
│                 api_client (Supabase singleton), interceptor/
├─ models/        profile, person, birthday, celebration, wish
├─ repositories/  auth, graph, wish, notifications — interface + impl each
├─ features/      onboarding, contacts_import, timeline, person, profile, settings
│                 (each: cubit + state + screen, layout inline)
└─ widgets/       only what is genuinely reused
```

`app_strings.dart` holds all user-facing copy; no literals in screens. Widgets
are not extracted into one-off classes — only what is reused or genuinely too
large.

Two deliberate departures:

- **Per-feature service interfaces rather than one.** The house convention has a
  single `api_service_interface` + `api_service`; at seven screens that becomes a
  god object, so `api/` keeps the cross-cutting plumbing and each feature owns
  its interface and implementation.
- **Supabase Dart client rather than dio**, per product spec §7.1 — auth, RLS and
  token refresh come with it. The interface split keeps the data source
  swappable.

Also: `go_router` (M3's tokenized confirm link is a deep link; retrofitting is
worse than adopting now); `firebase_messaging` with the `device_tokens` row
**deleted on sign-out**, or a signed-out device keeps receiving someone's
reminders; `phone_numbers_parser` for E.164 normalization against the country
captured at onboarding; contacts read via `flutter_contacts` in batches of ~500.

A prominent-disclosure screen precedes the OS contacts prompt. Play requires it,
and permission declarations are historically where releases get blocked.

## 7. Screens

1. **Onboarding** — phone OTP, then name, own birthday, handle, city
2. **Contacts import** — disclosure, permission, pick who you celebrate, fill
   missing birthdays
3. **Celebrating timeline** — Today / This week / This month, with edit-birthday
   and stop-celebrating inline on a row
4. **Person page** — their birthday, who else celebrates them, their wall
5. **Wish wall** — post a message on someone's day
6. **Profile** — header `Celebrating | Celebrates | Wishes received`, both counts
   tappable to real lists, and a per-year track record below
7. **Settings** — notification toggle, sign out, delete account

## 8. Testing

Phase 1 is pgTAP, following M0's discipline: implement the migration, then let
the tests find the defects.

New assertion groups, with the cases expected to break:

- **Birthday constraints** — month and day required together or neither; Feb 29
  accepted year-less; Feb 29 with a non-leap year rejected; Apr 31 rejected
- **Reminder due computation** — **December-to-January wraparound** (today
  Dec 28, T-7 must match Jan 4) and **Feb 29 → Feb 28** in non-leap years
- **Outbox idempotency** — run the fan-out twice, assert exactly one row, so the
  unique constraint is proven to be doing the work
- **`celebrations_select_incoming`** — I see who celebrates me; a blocked
  celebrator is excluded; edges between two strangers stay invisible
- **`wishes_select_visible`** — an author still sees their own wish *after*
  un-celebrating the subject
- **`my_birthday_stats()`** — called as a real user under RLS, not as `postgres`
- **`device_tokens`** — another user can neither read nor write my token row

Two standing obligations inherited from M0, both easy to forget:

1. Any new `private` function extends the allowlist assertion in
   `01_private.test.sql`. That guard caught five leaked functions during M0.
2. `11_rls_coverage.test.sql` scans only `public`, so
   `private.notification_outbox` could ship with RLS off unnoticed. Phase 1
   extends it to `private`. All three existing private tables already have RLS,
   so the extension passes immediately and guards the new table.

Phases 2 and 3, split by what fakes can and cannot prove:

- **Cubit tests with `bloc_test` against fakes** for state transitions — OTP
  retry, import progress, timeline grouping
- **Repository contract tests against the real local Supabase.** Deliberate:
  M0's evidence is that fakes hide exactly the RLS and privilege failures that
  cost the most. `private.can_see_person` alone broke three separate ways, and a
  fake repository would have passed every one
- **Widget tests** for the three riskiest screens only: OTP entry, import
  selection, timeline grouping
- **One end-to-end test**: sign in → import → timeline → wish → profile counts
  tick

Reminder scheduling and the two policy changes are written test-first, per the
product spec's principle that the money-and-privacy areas get tests before
feature work. No golden tests in M1 — the visual design is not settled enough
for them to be anything but churn.

## 9. Phasing

Three implementation plans, executed and merged in order.

**Phase 1 — Data and backend.** No UI, all pgTAP. The birthday-split migration,
push tables, the policy changes, `resolve_contacts`, `drain_reminders`, the
`pg_cron` fan-out, and the M0 regression sweep. This goes first and goes green
before any screen exists: it is the only work that touches existing M0
functions, and M0 proved that is where the defects live.

**Phase 2 — App: identity and graph.** Flutter scaffold, phone OTP onboarding,
contacts import, Celebrating timeline, Settings. Reminders land on a real device
by the end of this phase.

**Phase 3 — App: the social loop.** Person page, wish wall, and the profile with
its header counts, tappable lists and track record.

## 10. Not in M1

No cake, catalog, payment, or address confirmation — that is M3, and M0 already
built and tested its database half. No ops console (M4). No SMS invites to
non-users (M3). No group pooling, ever, in v1. No local database, no golden
tests, no realtime subscriptions.

Also explicitly not in M1: **no notification when someone starts celebrating
you.** Only birthday reminders are sent. A "X now celebrates you" push is the
kind of thing that reveals an import to its subject, and it deserves its own
decision rather than arriving as a side effect of the Celebrates list.

## 11. Open questions

None block Phase 1.

1. SMS provider selection — blocks the first real-device OTP test, not the
   build. The product spec lists this as blocking M3; it actually surfaces here
   first.
2. Firebase project and FCM credentials — blocks the first real-device reminder,
   not the outbox logic, which is fully testable without them.
3. Copy and visual design for the seven screens — needed during Phase 2, not
   before.
4. Whether "wishes received" counts `kind = 'cake'` posts alongside typed
   messages once gifting exists in M3. M1 has no cakes, so the question is
   dormant.
