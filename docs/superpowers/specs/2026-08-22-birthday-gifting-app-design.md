# Birthday Gifting App — Design

Date: 2026-08-22
Status: Approved for implementation planning

## 1. Product

A social app for birthdays. You keep a list of people you celebrate; the app
reminds you when their day comes; you can send them a cake, delivered to their
door, without ever seeing their address.

The social vocabulary mirrors Instagram's:

- **Celebrating** — people whose birthdays you track.
- **Celebrates** — people who track yours.

The two flows that matter: a reminder that arrives in time, and a cake that
arrives on the day.

## 2. Decisions

| Question | Decision |
|---|---|
| Fulfillment | Concierge. A human on the team places every order with a bakery. |
| Delivery address | Recipient confirms address and slot per gift. Sender never sees it. |
| Social graph | Phone-contacts import. You may celebrate people who are not users. |
| Payment model | One sender, one cake. No group pooling in v1. |
| Stack | Flutter app, Supabase backend, Flutter web ops console. |
| First release | Reminder-first: the app is useful before any cake is sold. |
| Launch scope | One city, hard daily order cap, hard confirm cutoff. |

### Why reminder-first

Every alternative has a dead first week. A contacts-based reminder app is
useful to a user with one contact. Gifting then supplies both the revenue and
the growth loop: sending a cake to a non-user brings that person into the app
through the address-confirm link.

### Why concierge

Sourcing cakes through an API or a partner bakery network are both real builds
with real coverage constraints, and neither answers the only question that
matters yet: will anyone pay to send a cake to a friend. Concierge answers it
with zero integration work. It does not scale past one city, and that is an
accepted constraint of v1, not a defect to fix later.

## 3. Modules

| Module | Owns | Depends on |
|---|---|---|
| Identity | Auth, profile, own birthday, handle | — |
| Graph | People, celebration edges, contact resolution | Identity |
| Calendar | Upcoming birthdays, reminder scheduling | Graph |
| Wish wall | Messages on someone's day | Graph |
| Catalog | Cakes, prices, city availability | — |
| Gifting | Checkout, payment, gift state machine | Graph, Catalog, Address vault |
| Address vault | Recipient addresses, slot choice, disclosure rules | Identity |
| Ops console | The human fulfillment layer | Gifting, Address vault |
| Notifier | Push and SMS fan-out | — |

Each module owns its tables and exposes a repository interface to the app. No
module reads another's tables directly from the client.

## 4. Data model

### 4.1 Profiles and people

The central modeling decision: **accounts and celebratable humans are separate
things.**

- `profiles` — one row per account. Handle, display name, date of birth, city,
  avatar. Backed by `auth.users`.
- `people` — one row per celebratable human, keyed on a normalized phone
  number. Created either when a user signs up or when someone imports the
  number from their contacts. `profile_id` is null until the person claims the
  row by signing up with that number.
- `celebrations` — the edge. `(celebrator_profile_id, person_id)`, unique, with
  a per-celebrator nickname and an import source. "Celebrating" is a select by
  celebrator; "celebrates" is a select by person.

Celebration edges point at `people`, never at `profiles`.

**Why:** when two users import the same cousin, both must land on the same
`people` row. Otherwise her birthday wall splits in two, two senders each send
a cake unaware of the other, and when she finally installs the app she inherits
no history. Phone-keyed people rows make the graph converge before anyone signs
up, which is the mechanism that makes the reminder-first release work.

**The cost being accepted:** `people` stores birthdays and phone numbers for
humans who never consented, because a friend typed them in. Section 6 is the
obligation that comes with that.

### 4.2 Gifting and fulfillment

- `products` — cake catalog. Name, size, flavour, price, image, and the
  service area it is available in. In v1 there is exactly one service area, so
  the sender browses one catalog at one set of prices. The per-area column
  exists so a second city does not require a migration.
- `gifts` — sender profile, recipient person, occasion date, product, amount,
  message, status, payment reference.
- `addresses` — owned by a profile. Lines, city, pincode, geo, label.
- `delivery_slots` — per city, per date, per window, with a capacity count. The
  daily cap lives here.
- `orders` — the ops-side record for a gift: bakery, cost paid to bakery, notes,
  courier, tracking. Ops-only.
- `wishes` — author profile, subject person, text, created at.
- `suppressions` — phone hashes that must never be re-imported (section 6).
- `address_access_log` — every ops read of an address.

