# M1 Phase 3 — App: The Social Loop

Date: 2026-08-29
Status: Approved for implementation planning
Parent spec: `docs/superpowers/specs/2026-08-24-m1-reminders-and-social-loop-design.md` §9, Phase 3
Predecessor: Phase 2b, merged to `main` at `91cf50d`

## 1. What Phase 3 is

Phase 2b made the app useful to one person: reminders you can act on. Phase 3 makes
it social. It closes the loop the parent spec opens with:

> A reminder arrives. You tap it. You wish them. Your profile and theirs both
> record it.

Phase 2b built everything up to "you tap it". This phase builds the rest.

## 2. Scope

**In:** the person page (their birthday, a celebrator count, their wall), wish
composing, the profile (header counts, two tappable lists, per-year track record),
the parent spec's single end-to-end test, and the `suppressed` oracle fix carried
from Phase 2b's final review.

**Out:** everything the parent spec §10 excludes. No cake or catalog — that is M3,
and `wishes.kind = 'cake'` stays unwritten by any client path here. No FCM, drain
cron or paid SMS — that is Phase 2c.

**A clarification from re-reading the parent spec:** §7.4 and §7.5 are not two
screens. §7.4 says the person page shows "their wall"; §7.5 is the *compose*
action. This phase builds **one screen plus a compose affordance**.

## 3. Decisions

| Question | Decision | Why |
|---|---|---|
| "Who else celebrates them" | **A count, never names** | The parent spec's line would expose a third party's follower list to anyone who imported their phone number. A count gives the same social-proof signal with a fraction of the privacy surface. |
| When may you post a wish | **Any time you celebrate them** | Already what `wishes_insert_own` enforces. A date restriction would need a new DB constraint — a client-side check would be theatre — and belated wishes are real behaviour. |
| `occasion_year` | **Derived by the client**, never asked | See §6. A year field on a screen that should be one text box and a button is a field most people would not understand. |
| Phase 2b debt | **Only the `suppressed` oracle** | The one genuine security finding. The other 24 deferred minors stay deferred. |
| Existing code | **Not migrated** | The principles in §4 govern code written from this phase onward. Retrofitting five cubits and four screens is its own project with its own risk. |

## 4. Design principles for new code

Phase 2b worked, but it accreted three avoidable inconsistencies. Phase 3 code
follows these rules; existing code is left alone.

### 4.1 One responsibility per repository (SRP, ISP)

`GraphRepository` was about to grow `celebratorCount`, `celebrates()` and `stats()`
on top of its timeline reads — three unrelated reasons to change in one interface,
and every consumer forced to depend on all of it.

Instead, three narrow interfaces:

- `WishRepository` — `wishesFor(personId)`, `post(...)`
- `ProfileRepository` — `stats()`, `celebrates()`, `celebrating()`
- `PersonRepository` — `person(personId)`, `celebratorCount(personId)`

`GraphRepository` is not touched. A cubit depends only on the interface it uses.

### 4.2 Dependencies are injected, never constructed (DIP)

The current codebase has **three different patterns across four screens**:
`SettingsScreen` and `TimelineScreen` take an optional repository but default to
`?? ConcreteImpl(ApiClient.instance)`; `ImportDisclosureScreen` hard-codes the
concrete class with no seam at all; only `AuthRepository` is properly provided.
That default-to-concrete pattern is the reason a widget test cannot mount those
screens without a live Supabase.

Every Phase 3 repository is registered once in `app.dart` under
`MultiRepositoryProvider` and read with `context.read<T>()`. **No `?? ConcreteImpl`
fallback, and no screen constructs a repository.** A widget test supplies fakes by
wrapping in `RepositoryProvider.value`.

### 4.3 Cross-cutting behaviour lives in one place (OCP, DRY)

The re-entrancy guard exists five times in three shapes: a state check in
`PhoneCubit` and `ProfileSetupCubit`, a `bool` in `ImportCubit`, and a keyed `Set`
in `TimelineCubit` and `SettingsCubit`. Each was rediscovered in review, and the
keyed-`Set` form — which permits concurrent actions on different rows — is strictly
the best of them.

Phase 3 extracts `ReentrancyGuard`, a mixin providing `guard(String key, Future<void> Function() body)`
which sets the key synchronously before the first `await` and clears it in a
`finally`. Every new cubit mixes it in. Existing cubits are not converted, but the
mixin is written so they could be, one at a time, later.

### 4.4 Domain rules are value objects, not scattered functions

`occasion_year` (§6) is not a helper buried in a cubit. It is a method on
`Birthday`, unit-tested with a fixed clock, sitting beside `nextOccurrence` and
`groupFrom` — which already encode the other two date rules this app depends on.

### 4.5 What these rules are not

