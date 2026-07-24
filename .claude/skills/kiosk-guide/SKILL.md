---
name: kiosk-guide
description: >-
  The single source of truth for CRM KIOSK MODE — the member-facing self-serve
  surface that runs on a gym's front-desk iPad INSIDE the authenticated CRM.
  Covers the mount boundary (kiosk replaces the admin workspace at the auth
  gate; entering keeps the admin session, LEAVING signs out), the synchronous
  `restoring` state + non-lazy provider that closes the reload seam, the
  absolute 12-hour server-anchored runway (lockout at T+11h45, grace, hard
  revoke at T+12h) and its fail-closed persistence, the beginFlow/endFlow
  balance contract and the single `goHome()` abandon path, the fresh-card law
  and the structural no-discounts rule, the TWO rejection shapes (a 200 with
  `skip_reason` vs a thrown error carrying a stable `code`), the TWO separate
  class lists (check-in window vs the forward-looking showcase), the four
  gym-wide catalogues warmed once at entry, the four independent timers, the
  kiosk type ramp / AA contrast / fixed QR polarity design laws, and the
  real-vs-illustrative data rule. Load this whenever you touch anything
  kiosk-shaped: `CRM/lib/features/kiosk/`, `auth_gate.dart`'s kiosk branch, the
  `is_member: true` check-in call, the "Get the app" modal, the kiosk QR, or
  the unbuilt Phase D/E signup and Phase G rotating check-in QR. Trigger on
  "kiosk", "front-desk iPad", "self check-in", "the glance", "get the app
  modal", "fresh-card law", "12-hour runway", "beginFlow / endFlow",
  "skip_reason", "kiosk type ramp", or "rotating QR".
---

# Kiosk Mode — a member surface inside the admin app

This is the deep domain knowledge for CombatDen's **Kiosk Mode**. It is the
**source of truth** for how the kiosk behaves; `CRM/CLAUDE.md` holds only the
"how to work here" pointer. When the kiosk changes, **update this skill in the
same change** (it is a living document — see the bottom).

**The shape in one breath.** A gym's front-desk iPad runs the ordinary CRM web
app. A staff member with `canOperateKiosk` taps *Kiosk Mode* in the nav rail,
confirms, and the authenticated app swaps the whole admin workspace for
`KioskScreen` — a full-viewport member surface with no nav rail, no admin route
table, and no way back except signing out. A member walks up, finds their name
(or, in Phase G, scans a QR), picks their class, gets checked in, and sees a
retention **glance** — their streak, their points, this gym's reward tiles —
before the screen resets for the next person.

**Why it exists.** Two reasons, both product, both load-bearing:

1. **Retention.** The check-in is the one moment every member touches the gym's
   system. The glance turns a transaction into a payout — streak, points,
   rewards within reach — which is the retention layer the whole product sells.
2. **App adoption, placed deliberately.** The member app is the long-term
   engagement surface, and the kiosk is the highest-intent place to hand it
   over: the member is standing there, just did the thing, and is looking at
   what they earned. Hence the "Get the app" modal, the spanning adoption strip
   on the home, and the app nudge in the glance's rewards panel. The standing
   rule is **always nudging, never nagging** — every nudge sits below the thing
   the member came for, and no failure path ever hides behind one.

Everything below is the set of rules that keep those two things from becoming a
security hole, a mis-billing, or a screen that lies to a member.

---

## 1. The security model

The kiosk is an unattended member surface running inside an app whose session
can charge cards. The entire security design is one boundary plus one clock.

### 1.1 It mounts INSTEAD of the admin workspace

`CRM/lib/features/login/presentation/screens/auth_gate.dart` — inside the
authenticated branch, once a gym is active, the gate reads the app-root
`KioskSessionCubit` and routes on `KioskStatus`:

| status | what the gate mounts |
| --- | --- |
| `restoring` | `LoadingScreen` — a neutral loader, **never** the workspace |
| `active` / `locked` | `KioskScreen` |
| `ended` | `KioskLockedScreen` (fail-closed terminal) |
| `inactive` | `_MembersWorkspace` (the normal admin app) |

So while kiosk is up, `_MembersWorkspace` never builds: the nested `Navigator`,
the admin route table, and `AppShell` are not in the tree at all. A member
cannot reach an admin route because no admin route exists to reach. This sits
**outside and above** the workspace's own role gating — entering kiosk is itself
a staff capability (`RolePolicy.canOperateKiosk`, owner / admin / front desk),
gating the nav item, and nothing inside the kiosk consults a role again.

The kiosk branch lives **inside** the authenticated branch on purpose: the
persisted kiosk flag is only ever honored while a Supabase session exists, so a
flag without a session is inert and falls through to the login screen.

### 1.2 Entering keeps the session; LEAVING signs out

This is the core property. `KioskSessionCubit.enterKiosk()` flips a cubit — the
admin's Supabase session and `selectedGym` stay live underneath, which is what
lets the kiosk make authenticated backend calls at all. `exitKiosk()` does one
thing: **dispatch a sign-out**. The discreet padlock in the header
(`widgets/kiosk_exit_lock.dart`) confirms first ("This signs the iPad out"),
then calls it.

A member CAN press the padlock and sign the iPad out. That is accepted
(founder ruling): the worst outcome is a nuisance drop to the login screen —
never the admin workspace.

### 1.3 Durable before active — and no admin flash on reload

Two seams, both closed, both easy to reopen by accident:

- **`enterKiosk` awaits the flag persist BEFORE emitting `active`.** A reload in
  the microtask gap would otherwise catch a live kiosk whose flag was never
  written, and the next boot would restore straight into the admin workspace
  (fail-OPEN). A failed save does **not** enter — the state is left untouched
  and the admin keeps the workspace. The nav-rail caller (`_confirmEnterKiosk`
  in `shared/widgets/navigation/nav_actions.dart`) `await`s it for this reason.
- **The cubit's synchronous initial state is `KioskStatus.restoring`**, and the
  provider in `main.dart` is **`lazy: false`**. Together these guarantee that
  when the gate first reads the cubit it is already restoring rather than
  reporting a pre-restore `inactive` — and the gate renders a neutral loader for
  `restoring`, so a boot / reload / refresh cannot flash an admin screen (and
  fire its backend fetch) at a URL fragment frozen in the address bar.
  `_restore` resolves `restoring` → `inactive` when nothing is persisted, so a
  genuine admin still reaches the workspace once the read completes.

**Never make the kiosk provider lazy, and never give the cubit a non-`restoring`
initial state.** Both are the same reopened hole.

### 1.4 The 12-hour runway — absolute, never extended

Entry pins an **absolute deadline** = `now + runway` (12h). Member interaction
never moves it: a forgotten or stolen iPad always loses access within the
runway. Two timers ride it (`_scheduleTimers`):

