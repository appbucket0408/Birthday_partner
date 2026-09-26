# M4 Phase 1 — the ops console's live half

Design, 27 Sep 2026. Follows M3 Phase 1b.

## 1. What this phase is

A staff web console for the things that can be operated **today**: the catalog and
the delivery calendar. Three screens — sign in, service areas & products, delivery
slots — served from a second Flutter entry point built for web.

## 2. Why this is a split, and what was left out

The M0 spec's M4 lists five surfaces: today's manifest, gift detail with a logged
address read, status transitions, a refund trigger, and a slot capacity editor.

**Four of those five cannot show real data yet.** A manifest means gifts in
`confirmed` / `placed` / `out_for_delivery`, and the only transition into that region
starts at `paid` (`20260822000007_gifts.sql:79`). Payments are M3 Phase 2, blocked on
a provider account. Status transitions and refunds need gifts in flight for the same
reason; the gift-detail address read needs a `confirmed` gift before
`ops_get_delivery_address` will return anything at all.

The capacity editor depends on none of that. It is also the one surface with a
demonstrated need: M3 Phase 1a closed with the local seed unable to complete a gift
at all, because the only product sat in `Gurugram` while the only slot sat in
`Race Test Area`. Nothing in the app can fix that; this screen is how it gets fixed
with real data in a real city.

So **M4 Phase 1 ships the live half**, and M4 Phase 2 ships the manifest, gift detail,
status transitions and refunds when payments make them reachable. Three consecutive
phases have now closed with surfaces nobody can reach; this one deliberately does not.

**Explicitly not in this phase**, beyond the four above: no `orders` table surface
(it exists from M0 and stays unused until fulfilment is real); and **no staff
management** — `is_staff` remains a database-administrator action, as
`20260822000003_profiles.sql:42` insists, and no screen may set it.

## 3. The client: a second Flutter entry point

`lib/main_ops.dart`, built with `flutter build web -t lib/main_ops.dart`. This is the
project's **first web build target**, which is the unknown the M3 spec worried about
when it deferred one — so it lands here, on a small surface that is genuinely usable,
rather than on a larger one that is not.

Flutter web is right *here* and was wrong for M3 Phase 1b's confirm page, for a reason
worth stating so the two decisions do not look inconsistent: that page was a stranger
opening an SMS link once on a mid-range phone, where a multi-megabyte payload is the
whole cost. This is a known operator at a desk, on wifi, loading the console once and
working in it — where the payload amortises to nothing and reusing the app's models
and repositories is a real saving.

**Reused wholesale:** `ServiceArea`, `Product`, `DeliverySlot` (`lib/models/`),
`ApiClient` (`lib/api/api_client.dart`), `AppStrings`, `AppSpacing`, the
`ReentrancyGuard` mixin, and the Cubit + sealed-state pattern.

**Not reused:** the consumer `buildRouter`, `SessionCubit`, and anything contacts- or
phone-shaped. The console has its own small router and its own session notion.

## 4. Staff auth: email and password, admin-provisioned

The app signs in with phone OTP (`auth_repository_impl.dart:22`), which needs SMS —
blocked on an account, like payments. The console must not inherit that dead end.

`[auth.email]` is already enabled with `enable_confirmations = false`
(`supabase/config.toml:209`). That combination means **an admin-provisioned account
with a password sends no email at all**, so staff sign-in needs no SMTP and no
external account. It works today.

Provisioning is two administrator actions, outside the app and outside this console:

```
admin.auth.admin.createUser({ email, password, email_confirm: true })
update public.profiles set is_staff = true where id = '<uuid>';
```

Consistent with M0's design, where `is_staff` was always a DBA action.

**One hardening change to `config.toml`:** set `[auth.email] enable_signup = false`.
Today a stranger could self-register an email account. They would see nothing —
`is_staff` defaults false and every staff policy gates on `private.is_staff()` — but
they would occupy a row in `auth.users` with no `people` row behind it, which is
pollution the project has no path to clean up. With signup off, the only email
accounts that can exist are ones an administrator made.