They are not a licence to add layers. No service layer between cubit and
repository, no use-case classes wrapping single repository calls, no abstract
factory for one implementation. The parent spec's YAGNI stance stands: the rules
above each fix an inconsistency this project actually paid for.

## 5. Backend surfaces

Almost everything already exists. `public.wishes` and its three policies shipped in
M0; `public.my_celebrates()` and `public.my_birthday_stats()` shipped in M1 Phase 1;
`private.can_see_person` has had a "they celebrate me" branch since M0. Two changes
only.

### 5.1 New: `public.person_celebrator_count(bigint) returns int`

`security definer`, returning a number and never a name.

Two conditions, both load-bearing:

1. **The caller must be able to see the person** — `private.can_see_person(p_person_id)`.
   `people.id` is a sequential bigint. Without this, anyone could walk the id space
   and count any user's followers.
2. **Celebrators who have blocked the caller are excluded**, matching the rule
   `my_celebrates()` already applies to the viewer's own list.

Written test-first in pgTAP; both conditions proven by reverting them individually
and watching the specific assertion fail.

### 5.2 Changed: `add_celebrations` stops naming `suppressed`

Phase 2b's final review established that the function returns the literal string
`"suppressed"` per phone number in its `results` array, and that the endpoint
accepts 500 arbitrary numbers per request with no rate limit and no requirement
that the caller holds them in an address book. That is a bulk oracle for "did this
person ask to be forgotten" over the phone-number space. The client's refusal to
render the label is cosmetic; the HTTP response names it.

The fix relabels `suppressed` to `skipped`. The aggregate count is unchanged, so
the count inference already accepted in Phase 2b remains.

**This REDUCES the oracle; it does not close it, and the finding must not be
marked closed.** The original wording above assumed `skipped` would be a shared
bucket. It is not: this endpoint emits seven statuses and each has exactly one
cause, so `"skipped"` is still a 1:1 fingerprint for suppression. Anyone who
learns that mapping — by any means — regains the same bulk per-phone enumeration.
What the change removes is the self-explanatory word, which is worth having and
costs nothing, not the capability.

**The capability is dormant, not removed.** `private.suppress_person` has no Edge
Function caller anywhere in this project, so no suppression can be created through
the API and there is nothing yet to enumerate. `delete_account`'s own comment
records suppression as a distinct, planned future request type — so this reopens
in full the moment any client-reachable path to create one ships.

**The genuine fix belongs in that same change**, and there is no cheap version of
it now: every other status in the vocabulary is actionable and deliberately so
(`invalid_phone` and `invalid_name` name the contact precisely so the user can go
fix it), so there is no honest bucket to merge into. Closing it properly means
rate-limiting the endpoint, requiring the submitted numbers to plausibly come from
the caller's own address book, or not returning per-phone outcomes for skips at
all — and that last one collides with the `results.length == contacts.length`
contract the import screen zips against.

**Task 2's Deno test currently asserts the leaking string**, so it changes in the
same commit. The client's `ImportStatus.suppressed` enum member and the summary
screen's comments explaining why it is never rendered are updated with it.

## 6. `occasion_year`, stated precisely

**The birthday occurrence nearest to today, ties going to the past.**

A Dec 25 birthday wished on Jan 5 attaches to *last* December. The same birthday
wished on Dec 20 attaches to *this* December. Belated and early wishes both land on
the occasion the user meant, and nobody is asked a question they would not
understand.

This is a method on `Birthday` (§4.4), pure and clock-injected. The Feb 29 rule
already in `Birthday` applies unchanged: a Feb 29 birthday resolves through
`Feb 28` in non-leap years, so the client and the reminder fan-out continue to
agree.

A person with no birthday recorded cannot be wished — the compose affordance is
hidden, not disabled, because there is nothing the user could do to enable it from
that screen.

## 7. Screens and navigation

### 7.1 Person page — `/person/:personId`

Their name, their birthday, "N people celebrate them", and their wall newest-first.
Reached by **tapping a timeline row**, which currently does nothing — rows have
only an overflow menu.

The wall shows each wish's body, its author, and its occasion year. A wish the
viewer authored is always visible to them, even after un-celebrating the subject —
`wishes_select_visible` was fixed in Phase 1 for exactly this, because a track
record that forgets is not a track record.

**Author names need no new backend surface, but they do need a two-step read.**
`profiles_select_own` restricts `profiles` to `id = auth.uid()`, so the viewer
cannot read another author's profile at all. `wishes` carries only
`author_profile_id`, and there is no foreign key from `wishes` to `people`, so
PostgREST cannot auto-embed the author. The wall therefore loads its wishes, then
resolves authors in a second query against `public.people` on
`people.profile_id in (…)`.