- **Lockout** at `deadline − graceWindow` (T+11h45): block *new* flow starts.
  If nothing is mid-flow → sign out now, 15 minutes early. If a flow is in
  progress → emit `locked` and let that one ride.
- **Hard revoke** at `deadline` (T+12h): `_endSession()` unconditionally —
  emit `ended`, drive a sign-out.

`KioskFlowCubit.selectMember` gates on `KioskSessionState.canStartFlow` (true
only while `active`); past lockout it routes to the calm `KioskView.closing`
screen and never begins the flow.

### 1.5 The runway is anchored to the SERVER clock (SEC-3)

`data/kiosk_server_clock.dart` — `KioskServerClock.serverNow()` issues a cheap
`GET /health` through `ApiClient` and parses the HTTP `Date` response header
(RFC 7231 IMF-fixdate, always GMT). On web the browser can only see that header
because the backend's CORS config sets `expose_headers=["Date"]`.

Both the **entry pin** and the **restore expiry check** read it. A supervised
iPad whose clock is rolled *back* therefore cannot read "still before the
deadline" and stretch the member surface past its true T+12h. Live-session
timers are duration-based (monotonic), so the exposure only ever existed across
a reload.

Fallbacks are asymmetric on purpose:

- **At entry**, an unreachable server clock falls back to the device clock —
  staff is physically present, so an untampered device clock is an acceptable
  baseline.
- **At restore**, it **fails closed**: if the server clock is unavailable AND
  the device clock already places us at/past the lockout mark, end the session
  rather than trust a possibly-rolled-back clock. A comfortably-early offline
  reload still resumes (otherwise an offline kiosk could never come back).
- Restoring *inside* the grace window restores straight to `locked` (the
  idle-sign-out is a property of the lockout **transition** on a live session,
  not of restore); the still-scheduled hard-revoke timer bounds it.

### 1.6 Fail-closed persistence

`data/kiosk_session_store.dart` writes two `shared_preferences` keys —
`kiosk_active` and `kiosk_deadline` (epoch-ms UTC). On Flutter web that is the
**same browser localStorage the Supabase session lives in**: a deliberate
*fate-share*, so a wiped storage takes both, and a flag can never outlive its
session.

The clear point is gated. `exitKiosk` signs out **first** and touches nothing;
persistence is cleared only by `handleSignedOut()`, and only once
`_sessionGone()` confirms the Supabase session is genuinely gone. A failed
sign-out therefore keeps the flag and keeps the iPad on the kiosk screen —
never drops it into admin. `main.dart` wires the trigger: a `BlocListener` on
`LoginUnauthenticated` calls `handleSignedOut()`.

### 1.7 What the app does NOT enforce

**Guided Access (or MDM kiosk mode) is the operational assumption.** Nothing in
Flutter can stop a member from leaving the browser, opening a new tab, or
reading the address bar; the iPad is expected to be locked to the app by iOS.
Every in-app rule above is written to hold *given* that assumption, and to fail
safely when it doesn't (the worst in-app outcome is a drop to login). Do not
propose an in-app "lock the browser" mechanism — it does not exist; do not
weaken an in-app rule on the grounds that Guided Access covers it either.

---

## 2. `beginFlow` / `endFlow` — the balance contract

**Exactly one `endFlow()` per `beginFlow()`, on EVERY exit path.** This is the
single easiest thing to break in the kiosk and the breakage is silent.

`KioskSessionCubit` keeps an in-memory `_flowCount` (`beginFlow()` increments,
`endFlow()` decrements, clamped at zero). It exists for exactly one decision: at
the T+11h45 lockout, is anyone mid-flow?

- `_flowCount == 0` → sign out immediately (15 min early).
- `_flowCount > 0` → emit `locked`, grant the grace window.

`KioskFlowCubit` brackets a flow with `_startFlow()` / `_endFlowIfStarted()`,
guarded by a `_flowStarted` bool so the pair can never double-count. Begin
happens in `selectMember`; end happens on **every** terminal:

- a recorded check-in (the glance),
- a gate rejection or a failed call (the blocked screen),
- `goHome()` — the abandon path,
- `close()` — a mid-flow teardown (`endFlow` is a pure in-memory decrement, safe
  post-close).

**If a new exit path skips `endFlow`, the count leaks permanently and the kiosk
never signs itself out at lockout.** The iPad then sits on a member surface past
the runway it was supposed to be bounded by. There is no self-healing: a reload
resets the count to 0, which is correct only because a reload kills any
in-flight flow anyway.

### `goHome()` is the ONE abandon path

`KioskFlowCubit.goHome()` **is** the whole abandon contract:

1. cancel the search debounce, the glance timer, the app-modal timer;
2. bump `_searchSeq` / `_classesSeq` / `_glanceSeq` so every in-flight fetch is
   dropped;
3. `_endFlowIfStarted()`;
4. `_pruneShowcaseClasses()` (see §6);
5. emit `_freshHome` — a clean home that keeps the gym-wide catalogues;
6. re-arm the idle guard.

Every abandon routes through it: the glance's **Done**, the 5-minute idle
timeout, the app modal's **expiry** (never its Done — see §7), and the class
pick's escape foot.

**Never hand-roll a second abandon path.** One that skips `endFlow` leaks the
flow count (above); one that skips the sequence bumps lets a late fetch paint
the previous member's data over the next person's home.

### The escape / cancel contract

**The problem it solves.** A member who tapped the WRONG NAME on the home landed
on the class pick with **no way back** — stranded there until the 5-minute idle
timeout fired. There was no escape affordance anywhere on the kiosk. The
contract below is the fix, and it governs every flow screen the kiosk will ever
have (Phase D/E signup included).

**1. Ghost tier, bottom-LEFT gutter.** The escape is a `KioskGhostButton` — no
border, no fill, `text2nd` label — sitting alone in the left gutter of a
hairline footer band, **deliberately far from the primary action**. On a
finger-driven kiosk a mis-tap that destroys a half-entered signup is far worse
than a longer reach, so distance is the safety mechanism. Ghost is the **escape
tier**: it is an escape hatch, not a call to action, and it is demoted by
WEIGHT rather than size (it keeps 17px — a member still has to find it from 2m).

**2. The wording answers the SCREEN, not the navigation.** The class pick reads
**"‹ Not {FirstName}?"** because the heading one line above asserts "Hi
{FirstName}, pick your class" — the escape must answer that assertion. A generic
"Back" makes a flustered member work out what it means. In the signup flow the
equivalent is **"↺ Start over"**, deliberately **NOT** "Cancel": beside a
`Pay $149.00` button, "Cancel" reads as *cancel the payment*. Every new escape
gets its wording from the sentence it is answering.