**`config.toml` carries `[auth.sms] enable_confirmations = true` at line 252**, which
guards a reproduced total-account-takeover bug covered by no test, and
`supabase init` or a CLI upgrade rewrites that file. The task that edits it must
re-verify line 252 and paste the output.

### 4.1 The is_staff check is honesty, not the boundary

On successful sign-in the console reads the caller's own `profiles.is_staff`; if
false, it signs out immediately and says plainly that the account is not a staff
account. **This is not the security boundary.** Every staff policy
(`service_areas_staff_write`, `products_staff_write`, `delivery_slots_staff_write`,
`orders_staff_all`) gates on `private.is_staff()` server-side, so a non-staff session
that reached a console screen would see and write nothing. The check exists so the
refusal is legible instead of an empty screen.

## 5. A new repository, not a wrapper

`GiftRepository` already reads `serviceAreas()`, `productsIn()` and `slotsIn()` — but
**the console must not use them**, and the reason is specific rather than stylistic:

- `productsIn()` filters `.eq(is_active, true)`. Staff need to *see* inactive products
  in order to reactivate them; a console built on this read could never show the row
  it is meant to edit.
- `slotsIn()` takes a required `onOrAfter` bound and is shaped for a buyer picking a
  future window. Staff need arbitrary ranges, including past dates, to audit what was
  offered.

So `OpsRepository` (interface + impl, registered in the ops app's own
`RepositoryProvider`, **no `?? ConcreteImpl(...)` fallback**) owns both its reads and
its writes:

```
Future<List<ServiceArea>> allServiceAreas();
Future<List<Product>>     allProductsIn(int serviceAreaId);   // active AND inactive
Future<Product>           createProduct({...});
Future<Product>           setProductActive(int productId, bool isActive);
Future<List<DeliverySlot>> slotsBetween(int serviceAreaId, DateTime from, DateTime to);
Future<DeliverySlot>      createSlot({...});
Future<DeliverySlot>      setSlotCapacity(int slotId, int capacity);
```

`StaffAuthRepository` is likewise separate from `AuthRepository`, which owns phone OTP
and account deletion. Narrow repositories are this project's convention (SRP/ISP) and
mixing two auth mechanisms into one interface would be the wrong shape.

## 6. The screens

**Sign in** — email, password, submit. Errors surface through the established shape:
`on AppFailure catch (f)` then `catch (_)` with `AppStrings.somethingWentWrong`, never
`'$e'`.

**Service areas & products** — pick an area; list every product in it with name,
flavour, size, price and active state; create a product; toggle active. Price is
entered in rupees and stored as `price_minor` paise; `Product.priceLabel` already
renders the reverse (`lib/models/product.dart`), and the parse is its inverse, living
on the model beside it rather than in the screen.

**Delivery slots** — pick an area and a date range; list slots with `slot_date`,
`window_start`, `window_end`, `capacity` and `reserved`; create a window; change a
capacity.

**Capacity may never be set below `reserved`, and the database already enforces
that** — `delivery_slots_not_oversold check (reserved <= capacity)`
(`20260822000006_catalog_slots.sql:41`), alongside
`delivery_slots_capacity_non_negative check (capacity >= 0)` at `:38`. A staff update
that would oversell a real van is rejected by Postgres, not merely by this screen.

The console still refuses it client-side, for one reason only: the raw violation
arrives as SQLSTATE **`23514`**, which on this project is the *generic* CHECK-violation
code shared by seven explicit raises and every table constraint — the overload that
caused M3 Phase 1b's Critical bug, where a mistyped pincode was reported as an invalid
gift link. So the screen validates first and says plainly that capacity cannot go below
what is already reserved, and any `23514` that still reaches it is rendered as a
generic failure **and logged**, never as a guess about its cause.

## 7. Dates: one source of truth

M3 Phase 1b closed with a fixture that passed by day and failed by night, because it
derived "today" from Dart's clock while the database derived it from `current_date` —
Postgres runs UTC and the host runs IST, so the two disagreed for 5.5 hours nightly.

This console creates and edits `slot_date` values directly. **Every date it writes
must come from an explicit user choice or from a value read back from the database —
never from `DateTime.now()` on the client.** Tests must prove it under at least two
extreme timezones (`Pacific/Kiritimati`, UTC+14, and `Pacific/Midway`, UTC−11), the
technique that caught the original.