RLS then does the right thing without any extra work: `people_select_visible` runs
`private.can_see_person`, whose three branches are *my own person*, *someone I
celebrate*, and *someone who celebrates me*. So an author the viewer is connected
to renders by name, and an author they are not simply does not come back — the
wish still renders, attributed to `AppStrings.wishAuthorUnknown`
("Someone who celebrates them").

This is a deliberate privacy outcome, not a limitation to work around: a wall
shows you the names of people already in your graph, and everyone else stays
unnamed. Do not add a function to expose the rest.

### 7.2 Wish composing — a sheet, not a route

Same reasoning that kept `/otp` unrouted in Phase 2b: the compose action needs the
person in memory, so a URL-addressable compose screen would render with nothing to
post to. It is a modal sheet on the person page: one text field, a character
counter against the 500-character DB limit, and a post button.

The insert is refused by RLS unless the caller celebrates the subject. The
affordance is therefore only shown for people the viewer celebrates, and the
error branch still exists for the race where they un-celebrate mid-compose.

### 7.3 Profile — `/profile`

Header: `Celebrating | Celebrates | Wishes received`. Reached from the timeline
AppBar, beside the settings gear.

Both first two counts are tappable, to `/profile/celebrating` and
`/profile/celebrates`. **Both list routes get a real back affordance.** Navigating
to a top-level route with `context.go` replaces the stack, so no back arrow renders
by default — that trap has now bitten this project twice, once on `/import` and
once on `/settings`.

Below the header, the per-year track record from `my_birthday_stats()`: one row per
year with wishes sent, wishes received, and birthdays celebrated. The third differs
from the first once a cake post and a typed message can both land on the same
person in the same year — dormant until M3, but the function already computes it
distinctly.

## 8. Testing

| Layer | Tool | Covers |
|---|---|---|
| `person_celebrator_count` | pgTAP, test-first | Both §5.1 conditions, each proven by reversion |
| `add_celebrations` | Deno | The updated status vocabulary; the old assertion changes with it |
| `Birthday.occasionYear` | `flutter_test` | §6, with a fixed clock — nearest occurrence, ties to past, Feb 29 |
| Cubits | `bloc_test` against fakes | Wall load and post, profile load, list loads |
| Repositories | Contract tests against **real local Supabase** | RLS on wishes, the count function, stats |
| Widget | `flutter_test` | The wall, and the compose sheet's 500-char limit |
| End to end | `flutter_test` | The parent spec's single E2E, finally writable |

The contract suites need one more test number — `+919999000007` — under the
one-number-per-suite convention Phase 2b established, because `flutter test` runs
files concurrently and a shared OTP identity produces failures in unrelated files.

Two standing rules from Phase 2b carry: **a green suite is not evidence** until the
new assertion has been watched to fail with its implementation reverted; and any
widget test counting screens passes `skipOffstage: false`, because Navigator marks
a covered route offstage and the obvious assertion silently passes against a
duplicate-push bug.

## 9. Build order

Vertical slices, each feature's repository contract-tested before its screen.

0. **Backend** — `person_celebrator_count` + pgTAP; the `add_celebrations` oracle
   fix + its Deno test update.
1. **Foundations** — `ReentrancyGuard` mixin, `Birthday.occasionYear`, and the
   `MultiRepositoryProvider` registration in `app.dart` for the new repositories.
2. **Person page** — `PersonRepository`, then the screen with the count and wall.
3. **Wish composing** — `WishRepository`, then the sheet.
4. **Profile** — `ProfileRepository`, then the header, the two lists, the track
   record.
5. **Close** — the end-to-end test, cold verification, ledger.

## 10. Risks carried into this phase

1. **No end-to-end run of the app has ever been completed.** An iOS App Transport
   Security defect survived 96 passing tests and died only when a human ran the
   simulator. Contacts import remains entirely unexercised — simulators carry no
   address book. The E2E test added here still runs on the Dart VM and does not
   close this. **Phase 2c must open with a physical-device run.**
2. **`resolve_contacts` returns `display_name` for up to 500 arbitrary numbers per
   request** — a name-enumeration oracle of the same shape as the one §5.2 closes.
   Pre-existing from Phase 2a and out of scope here, but it belongs in the same
   conversation and should not be forgotten because its sibling was fixed.
3. **`[auth.sms] enable_confirmations = true`** is a load-bearing security control
   guarded by nothing but a hand-check at each phase close, and `supabase init` or a
   CLI upgrade rewrites that file.
4. **24 deferred minors from Phase 2b** remain in that phase's ledger, including
   several pieces of dead code that read as a designed offline story which does not
   exist (`OfflineFailure`, `PermissionFailure`, `ApiConnectivity`,
   `connectivity_plus`, `fluttertoast` — all with zero callers).

## 11. Open questions

1. Whether "wishes received" should count `kind = 'cake'` posts once gifting
   exists. Dormant — M1 has no cakes.