## 5. Gift lifecycle

```
draft → paid → awaiting_confirm → confirmed → placed → out_for_delivery → delivered
                     │                 │                        │
                  expired            declined              delivery_failed
                     └──────────── all → refunded ──────────────┘
```

Rules:

1. **Every transition happens server-side**, in an Edge Function. RLS grants
   the client no direct insert or update on `gifts`. A client that can move its
   own order to `delivered` is a fraud hole.
2. **Charge at checkout; refund on any failure branch.** Simpler and more
   honest than authorization holds, and workable with Indian payment rails. A
   recipient who never confirms costs the sender nothing and requires no
   support ticket.
3. **Slot inventory is reserved inside the payment transaction**, not at
   confirmation time. Reserving late oversells a Saturday the kitchen cannot
   serve. Expiry releases the slot.
4. **Hard confirm cutoff.** The recipient must supply address and slot by a
   configured lead time before the delivery date, because ops needs the morning
   to place orders. Missing it moves the gift to `expired` and refunds it. The
   lead time is a config value, set per section 12.1.
5. **An address outside the service area refunds the gift.** The sender cannot
   know the recipient's city before they confirm — for a contact-imported
   non-user the app does not hold it either. So checkout states plainly which
   area is served, and a confirmed address outside it moves the gift to
   `declined` and refunds it, telling the sender only that delivery is not yet
   available there.
6. **`delivered` fires the social moment.** It auto-posts to the birthday wall:
   "<sender> sent a cake". This is the loop that makes other people send one.
7. **A decline is never reported as a decline.** The sender is told "expired,
   refunded" in both the ignore case and the decline case, and learns nothing
   about the recipient's intent.

## 6. Privacy contract

1. **Addresses are owner-readable only.** RLS on `addresses` permits select to
   the owning profile. There is no sender role on that table.
2. **The sender's gift view shows display name, city, slot window, and status.**
   No address line, no pincode, no phone number. The city appears only *after*
   the recipient confirms, and is the ceiling on what the sender ever learns
   about where they live. Before confirmation the sender sees no location at
   all — pricing does not require it, because v1 serves one area.
3. **Ops sees an address only while it is needed.** Service-role access gated
   on `gift.status in (confirmed, placed, out_for_delivery)`, and every read is
   written to `address_access_log` with staff id and gift id. That log is the
   only control standing between a second ops hire and a quiet data leak.
4. **Phone numbers are HMAC-hashed with a server-side pepper** as the
   resolution key, with a separately encrypted copy used only for sending SMS.
   No API response ever contains another person's number.
5. **Non-users confirm through a tokenized web page**, not the app. Single-use,
   short-lived token in the invite SMS, opening a plain web form for address and
   slot. A signup wall here would damage both conversion and delivery success.
6. **Every invite carries "not me / remove me."** One tap hard-deletes the
   `people` row and its edges and writes the phone hash to `suppressions`, so a
   later contact import cannot resurrect them. Without the suppression list the
   delete button is theatre.
7. **A non-user's birthday is never discoverable.** It is visible only to users
   who already held that contact. The app must never function as a lookup tool
   for a stranger's birthday or city.

Under India's DPDP Act the product is a data fiduciary processing people who
never signed up. Rules 3, 4, 6 and 7 are the compliance story, cheap to build
now and expensive to retrofit.

## 7. Application architecture

### 7.1 Flutter app

Standard project shape: an `api/` folder holding `endpoints`, `params`,
`connectivity`, and an abstract interface plus implementation per feature;
`app_colors`, `app_text_styles`, `app_strings` const files.

One deviation from the usual dio setup: implementations wrap the **Supabase
Dart client** and `functions.invoke`, since auth, realtime and RLS come with it.
The interface/implementation split is retained so the data source stays
swappable.

Widgets follow the house style: no one-off sub-widget extraction; extract only
what is reused or genuinely too large, and keep shared values in shared files.

Screens in v1:

1. Onboarding — phone OTP, then name, own birthday, handle, city
2. Contacts import — choose who you celebrate, fill missing birthdays
3. Celebrating — home timeline: Today / This week / This month
4. Person page — birthday, who else celebrates them, wish wall, Send a cake
5. Send a cake — service-area catalog, message, payment
6. My gifts — sent and received, with status
7. Confirm incoming gift — address and slot
8. My day — my wall, who celebrates me
9. Settings — address book, notifications, blocking, who may celebrate me