## 8. Testing

| Layer | Covers |
|---|---|
| Cubit, `bloc_test` | Each screen's load, mutate and failure paths against a fake `OpsRepository`; a non-`AppFailure` reaching `AppStrings.somethingWentWrong`; re-entrancy on every mutating action |
| Widget | The capacity-below-reserved refusal; the sign-in refusal for a non-staff account |
| Contract, real Supabase | **A non-staff caller is refused on every staff write** — the assertion that matters. Needs a staff user, which the API cannot create (`authenticated` has no update grant on `is_staff`, `20260822000003_profiles.sql:54`); use the `psql()` superuser helper, as `gift_repository_test.dart` already does |
| pgTAP | `[auth.email] enable_signup = false` cannot be asserted from SQL — see §9 |

**A green suite is not evidence.** Every new assertion is watched to fail with its
implementation reverted, then restored. M3 Phase 1b caught fourteen tests on this
project that passed against the exact bug they were written to catch.

## 9. Not verified by any suite

Stated up front rather than discovered later:

- **`[auth.email] enable_signup = false` is a gateway-level setting no test can
  reach**, exactly like `[functions.confirm] verify_jwt = false` in M3 Phase 1b. That
  one is covered by `supabase/functions/test-gateway.sh`, run manually against a
  server started without `--no-verify-jwt`. This setting needs the same treatment: a
  manual check that an email signup is refused, documented in the ledger.
- **The web build itself.** `flutter build web` producing a working bundle is not
  something the Dart-VM test suite can assert. The build must be run and the output
  loaded in a browser at least once before this phase closes — and that is a human
  step, like the device run.
- **No device or simulator run has ever happened, in any phase.** This phase adds no
  mobile screens, so it adds no new exposure there, but the standing risk is
  unreduced.
- **The `23514` mapping on this screen.** The database rejects an overselling
  capacity change (§6), but it does so with the same generic SQLSTATE as six other
  raises, so the console cannot tell *which* constraint fired from the code alone. The
  client-side check makes the common case legible; an unanticipated `23514` is logged
  rather than explained. This is the same overload carried forward from M3 Phase 1b.

## 10. Risks

1. **The first web build target.** New toolchain path, new output, a hosting decision
   deferred (this phase builds; it does not deploy). The mitigation is scope: three
   screens, all usable.
2. **`config.toml` edits** — the same file as the account-takeover guard at line 252,
   rewritten wholesale by `supabase init` and CLI upgrades.
3. **A console that writes catalog data has no undo.** Deactivating a product or
   shrinking a capacity takes effect immediately for every buyer. No soft-delete and
   no audit trail ship here; `address_access_log` covers address reads only.

## 11. Carried forward

- Everything M4 Phase 2 owns: manifest, 6am cron, gift detail with logged address
  read, status transitions, refunds.
- **`address_access_log.staff_profile_id` is `ON DELETE RESTRICT`** on a deliberately
  immutable table, so a staff member who has ever opened a gift's address can never be
  deleted. Inert until Phase 2 ships that read — and it is the same shape as the
  `gifts.sender_profile_id` regression M3 Phase 1a's final review caught, so Phase 2
  must decide the policy before shipping, not after.
- Narrowing the `23514` overload so a handler can tell one constraint from another
  (§9) — the project-wide item M3 Phase 1b also carried.
- M3 Phase 1b's open items: the `23514` overload on the Flutter client, spec §9's race
  row, `seed.sql`'s non-idempotent `products` insert and its NULL GoTrue columns.

## 12. Open questions

1. **Hosting.** This phase builds the bundle; it does not deploy it. Where the console
   is served from — Supabase static hosting, Netlify, a private S3 — is a Phase 2
   decision, and it carries an access question (IP allowlist? basic auth in front?)
   that is worth deciding once rather than twice.
2. **Whether the console should create service areas at all.** Adding a city is a
   business decision with pricing and coverage behind it, not an afternoon's data
   entry. This phase lists areas and edits products and slots within them; creating a
   new area stays a DBA action until there is a reason to change that.