**3. Wire it to `goHome()` — never write a second abandon path.**
`KioskFlowCubit.goHome()` already IS the whole abandon contract (timers
cancelled, the search / class / glance sequence counters bumped so in-flight
fetches are dropped, `_endFlowIfStarted()` called, a fresh home emitted with the
member / query / results wiped). An escape is a button wired to it — zero cubit
work. A hand-rolled second path leaks the flow count or paints the last member's
data over the next person (§2 above).

**4. Confirmation is proportional to what is lost.** The class-pick escape takes
**none**: nothing typed, nothing written, no charge, and the member has already
mis-tapped once — a confirm dialog would be a second trap. The signup flow's
early steps likewise abandon on first tap (at most ~20 seconds of retyping). A
confirm appears only where real work dies: the card step and the solo / group
review steps (reusing the shipped `kiosk_idle_warning` composition, with the
safe choice as primary).

**5. Some screens deliberately have NO escape at all**, and this is the rule
that matters most:

> **An escape that would orphan committed state is replaced by a handoff, never
> added alongside one.**

- **The Paying screen** — a Stripe charge is in flight. Abandoning mid-charge
  can strand a member who paid with no record of it.
- **Terminal front-desk stops** (the duplicate-payer stop, the no-Stripe-account
  stop) — they ARE the handoff; an escape beside one just offers a way to skip
  the resolution.
- **The Declined screen**, most sharply. By that point a member row, a Stripe
  customer and a signed waiver are all committed and nothing rolls back. A
  "Start over" there would silently orphan all three: the member walks off
  believing they joined, and their own second attempt is then **hard-stopped by
  the duplicate check** — the fresh-card law forbids "use the existing member"
  for a payer (§3), so they could never self-serve again. The screen hands off
  to the front desk instead. (The founder's counterpart ruling: abandoned drafts
  surface in a staff-visible "incomplete signups" list in the CRM, so the front
  desk can finish or delete the shell — not a nightly sweep, which would destroy
  a signed waiver.)

`KioskEscapeFoot` (`widgets/kiosk_escape_foot.dart`) is the built instance: a
hairline band pinned to the fold by `KioskStage`'s `footer` slot, so the class
grid scrolls *beneath* it — a way out that a tall grid pushes off-screen is not
a way out.

### Abandon clears the DRAFT, not just the view

Every abandon path is also a **privacy** path, because the next person is
standing right there. `KioskFlowState.home()` is a plain "everything off"
constant and `goHome()` emits it (re-seeded with the gym-wide catalogues only),
so the selected member, the query, the results and every check-in outcome field
are gone. `KioskNameSearch` listens for the query going empty and **clears its
own `TextEditingController`**, so no half-typed name is left visible on screen —
a state reset alone would not do that.

This generalizes to Phase D, and it is the reason the rule is written down: the
member-detail step collects **address, emergency contact and date of birth** —
personal data typed on a shared screen. Everything a signup step holds must die
on abandon and on idle-timeout the same way the search query does, including
those fields.

### Browser autofill is a cross-member leak on a shared iPad

**There are currently NO Flutter `AutofillHints` or `AutofillGroup` anywhere in
`CRM/`** — verify with `grep -rn "AutofillHints\|AutofillGroup" CRM/`, which
returns nothing today. That absence is quietly load-bearing.

The kiosk is a **shared** front-desk device. Browser/OS autofill would happily
offer the **previous member's** address — or their card details — to the next
person standing at it.

> **If autofill hints are ever added to a shared CRM form widget, the kiosk MUST
> explicitly opt out.**

Someone adding `autofillHints` to a shared text field purely for the admin app's
convenience would silently create a cross-member data leak on the kiosk, and
**nothing in the type system would flag it** — the kiosk reuses those widgets by
design (§8.1). Treat it as a review checkpoint on any shared form field, not as
something the kiosk can be trusted to notice later.

---

## 3. The fresh-card law, and no discounts at all

Both rules are about the same thing: a self-serve iPad must not be able to spend
someone else's money or discount its own membership.

### The fresh-card law

**The kiosk may only charge a card entered during the CURRENT kiosk signup, for
a member created in that same signup.** Consequences:

- **No payer picker.** Anywhere.
- **No saved-card list.** Anywhere.
- The payer must be **brand new**; payees (the group / family case, Phase E) may
  be new or existing.
- A duplicate payer at signup is a **front-desk stop**, never "use the existing
  member" — that would attach a kiosk charge to a member the kiosk did not
  create.

For a **recurring** plan the entered card IS kept (a subscription can only bill
the saved default, so `set_default` must be true); for **one_time / trial** it is
attach → pay → detach. The card copy branches on the plan for exactly that
reason — writing "only used for this signup" on a recurring plan would be a lie.

This is a **frontend guard** (accepted, given the supervised iPad + Guided
Access). Which means: it holds only as long as no kiosk screen imports a
payer/card-selection widget. Treat any such import as a defect.

### NO discounts reach the kiosk — enforced structurally

Neither staff-applied discounts nor member-entered promo codes exist on the
kiosk. **This is enforced by the kiosk never IMPORTING a discount-shaped widget,
not by a flag.** A `showDiscounts: false` parameter is one wrong default, one
flipped boolean, or one new call site away from a member discounting their own
membership.

The invariant to preserve when Phase D lands: **`grep -ri discount
CRM/lib/features/kiosk/` returns nothing.** The shared add-member modules the
kiosk will reuse (`features/member_details/presentation/dialogs/add_member/`)
must therefore be extracted with the discount surface as a *separate widget the
kiosk does not import* — not as a parameter the kiosk passes `false` to.

---

## 4. Two rejection shapes — and the kiosk switches on the CODE

A refused check-in arrives in **two structurally different ways**, and conflating
them is a bug:

| shape | transport | carries | means |
| --- | --- | --- | --- |
| **Gate rejection** | HTTP **200** | `skip_reason` (a `CheckInWarning` enum), `log_id: null` | The member was resolved and evaluated; the strict kiosk gate said no. Nothing written. |
| **Resolution error** | a **thrown** 4xx | a stable `code` **sibling** of `detail` | The occurrence / class itself is unusable (paused, deleted, cancelled, not yet open, full, unknown). |

**The gate rejection (200).** `is_member: true` selects the backend's strict
gate (`FastApiBackend/src/checkin/service/checkin_member_gate.py`): a blocking
condition rejects with a single primary `skip_reason` chosen by
`_REASON_PRIORITY` — `over_capacity` → `no_membership` → `unsigned_waiver` →
`out_of_classes` → `ineligible_plan`. Nothing is written, no points awarded.
This is the *kiosk* mode of a staff-only endpoint; `is_member` is a
staff-selected MODE, not a claim about who is calling. (The staff mode,
`is_member: false`, is warn-first instead — see `class-system-guide` §5.)