### 7.2 Backend

Postgres with RLS as the real security boundary. Six Edge Functions perform
every write that matters:

| Function | Job |
|---|---|
| `resolve_contacts` | Batch phone-hash to `people`, honouring suppressions |
| `create_gift` | Reserve slot, create gift, open payment |
| `payment_webhook` | Capture confirmation, move gift to `awaiting_confirm` |
| `confirm_gift` | Accept address and slot, from app session or invite token |
| `ops_transition` | Staff-driven status moves, with audit |
| `send_invite` | Tokenized SMS to non-users |

Three `pg_cron` jobs: reminder fan-out at T-7 / T-1 / T-0, the confirm-expiry
sweep with refunds, and the 6am ops manifest.

### 7.3 Ops console

A Flutter web app, reusing the app's models. Screens: today's manifest, gift
detail with address (logged on read), status transitions, refund trigger,
capacity editor for `delivery_slots`.

## 8. Testing

Three areas get tests before feature work, because they are where money and
privacy break:

1. **RLS policies.** pgTAP tests asserting that a sender selecting a
   recipient's address returns zero rows, that cross-user reads of phone
   numbers return nothing, and that a suppressed hash cannot be re-imported.
2. **Gift state machine.** Every transition and every failure branch, including
   double webhook delivery and refund idempotency.
3. **Slot-cap concurrency.** Parallel checkouts against the last remaining slot
   must produce exactly one paid gift.

Flutter unit and widget tests cover repositories and the confirm flow. TDD
applies to implementation.

## 9. Build order

| Milestone | Contents | Status |
|---|---|---|
| M0 | Schema, RLS, and their tests. No UI. Nothing else starts until green. | Done, 2026-08-23 |
| M1 | Auth, onboarding, contacts import, Celebrating timeline, reminder push, **person page, wish wall, and the profile**. Shippable alone. | Planned |
| M2 | *Folded into M1.* | — |
| M3 | Catalog, `create_gift`, payments, webhook, confirm flow, state machine, refunds. | Database half done in M0 |
| M4 | Ops console, 6am manifest, address access audit. | Database half done in M0 |
| M5 | Pilot: one city, daily cap, confirm cutoff, human review of every order. | Not started |

M1 absorbed M2 on 2026-08-24. Two reasons: a reminder with nowhere to tap is
just a notification, so wishing belongs to the milestone that ships reminders;
and the Instagram-style profile added in M1 counts wishes, which is meaningless
until wishes exist. See
`2026-08-24-m1-reminders-and-social-loop-design.md`.

The profile screen — `Celebrating | Celebrates | Wishes received`, both counts
tappable, plus a per-year track record — is new since this document was written
and is specified there, not here. It requires two policy changes to M0's
schema, because celebration edges were readable only by their owner and a
wish became invisible to its own author once the graph changed.

## 10. Not in v1

Group pooling. Feed, stories, explore. Profiles discoverable by strangers, and
any search that finds a person you have no edge to. Non-cake gifts. A second
city. Chat. Video wishes. Cake customization. Referrals. Ratings. A web app for
the social side.

Note, since this list originally read "public profiles and follower counts":
M1 does add celebrate counts and tappable Celebrating / Celebrates lists. That
is not the same feature. A profile is reachable only through an existing edge —
someone you celebrate, or someone who celebrates you — never through search or
an explore surface. `private.can_see_person` is what enforces the difference,
and a stranger's birthday stays undiscoverable, which is privacy contract §6
rule 7.

Each is a real feature. None changes whether the core loop works.

## 11. Pilot success criteria

The pilot exists to produce four numbers. Thresholds are set by the product
owner before launch, not derived here.

1. **Delivery success rate** — delivered / confirmed.
2. **Confirm rate** — gifts that receive an address before cutoff / gifts paid.
   A low number means the address flow is wrong.
3. **All-in cost per delivered cake** versus sender price. If this leaves no
   margin, concierge never graduates to a partner network.
4. **Repeat-send rate within 90 days.**

## 12. Open questions

None of these block M0–M2.

1. Pilot city, daily order cap, and confirm cutoff lead time — blocks M5.
   Needed as config values only; the schema does not depend on the numbers.
2. Payment provider selection and refund SLA — blocks M3.
3. SMS provider for invites — blocks M3.
4. Sender price points per cake tier — blocks M3.