**The resolution error (thrown).** The body is
`{"detail": "Class is not active", "code": "class_inactive"}` — a plain-string
`detail` plus a **sibling** machine-readable `code` from the backend's
`CheckinErrorCode` (`FastApiBackend/src/checkin/checkin_exceptions.py`). The
status AND the code both come off the exception *type*.

`KioskFlowCubit.selectClass`'s `catch` reads the code off
`ServerException.data['code']` via
`CheckInErrorCode.fromErrorBody` (`features/check_in/data/models/check_in_error_code.dart`
— safe-parsed with an `unknown` fallback per the resilient-enum rule; an absent,
null, or non-String `code` parses to `null`, which is how a fresh failure clears
a stale code rather than inheriting the last member's reason). It rides on
`KioskFlowState.checkInErrorCode`, and
`presentation/kiosk_blocked_copy.dart` is the **single** place that maps either
shape to a member-facing line.

**Matching on the `detail` prose is forbidden.** The backend states plainly that
the message text may be reworded freely while the code is the contract — a
client-side prose match would recreate exactly the fragility the typed backend
errors removed. (It has already bitten once: the router used to pick 404-vs-400
with `if "not found" in str(exc).lower()`.) **Codes are public contract**: adding
one is fine, renaming one is a breaking change.

Every blocked line is **blame-free and stops at the fact** — the screen itself
supplies the front-desk handoff ("Nothing's wrong. The coach at the desk can
sort it…"), so no line carries an error code, jargon, or any hint the member did
something wrong. Anything unrecognised (an `unknown` code, a foreign 400, a 5xx,
a dropped network) lands on the one calm generic line.

---

## 5. Two SEPARATE class lists, and why merging them is two bugs

`KioskFlowCubit` holds two different lists of class occurrences on
`KioskFlowState`. They look interchangeable and are not. Merging them is the
single most likely "simplification" a future contributor will attempt, and it
reintroduces two separate founder-reported bugs at once.

### `state.classes` — the CHECK-IN flow's list

Today only (`GET /api/v1/classes/instances` over `[today, today]`), read fresh
per member in `_loadClasses` when a member is selected, narrowed to what that
member can actually check into **right now**:

```dart
!i.isCancelled &&
occurrenceCheckInOpen(i.occurredAt, now) &&
occurrenceEnd(i.occurredAt, i.resolvedDurationMinutes).isAfter(now)
```

ordered current-then-soonest (ascending start instant, so an in-session class
precedes an upcoming one). This is what the class-pick grid renders.

That filter is a **deliberate safety fix, not tidying.** Before it the kiosk
offered classes that had already ended — and the backend silently accepts a
check-in against a past occurrence — so a member tapping the morning's class at
6pm was recorded into the wrong session. The end-bound is **kiosk-local on
purpose**: the shared `occurrenceCheckInOpen` predicate
(`features/schedule/data/occurrence_windows.dart`, reused by the staff check-in
dialog) has no upper bound and is deliberately looser. **This filter must never
be widened, and the showcase must never drive it.**

### `state.showcaseClasses` — the Get-the-app showcase's list

Marketing data for the "Book classes" slide. Warmed once at kiosk entry
(`_warmShowcaseClasses`, alongside `_warmRewards` / `_warmVideos` /
`_warmRankLadder`) over a **forward** window `[today, today +
kKioskShowcaseClassDays]` (7 days ahead → an eight-day inclusive range), keeping
only occurrences that have **not started yet**, soonest-first, capped at
`kKioskShowcaseClassCount` (2). `goHome` re-seeds it from the entry cache, so
nothing re-fetches per member and the modal fires **no network call at all** —
that is why it opens instantly.

Seven days is chosen so the list **cannot go empty merely because of the time of
day**: every weekday of a weekly schedule falls inside an eight-day window even
after today's own occurrences have finished. "Not yet started" (rather than "not
yet ended") is what keeps each row honest — every row carries an inert Book
pill, and a finished class under a Book pill reads wrong. Because one warm covers
a session up to twelve hours long, `goHome` also **prunes** occurrences that have
since started (`_pruneShowcaseClasses`) — no network; the cache simply drains,
and an empty list omits the slide.

### Why merging them reintroduces BOTH bugs

Drive the showcase off `state.classes` and you get the original report — the
modal showing three slides instead of four — because `classes` is empty until a
member is picked, so the home-panel path has no class data at all. Even after a
member is picked, that list empties every evening once nothing is in the
check-in window, so the slide would vanish at the hour the gym is busiest. Widen
`classes` to the showcase's forward range instead and you re-open the
wrong-class check-in risk the filter exists to close. **No single range is
correct for both jobs.** Two fields, two caches, two calls.

**Supporting invariants.**

- The row's day word is derived per occurrence via `classDayWordLabel`
  (`Today` / `Tomorrow` / `Thu`), never hard-coded. A fixed "Today" was correct
  only while the list was today-only; over a week-wide window it would state
  something untrue about a real class on a member-facing screen.
- `KioskGetAppModal` takes the list as **`showcaseClasses`** (not `classes`)
  precisely so wiring `state.classes` into it is visibly wrong at the call site.

---

## 6. Four gym-wide catalogues, warmed once at entry

The `KioskFlowCubit` constructor fires four independent warms and caches each
for the whole session. They are identical for every member, and the
member-facing screens that render them must open with **no network wait** — the
"Get the app" modal in particular fires nothing of its own.

| warm | read | feeds |
| --- | --- | --- |
| `_warmRewards` | `GET /api/v1/rewards/?gym_id=` (active only, cheapest-first, capped at `kKioskGlanceRewardCount` = 4) | the glance's reward tiles + the "Earn rewards" slide |
| `_warmShowcaseClasses` | `GET /api/v1/classes/instances` over the forward window (§5) | the "Book classes" slide |
| `_warmVideos` | `GET /api/v1/gyms/{id}/videos?limit=2` | the "Watch videos" slide |
| `_warmRankLadder` | `GET /api/v1/ranks/enabled` **first**, then `GET /api/v1/ranks/` | the "Track rank" slide |

Rules that hold across all four:

- **Every failure is non-fatal.** The slide is simply omitted — never an error
  state on a member-facing screen. (The rewards cache is the one that re-attempts:
  a failed fetch stays uncached so a later glance retries, and `_rewardsInFlight`
  dedups the eager warm against a fast first check-in.)
- **`goHome` re-seeds from the caches** (`_freshHome`), so nothing re-fetches per
  member. `KioskFlowState.home()` is a plain "everything off" constant that
  clears them; `_freshHome` is what puts them back.
- **The video read is this gym's own feed**, never `selectedGym.detail` — that
  showcase belongs to a DEFAULT content gym, so rendering it here would put
  another gym's videos on a member-facing screen.
- **The rank ladder checks the enabled flag first.** Rank-enabled is a separate
  gym setting from the ladder rows, so a gym that configured belts and then
  switched ranks off must not see them.

---

## 7. Four clocks, and which one owns which screen

Four independent timers exist. Confusing them is a recurring source of bugs, so
name them precisely:

| clock | length | scope | on expiry |
| --- | --- | --- | --- |
| **Runway** (`KioskSessionCubit`) | 12h absolute, lockout at 11h45 | the whole session | sign out |
| **Flow-idle** (`kKioskIdleTimeout`) | 5 min, then a 30s visible countdown (`kKioskIdleCountdown`) | any *engaged* flow page | `goHome()` — abandons the draft |
| **Glance hold** (`kKioskGlanceHold`) | 10s, started at the LAST reveal beat | the glance only | `goHome()` |
| **App modal** (`kKioskAppModalTimeout`) | 60s | the modal overlay only | `goHome()` |

`_syncIdleTimer()` is the arbiter: the idle guard runs only while `_engaged`
(past home, or typing into home's search) and is **suppressed entirely** on the
glance (`view == checkedIn`) and while the app modal is open. Any pointer-down on
the kiosk surface calls `registerActivity()` ("I'm still here") — except while
the modal is open, where it is a no-op.

**The glance hold starts at the last beat, not on entry.** `kKioskGlanceLastBeat`
(2220ms) must equal `KioskRevealTimings.panels`; a test asserts exactly that.
The hold is time to read something *finished*, so starting it on entry would
spend its opening seconds watching the screen assemble itself. The full countdown
value is emitted on the first frame (the footer never reads a drained "0s"
mid-reveal); only the decrement waits. Total glance life ≈ 12.2s, by design.

**Done and expiry part ways on the modal, deliberately.** The modal is an
*overlay*, so `closeAppModal()` (Done) returns to **whatever was underneath** —
the glance when a glance tap opened it, the home when the adopt strip's *Get it*
did — and returning to the glance **restarts its hold at the full ten seconds**
(the member spent their reading time inside the modal; handing back the two that
were left would eject them mid-sentence). The reveal choreography does **not**
replay, because the glance never unmounted behind the overlay — which is why
`_startGlanceCountdown` is split out of `_startGlanceReturn`. **Expiry still goes
home**: 60 seconds of no interaction means nobody is standing there, and leaving
a member's name and streak up on a shared iPad for the next person is the wrong
default. Either way the modal's timer is cancelled on close, so no late tick can
fire over the next person.

> `closeAppModal` used to call `goHome()` unconditionally, which threw a member
> out of their own check-in result the moment they pressed Done. Keep the two
> paths distinct.

---

## 8. Design and layout laws

The kiosk is a supervised iPad read from ~2 metres and never scrolled by
someone who knows there is more. Every rule below is structural rather than
aesthetic — it holds by construction, not by a tuned pixel value.

### 8.1 The kiosk runs its OWN COMPLETE type ramp, and it moves as a SET

Every text role on the kiosk — not just the loud ones — is a step above the
admin ramp, expressed as named `DesignConstants.kiosk*` tokens. The ladder,
largest first:

```
kioskStreakNum 112 · kioskDisplay 40 · kioskMetric 30 · kioskPanelTitle 25 ·
kioskStatement 22 · kioskFieldText 22 · kioskTitle 21 ·
kioskButtonPrimaryLabel 19 · kioskName 19 · kioskSubtitle 18 ·
kioskButtonOutlineLabel 17 · kioskButtonGhostLabel 17 · kioskBody 17 ·
kioskLabel 16 · kioskSectionText 16 · kioskCaption 15 · kioskMicro 13 ·
kioskMonoValue 13 · kioskEyebrow 12 · kioskTag 11
```

**Never re-scale one kiosk role on its own.** A half-applied ramp is the same bug
as no ramp — scaling only the buttons is what once put the home's "Get it" label
above the copy around it. Every kiosk call site reads one of these tokens; **no
kiosk call site ever restates a size**, and the admin ramp (`h1`/`h2`/`h3`/`p`,
`AppPrimaryButton`, `AppOutlineButton`) is never touched by a kiosk change.
`test/features/kiosk/presentation/kiosk_type_ramp_test.dart` is the structural
guard: it fails if the ladder stops descending, if a button label out-sizes a
heading, or if the admin sizes drift.

A shared widget the kiosk reuses gets an **opt-in, not a fork** — `ClassCard`
takes a `kiosk` flag, `ClassMetaChip` a `textStyle`, `AppSearchBox` a
`textStyle` + `hintColor` — so admin defaults stay exactly as they were.

Every kiosk button goes through `KioskPrimaryButton` / `KioskOutlineButton` /
`KioskGhostButton` (`widgets/kiosk_buttons.dart`), the only place the three
button tokens and their paddings are applied. The ladder is loudest-first:
primary (gradient) > outline (2px ink) > **ghost** — the *escape* tier, the only
one used for LEAVING a flow, demoted by WEIGHT rather than size (it keeps 17px
because a member still has to find it from 2m). `KioskPrimaryButton` also takes
`compact: true`, which keeps the gradient (still the primary tier) but borrows
the outline button's label + padding tokens rather than declaring a third size —
for a filled button that must sit beside a secondary one without out-shouting it
(the home adopt strip's *Get it* is its one user).

The one deliberate exception is a dialog built on the shared `AppDialog` (the
Phase D signup stub): the whole shell stays on the dialog's own
internally-proportional scale rather than putting *only* its body on the kiosk
ramp. A kiosk-scale dialog shell would mean a `kiosk` opt-in through `AppDialog`
/ `AppDialogTitle` / `AppDialogActions` — a separate call, not something to
half-do.

### 8.2 Kiosk text meets the AA contrast floor

Muted words on a kiosk surface are **`text2nd`, never `text3rd`**. `text3rd`
(`#878D99`) measures 3.05:1 on the ground — under the 4.5:1 WCAG AA floor
`CRM/PRODUCT.md` holds as a hard requirement, and unreadable at 2m anyway. The
kiosk deliberately lifts every muted role that carries **words** (timer label,
section sub-text, eyebrows, the search hint and empty-result line, the "or" seam,
the header kicker, belt names, view counts, the rotate caption). `text3rd`
survives on kiosk surfaces only for NON-text: hairlines, the return timer's
drain bar, placeholder glyphs. This is scoped to the kiosk; the admin app's own
`text3rd` usage is untouched.

### 8.3 A QR's colours are functional, not themable

Both kiosk QR tiles render through the one `KioskQrFrame`
(`widgets/kiosk_qr_frame.dart`) and pin to `DesignConstants.kioskQrModule` /
`kioskQrQuietZone` — **fixed dark-on-white in EVERY theme**. Resolving them
through `text` / `surface` inverts the code under the dark theme, which many
scanners fail on. **Never "fix" them back onto the theme tokens.** The download
QR's centre badge occludes ~4% of the symbol — comfortably inside level-M's 15%
recovery budget and clear of the finder/timing patterns — so it still scans.

### 8.4 The home is laid out as BANDS, not as two columns

`widgets/kiosk_home_columns.dart` composes the home's two halves
(`KioskHomeHalf` = head / body / optional foot) as shared **horizontal bands** —
heads, bodies, optional feet — inside an `IntrinsicHeight`, with the vertical
"or" seam drawn ONCE across all three as an `IgnorePointer` overlay and each
band reserving the seam's exact width in its gutter.

The point: the QR tile and the search field float in the *same* flexible middle
band, so they land on **one optical centre** while both headings stay
top-aligned. Nothing is pixel-pinned; the guarantee comes from the structure.

Two consequences that are easy to undo by accident:

- **The feet band is OMITTED, not emptied, when neither half fills it.** A
  zero-height band still costs the column's spacing above it, reserving a gap
  under the bodies and stealing that height from the flexible middle they are
  centred in. `test/features/kiosk/presentation/kiosk_home_columns_test.dart`
  guards both directions (band absent when unused; band + its spacing back when
  a half fills it).
- **`KioskSearchResults` is a true zero-height box at rest** and each populated
  state carries its OWN top gap, so an empty result list cannot nudge the field
  off that shared centre. Never re-introduce that gap as a parent `Column`
  spacing.

**The search field is capped at `DesignConstants.kioskHomeMeasure` and centred
in its half**, not stretched across it — a control spanning half an iPad reads
as running off the edge of the screen. The cap is `MeasuredMaxWidth`, not a
plain `ConstrainedBox`: the bands resolve through `IntrinsicHeight`, which would
otherwise measure a wrapping result row at the FULL column width and
under-reserve its height.

**The adoption strip spans BOTH columns and is the LAST band on the home**
(`widgets/kiosk_adopt_strip.dart`): a hairline running the full stage, then the
white-labelled adoption line and the compact *Get it* button on ONE row beneath
it, centred as a group. Getting the app is a property of the WHOLE screen — the
member who scans and the member who types both end up wanting it — so it never
belonged inside one half; while it lived in the QR half's foot only one column
had a foot at all, which left that half structurally heavier however small the
strip got. Spanning it empties both feet, so the columns balance **by
construction rather than by tuning one side down**.

- **The rule spans; the pair does not.** The hairline runs full width because
  its job is to close everything above it (the "or" seam terminates onto it),
  while the line + button are group-centred inside
  `DesignConstants.kioskAdoptMeasure`; nothing in the row pushes them apart (no
  `Expanded`, no `Spacer`), so a band twice as wide as the old column can
  neither maroon them at opposite edges nor run the sentence past a readable
  measure.
- **One row, not a stack.** The line is the row's only `Flexible` child, so a
  long gym name narrows and wraps the SENTENCE (ellipsizing at `maxLines: 2` —
  the one reason `KioskAppLine` takes a cap) while the button holds its width
  and its place beside it. The button's label is deliberately short: the line
  already says what and where, so the button carries only the verb.
- **Order: "New here? Sign up" sits ABOVE the strip.** Both are footer-weight
  bands and only one can own the terminal slot, so the strip's hairline is the
  home's single categorical boundary: above it, every way to get in RIGHT NOW
  (scan / search / sign up); below it, the one thing that is about later. A
  newcomer with no account is *blocked* at the kiosk and outranks a nudge nobody
  is waiting on. Never add a second rule to give the strip its own band — that
  turns one boundary into two footers competing for the same role.

### 8.5 The glance's choreography — two beats, and the layout never moves

`presentation/kiosk_reveal_timings.dart` is the beat sheet; every offset lives
there and **no call site invents one**.

| at | what |
| --- | --- |
| 0ms | the confirmation fades in (`confirmationFade` 560ms), CENTRED and alone |
| 1500ms | `centredHold` ends; it LIFTS (`lift` 720ms, `Curves.easeOutQuart`) |
| 2220ms | `panels` — BOTH cards land together; the ten-second hold starts here |

The confirmation is one `kioskDisplay` line, "Checked into {class name}", with
the green check disc beside it. There is deliberately **no** "Nice one, {name}"
above or below: a congratulatory line adds no information and delays the answer,
and the celebration is the streak + rewards underneath.

`widgets/kiosk_glance_lift.dart` makes the travel exact with nothing measured:
the settled column sizes a `Stack`, and the confirmation rides a
`Positioned.fill` `Align` lerping `center` → `topCenter`, so both ends of the
move are exact. The cost is that the confirmation is **built twice** while it
travels — a zero-opacity copy in the column holding its slot (dropped from
semantics by that zero opacity, so a screen reader hears it once) and the
`kKioskGlanceTravellingConfirmation`-keyed copy in flight (`IgnorePointer`, so
Done and the tap-to-open-the-app gesture keep working throughout). The flying
copy is removed the instant it lands.

**The layout NEVER moves.** The cards and the footer are laid out in full from
the first frame — invisible, but holding every pixel — so no beat can reflow the
screen and Done never shifts under a finger.

**"Together" is structural**, not two offsets that happen to agree: ONE
`KioskReveal` wraps the whole row. Inside it the streak's numeral rolls up on
the member app's own odometer (`shared/widgets/animation/count_up_text.dart`, at
`CelebrationTimings.countUpDuration`) while the reward tiles cascade one by one.
**A reward tile's delay carries the `panels` beat, not just its stagger slot** —
a `KioskReveal` delay runs from MOUNT and the grid mounts when the catalog
lands, so a bare `tileStagger * index` would cascade invisibly behind a card
still at zero opacity.

**Reduced motion gets the whole glance at once, already landed**, with the
streak's final number: every wrapper is `KioskReveal`, which returns its child
bare under `MediaQuery.disableAnimationsOf`, and `KioskGlanceLift` returns the
settled column directly (no centred hold, no lift, no stagger, no roll). The
hold still applies, so there is time to read. `KioskAppShowcase` set the same
precedent for its auto-rotation.

The view swap itself is cross-faded (`_ViewSwitcher`'s `AnimatedSwitcher`,
layout-transparent via `StackFit.passthrough` + top-left alignment), so
"Checking you in…" RESOLVES into the glance instead of hard-cutting to it.

Reward tiles show a filled ready disc when affordable (`balance >= cost`) and a
progress ring otherwise; a null balance degrades them to cost-only. Both the
balance fetch and the catalog degrade independently — a failed catalog leaves a
points-only panel, never an error.

The week strip is fed by **`current_week_days`** — a length-7 **Monday-first**
list of the gym-local weekdays the member attended this week, carried on the
check-in response (and on `GET /api/v1/streak`) alongside `class_streak_weeks`,
so the glance needs no second call for either. `class_streak_weeks` and the
strip are both zeroed when the check-in was not recorded. The member's points
BALANCE is the one per-member fetch the glance makes
(`GET /api/v1/members/{id}/billing` → `retention.pointsBalance`), and it is the
balance AFTER the just-awarded points — distinct from the response's own
per-check-in `points_awarded` delta (which an idempotent repeat merely *echoes*
without re-awarding; `already_checked_in` is what tells them apart).

### 8.6 The "Get the app" modal is ONE popup, and it must not scroll

`widgets/kiosk_get_app_modal.dart` supplies a single lifted surface
(`kKioskGetAppPopup` — the same `popup` fill / `radiusCard` / hairline /
`cardShadow` chrome the idle warning wears) carrying **two nested cards** — the
accent-soft app card (`get_app/kiosk_app_card.dart`: title, the book/earn/watch
checks, the real download QR, the two sign-in steps) beside the auto-advancing
"In the app" showcase (`kiosk_app_showcase.dart`: a 5s rotation over one fixed
slide box, clickable dots, honoring reduced motion) — **with the countdown +
Done foot INSIDE the surface**. Before this the panels floated straight on the
veil with the foot dangling below, which read as three loose objects rather than
one thing that had opened.

There is deliberately **no spanning "Welcome to {gym}" header**: the gym is
already named on the persistent kiosk header and on the app card's own title, so
a third naming only costs height on a screen that must not scroll.

**And it must not scroll — that is structural, not a size that happens to fit.**
A member standing at a kiosk never discovers content below a fold, so
`get_app/kiosk_get_app_body.dart` lays the foot out FIRST and gives the two
cards an `Expanded` share of what is left (bounding their height); inside each
card a `ShrinkToFit` (`shared/widgets/shrink_to_fit.dart` — lay out at full
width, then scale the whole card down uniformly if it is taller than the box)
turns a short fold into ONE proportional scale-down rather than an overflow.
With no slides at all the app card is centred alone, capped at
`dialogMaxWidth`. **Never add a `SingleChildScrollView` here** — a scrollbar on
a kiosk is content nobody will ever see.
`test/features/kiosk/presentation/kiosk_get_app_modal_test.dart` guards it at
1180×820 and 1024×700: no overflow, and nothing *vertically* scrollable (the
belt ladder's sideways strip is fine).

---

## 9. Real data vs the one illustrative slide

**The kiosk never renders fabricated member data on a member-facing screen.**
A gym's members read anything on this screen as their gym's own schedule,
catalogue, feed or belts.

- **Every showcase slide is conditional on real data.** `kioskShowcaseSlides`
  adds a slide only when its list is non-empty — no placeholder, no stand-in, no
  demo content. The rotating title, the dots, and the auto-rotate caption all
  derive from the same list, so none of them can advertise a missing slide; with
  no slides at all the showcase panel is dropped and the app card carries the
  modal alone.
- **"Book classes" / "Earn rewards" / "Watch videos" are strictly real** — the
  gym's own upcoming occurrences, its own cached catalogue, its own curated feed.
- **"Track rank" is the ONE deliberate exception.** `slides/kiosk_rank_slide.dart`
  + `kiosk_rank_progress.dart` draw the gym's REAL ladder (belt names, belt art,
  and the featured rung's real `classes_to_next_major` as the bar's denominator)
  but always feature a MIDDLE rung — `kioskFeaturedRungIndex`, the lower middle,
  so a rung above it always exists to name — over a bar filled to a fixed
  fraction.

  **Do not wire it back to the member.** An earlier pass used the checked-in
  member's real rank and real attendance progress; it was removed on purpose.
  Kiosk users skew new, so real data pinned the highlight to the FIRST rung with
  an empty bar — the least compelling thing the feature can look like. This panel
  is a **pitch for the app, not a status readout**, so it needs no member data at
  all and renders identically from the glance and from the idle home. That is why
  there is no `currentRankId` on `KioskFlowState` and nothing rank-shaped is read
  off the glance's member fetch.

  The one hard guard that survives: **no copy on that slide may claim the
  featured rung or the progress belongs to the person standing there** (a white
  belt told "you're purple" distrusts the number instead of wanting it) — hence
  no "You're here" tag and a feature-describing caption. Emphasis is size +
  opacity + ink only. `test/features/kiosk/presentation/kiosk_rank_slide_test.dart`
  pins all of it.

Two smaller members of the same family:

- The modal's step-2 email chip renders only for a **really-known** member
  (`AllViewRow.email`, the view the kiosk name search uses); any other row shape
  means we don't know it.
- The glance's class name is carried from the picked occurrence
  (`KioskFlowState.selectedClassName`) because the check-in response has only a
  `class_id`. An unknown name degrades to a bare "Checked in" — never a guess.

### Copy: the member app is WHITE-LABELLED

Every kiosk line that names the app says the **GYM's** name. A member downloads
*their gym's* app; "CombatDen" is the platform's name and means nothing to the
person at the iPad. `presentation/kiosk_app_copy.dart` is the ONE place those
strings live (the app card title, the home's spanning adoption line, the glance
rewards panel's redeem / book nudges), and each builder degrades to naming the
app generically ("Get the App") when `selectedGym.gymName` is null or blank —
never to an empty word, a doubled space, or a stand-in gym name. **A wrong gym
name on a member-facing screen is worse than none.** No kiosk call site
assembles one of these sentences itself.

Name display splits by purpose: search results render the member's **full name**
(two members sharing a first name and last initial must stay distinguishable at
the moment they tap to check in), while greetings use `kioskFirstName`
(`presentation/kiosk_name_format.dart`) for direct address.

---

## 10. Phase status — what is built, what is not

**Built (PR #59, worktree `worktree-kiosk-mode`):**

- **Phase B — the security shell.** `KioskSessionCubit` + `KioskSessionStore` +
  `KioskServerClock`, the auth-gate intercept, the `restoring` boot seam, the
  runway, `KioskLockedScreen`.
- **Phase C1 — the check-in lane.** `KioskFlowCubit` drives home → name search →
  class pick → `is_member: true` check-in → glance / blocked / closing, plus the
  5-minute flow-idle guard and the escape foot.
- **Phase C2 — the retention glance.** Two-beat reveal, streak + current-week
  strip, points balance, reward tiles, the 10-second hold.
- **UX-5 — the "Get the app" modal.** One solid popup carrying the app card
  (with a real `qr_flutter` download QR encoding the per-gym download page) beside
  the auto-advancing showcase, over a countdown + Done foot. It must not scroll —
  the body lays the foot out first, gives the two cards an `Expanded` share of
  what's left, and each card's `ShrinkToFit` turns a short fold into one
  proportional scale-down. **Never add a `SingleChildScrollView` here**: a
  scrollbar on a kiosk is content nobody will ever see.

**Not built:**

- **Phase D (solo signup) + Phase E (group / family add).** The kiosk's "New
  here? Sign up" button currently opens `showKioskSignupStub` — a calm
  front-desk handoff dialog, explicitly a placeholder. The approved design spec
  is **`KIOSK_SIGNUP_MOCKUPS.html` at the repo root** (12 screens: details →
  extra details → duplicate stop → plan → waiver → card → review → paying →
  declined, plus the group add / existing-match / payer-waiver / group-review
  set, plus the idle-warning, abandon-confirm and welcome states). Its HTML
  comments carry the backend contract per screen and are the build spec. The
  post-signup **welcome screen** is D's tail. D is the kiosk's first
  money-moving surface — the repo's billing rule (small, individually approved
  pieces) applies.
- **Phase G — the rotating check-in QR.** The kiosk home's QR is a static,
  deliberately inert glyph (`widgets/kiosk_qr_panel.dart`, `_QrPlaceholder`),
  already sitting in `KioskQrFrame` so the live code drops into a tile with the
  right fixed contrast. The full design — hourly server-minted per-gym tokens in
  a `gym_kiosk_tokens` table, a previous-OR-current-hour validity window, the
  URL/universal-link payload, the new `src/kiosk/` backend domain, and the
  member-portal scan-checkin route — lives in **`PHASE_G_QR_PLAN.md` at the repo
  root** (DESIGN ONLY; its §10 open questions are unanswered). Note the two QRs
  are **different codes with different jobs**: the rotating CHECK-IN QR (kiosk
  home) and the static APP-DOWNLOAD QR (the modal). Only the check-in QR is
  Phase G.
- **The per-gym app-download page** the download QR points at — deferred to a
  follow-up PR; mockup at `APP_DOWNLOAD_PAGE_MOCKUP.html`. The URL the QR
  already encodes is composed by `kioskAppDownloadUrl(gymId)`
  (`kKioskAppDownloadBaseUrl` + the gym id, in
  `widgets/kiosk_get_app_modal.dart`) — never a raw store link, so Android
  members and white-label gyms both route correctly once the page exists. The
  backend half **has shipped**: nullable `gyms.app_store_url` /
  `gyms.play_store_url` plus the public, unauthenticated
  `GET /api/v1/gyms/{gym_id}/app-links`, which resolves the gym's override else
  the CombatDen default from `Settings` (a placeholder until the app publishes).

---

## Key files

**CRM — the kiosk feature** (`CRM/lib/features/kiosk/`):

- `bloc/kiosk_session_cubit.dart` + `kiosk_session_state.dart` — the security
  runway (§1), `beginFlow`/`endFlow` (§2).
- `bloc/kiosk_flow_cubit.dart` + `kiosk_flow_state.dart` — the check-in lane,
  the two class lists (§5), the four catalogues (§6), the timers (§7). All the
  tunable constants live at the top of the cubit file.
- `data/kiosk_session_store.dart` (fate-shared persistence),
  `data/kiosk_server_clock.dart` (the HTTP `Date` read).
- `presentation/kiosk_screen.dart` — the mounted surface: header, the cross-faded
  `_ViewSwitcher`, the idle overlay, the app-modal overlay.
- `presentation/screens/` — `kiosk_home_screen.dart`,
  `kiosk_class_pick_screen.dart`, `kiosk_glance_screen.dart`,
  `kiosk_blocked_screen.dart`, `kiosk_closing_screen.dart`.
- `presentation/kiosk_blocked_copy.dart` — the ONE map from either rejection
  shape to member copy (§4). `presentation/kiosk_app_copy.dart` — the ONE home
  for white-labelled app naming (§9). `presentation/kiosk_reveal_timings.dart` —
  the glance beat sheet.
- `presentation/widgets/get_app/` — the modal's card + showcase;
  `slides/kiosk_rank_slide.dart` is the illustrative one (§9).
- `presentation/kiosk_locked_screen.dart` — the fail-closed terminal screen
  (mounted by the gate, not by `KioskScreen`).

**CRM — outside the feature:**

- `lib/features/login/presentation/screens/auth_gate.dart` — the mount intercept.
- `lib/main.dart` (`_AuthGateHost`) — the non-lazy app-root provider + the
  sign-out fate-share listener.
- `lib/shared/widgets/navigation/nav_actions.dart` / `nav_sections.dart` — the
  confirm-then-enter path, gated on `RolePolicy.canOperateKiosk`.
- `lib/core/constants/design_constants.dart` — the `kiosk*` type ramp, the QR
  colour pins, `kioskProgressBarThickness`.
- `lib/features/check_in/data/models/check_in_error_code.dart` /
  `check_in_warning.dart` — the two rejection enums.
- `lib/features/schedule/data/occurrence_windows.dart` — the shared window
  predicates the check-in list narrows further.

**Backend:**

- `FastApiBackend/src/checkin/service/checkin_member_gate.py` — the `is_member`
  split; `schema/checkin_schema.py` — `CheckinWarning`, `CheckinRequest`,
  `CheckinResponse` (incl. `class_streak_weeks` + `current_week_days`).
- `FastApiBackend/src/checkin/checkin_exceptions.py` — `CheckinErrorCode`, the
  public code contract.

**Specs for unbuilt phases (repo root):** `KIOSK_SIGNUP_MOCKUPS.html` (D+E),
`PHASE_G_QR_PLAN.md` (G), `APP_DOWNLOAD_PAGE_MOCKUP.html`.

**Tests:** `CRM/test/features/kiosk/` — `bloc/kiosk_session_cubit_test.dart`
(the runway + the SEC-1/2/3 seams), `bloc/kiosk_flow_cubit_test.dart`, and the
presentation guards `kiosk_type_ramp_test.dart`, `kiosk_get_app_modal_test.dart`
(no overflow / no vertical scroll at 1180×820 and 1024×700),
`kiosk_rank_slide_test.dart`, `kiosk_home_columns_test.dart`,
`kiosk_glance_screen_test.dart`.

**Sibling skills:** `class-system-guide` (the occurrence model + the warn-first
staff gate this kiosk gate is the strict twin of), `rewards-guide` (the reward
catalogue the glance renders), `ranks-guide` (the ladder the rank slide draws),
`employees-guide` (the role model behind `canOperateKiosk`), `qa-crm` (driving
the live app).

---

## Living document

This skill tracks Kiosk Mode **as it currently is** — not a changelog. When a
kiosk rule, screen, timer, contract, or phase status changes, update this skill
in the **same** change so it never drifts. In particular: when Phase D/E lands,
the fresh-card law and the no-discount-imports rule move from "specified" to
"enforced in code" and this skill must say where; when Phase G lands, the QR
contract (URL shape, bucket/window rule, endpoint pair, rejection mapping)
becomes a section here and `PHASE_G_QR_PLAN.md` stops being the record. If you
touch anything kiosk-shaped and find a statement here that no longer matches the
code, fix the skill (or the code) so they agree before you finish.
