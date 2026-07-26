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
  balance contract, the escape / cancel contract (ghost tier in the left gutter,
  wording that answers the screen, the single `goHome()` abandon path, and the
  screens that get a handoff INSTEAD because an escape there would orphan
  committed state), the draft-clearing privacy rule and the shared-iPad autofill
  hazard, the fresh-card law (the entered card is ALWAYS saved as the payer's
  default and replaces theirs, which is what makes the lane self-serve for
  existing members too), the TWO client-side PLAN-BLOCK rules derived from the
  member's own history — the kiosk-only one-trial rule (per member) and the
  already-held recurring membership (per plan, mirroring the backend's conflict
  guard, which takes THREE client statuses for its two SQL strings because
  `overdue` is a display status masking a raw `active`; the CRM's own rule is now
  aligned to the same guard) — the structural
  no-discounts rule, the never-ask-about-the-app-invite rule (`send_invite: true`
  hardcoded at both create sites, and why a prompt there would be wrong), the TWO
  rejection shapes (a 200 with `skip_reason` vs a thrown error carrying a stable
  `code`), the TWO separate class lists (check-in window vs the forward-looking
  showcase), the four gym-wide catalogues warmed once at entry, the seven
  independent timers (every blocking surface carries a visible 60s return
  countdown), the kiosk type ramp / AA contrast / fixed QR polarity
  design laws, the PINNED per-step identity band, the real-vs-illustrative
  data rule, and the built SOLO + GROUP self-serve **signup** lane (its own
  cubit, the new-here/already-a-member front door and the identify search, the
  double-charge defences, the three entry points into a seated payer, the
  group-only "Skip" control on the plan step, the fail-CLOSED waiver skip that
  never re-asks for a signature already at the re-sign floor, the
  THREE-way start-response
  split into the per-person RESULTS receipt (all-created and PARTIAL) vs the
  all-failed decline popup, the
  uncapped, no-wait decline model with same-card + new-card
  retry, and the CRM's
  Incomplete tab as the staff-side resolution for an abandoned draft). Load
  this
  whenever you touch anything kiosk-shaped: `CRM/lib/features/kiosk/`,
  `auth_gate.dart`'s kiosk branch, the `is_member: true` check-in call, the
  "Get the app" modal, the kiosk QR, the signup lane, or the unbuilt Phase G
  rotating check-in QR. Trigger on "kiosk", "front-desk iPad", "self
  check-in", "the glance", "get the app modal", "fresh-card law", "12-hour
  runway", "beginFlow / endFlow", "kiosk escape / start over / cancel",
  "autofill on the kiosk", "skip_reason", "kiosk type ramp", "rotating QR",
  "kiosk signup", "duplicate payer", "already had a trial", "one trial per
  member", "already on that membership", "plan block", "kiosk results screen",
  "partial signup", "skip this person", "find my name", "someone else is
  paying", "decline retry", "retry same card", "already signed that waiver",
  "meets_floor", "re-sign floor", "send_invite", "app invite", or "Incomplete tab".
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
table, and no way back except signing out. An existing member walks up, finds
their name (or, in Phase G, scans a QR), picks their class, gets checked in,
and sees a retention **glance** — their streak, their points, this gym's
reward tiles — before the screen resets for the next person. A brand-new
member instead taps *"Start Trial / Membership"* and walks a self-serve **signup**
spine — details, plan, waiver, card, review, pay, the per-person results receipt,
welcome (§10, §11), solo or
as a group/family — before landing on the same app-adoption push.

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

## 2. Leaving a flow — the balance contract, the escape, and the draft

Three rules that all hang off the same moment (a member walking away from a
half-finished flow): the session bookkeeping that must balance, the affordance
that lets them leave on purpose, and what has to be wiped when they do.

### `beginFlow` / `endFlow` — the balance contract

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

**`KioskSignupCubit` brackets the SIGNUP lane the same way, with its own
latch.** `beginFlow()` fires exactly once, in its constructor (reaching that
constructor *is* the flow starting — `KioskFlowCubit.startSignup()` has already
checked `canStartFlow`, and it deliberately does **not** call `beginFlow`
itself, which would double-count). `_endFlowIfStarted()` fires on entering
`welcome`, `stop` or an ALL-CREATED `results`, on `abandon()`, and in `close()`;
`declined` does **not** release (the member is still there and can retry), a
PARTIAL `results` does not either (Retry is live on it), and `paying` **never**
does. The latch makes the pair exactly-once however many of those run — see
§11.3 for the full table.

The signup cubit cannot navigate — `goHome()` is `KioskFlowCubit`'s — so every
signup exit raises `KioskSignupState.abandoned` and `KioskSignupScreen`'s
`BlocListener` routes it to `goHome()`. That indirection is what keeps the ONE
abandon path one.

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
`Sign Membership · $149.00` button, "Cancel" reads as *cancel the payment*.
Every new escape gets its wording from the sentence it is answering.

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
- **Terminal front-desk stops** (the ineligible-duplicate stop, the
  no-Stripe-account stop) — they ARE the handoff; an escape beside one just
  offers a way to skip the resolution.
- **The Declined screen**, most sharply. By that point a member row, a Stripe
  customer and a signed waiver are all committed and nothing rolls back. A
  "Start over" there would silently orphan all three: the member walks off
  believing they joined, and their own second attempt starts the whole flow
  again from a name they have already used. The screen keeps them where their
  work is instead — retrying the CHARGE and nothing else. (The founder's
  counterpart ruling: abandoned drafts surface in a staff-visible "incomplete
  signups" list in the CRM, so the front desk can finish or delete the shell —
  not a nightly sweep, which would destroy a signed waiver.)
- **The results receipt**, on both branches. Money has moved by then, so there is
  nothing to start over; it uses `KioskResultsFoot` rather than `KioskFlowFoot`
  for exactly that reason (§11.6).

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

## 3. The fresh-card law, the one-trial rule, no discounts at all, and the unasked invite

Three rules, all about the same thing: a self-serve iPad must not be able to
spend someone else's money, hand itself a second free trial, or discount its own
membership.

### The fresh-card law

**The kiosk never charges a PRE-EXISTING card.** Every card it charges is one
entered during the current signup, and that card **always** becomes the payer's
Stripe default — replacing whatever was on their profile. That is the whole
invariant.

**It is about the CARD, never about who the payer is.** Because the kiosk reads
no stored card and offers no saved-card surface, there is nothing for it to
reach for: an existing member with a card on file is a perfectly good kiosk
payer, and typing a fresh card is the price of paying here. The lane is
**near-fully self-serve** for exactly that reason — an existing member starts
and pays for a membership at the iPad rather than being sent to the desk.

**The card step says the consequence out loud**, because a member has to
register it: *"This card is saved to {Name}'s profile and used for future
payments. It replaces any card already on file."* (§ "The card surface" below.)

**What that costs, and why it is accepted.** Person A can seat person B as payer
and type A's card, so B's profile ends up defaulting to A's card and the next
front-desk "charge the card on file" bills A. The kiosk names the payer in a
pinned strip on the card step and states the replacement in as many words, so
the screen cannot do it silently; beyond that it is the same trust model as a
member handing their card to the desk (founder ruling).

#### The three entry points, and the one seat path

**A — the ordinary create.** A brand-new member types their details and
`POST /members/` makes them. Nothing special.

**B — "Is this you?"**, reached two ways and ending in one screen
(`KioskSignupStep.payerMatch` over `KioskPayerMatchStep` + the shipped
`KioskMatchCard` — full name + the masked email `kiosk_name_format.dart`'s
`kioskMaskedEmail` renders for a payee):

- the **identify** search (`KioskSignupStep.identify`), where the member says
  up front that they already train here and taps their own name;
- a **duplicate 409** on their own create, where the gym's records say so.

A confirm is warranted on BOTH routes: two members can share a name, and a
mis-tap on a shared iPad would seat a stranger's account behind the card about
to be typed. "Yes, that's me" adopts the id and writes nothing. **"No, that's
not me" goes where the match came from** — back to the identify search with the
query intact (nothing committed, they simply mis-tapped), or to the terminal
duplicate stop on the 409 route (the create was already refused). A 409 that
names NOBODY is terminal on the spot. A LIST of matches is never rendered, and
never a phone, photo or membership status.

**C — the payer picker (`KioskSignupStep.payerPick`).** One screen serves two
situations. **Changing** who pays while a payer exists — a secondary-tier
affordance under the roster ("Change who is paying"), a change-of-ROLE action
whose label says so ("someone else is paying" announced a fact about a third
party, which is not what the button does). And **choosing** the first payer
after the previous one was DELETED — reached straight from the trash, and
re-openable from the People step's "Choose who's paying" affordance in the
no-payer state (below).

The picker's ONE inline answer is `KioskSignupState.payerAlreadyInSignup`: a CRM
search hit who is already on this roster. It is a **redirect**, not a rejection
— they are listed above and pickable there — and it exists because the CRM path
must refuse to INSERT a second entry for one member, which would be two cart
items (and two charges) for one person.

### Two plan-block reasons, ONE popup and ONE blocked visual

A plan card on the grid can be closed to the person picking for exactly **two**
reasons, and they are different rules with different scopes:

| reason (`KioskPlanBlockReason`) | scope | tag on the card | names a plan? |
| --- | --- | --- | --- |
| `trialUsed` | per MEMBER — any prior trial closes EVERY trial plan | `Already used` | **no** |
| `alreadyOnPlan` | per PLAN — this exact recurring plan is already held | `You have this` | **yes** |

**One popup serves both** (`widgets/signup/kiosk_plan_block.dart`,
`KioskPlanBlock`) and **one blocked visual serves both** (`KioskPlanCard`'s
`blocked` state: `Opacity(0.45)`, the tag pinned top-LEFT over the hero because
the top-right belongs to the select mark, the select mark dropped entirely, and
the card still **tappable** so the tap opens the answer instead of a silent
no-op). The only thing that varies by reason is the words:
`presentation/kiosk_plan_block_copy.dart` maps a reason to its title, body, disc
glyph and card tag, and **its switches are exhaustive on purpose** — a new reason
cannot ship without words, exactly as `kiosk_signup_stop_copy.dart` works. A
second modal or a second blocked treatment would fork the kiosk's one modal
vocabulary for a consequence that is identical.

**The inversion over whether the plan is NAMED is the rule, not a style drift.**
The trial popup never names a plan because its rule is per member — naming one
would describe a narrower rule than the grid is enforcing. The already-on-plan
popup does name it, because its rule genuinely is per plan. The copy file carries
a comment saying so; do not "fix" one of the two to match the other.

Both reasons behave identically otherwise: the card can never become the
selection (`selectPlan` turns the tap into `_openPlanBlock(reason)` instead of
setting `selectedPlanId`), a late eligibility answer CLEARS a pick it
invalidates, the popup's primary (`dismissPlanBlock`) returns to the live grid,
and its outline hands off to the desk (`planBlockHelp` → the reason's own
`KioskSignupStopReason`: `trialAlreadyUsed` or `alreadyOnPlan`).

### The one-trial rule — a KIOSK rule, enforced client-side

**A member gets one trial at the kiosk, ever, and any prior trial closes EVERY
trial plan for them** — not just the one they took.

**Staff can still grant a repeat trial from the CRM, and that asymmetry is
deliberate** (founder ruling). There is no backend rule, no new endpoint and no
new column: this is a self-serve product rule, so it lives entirely in
`KioskSignupCubit`. Do not "fix" it by pushing it into the backend.

- **The signal is derived from the member's own history.** At the plans step
  `_loadPlanEligibility` reads `MemberRepository.getMemberDetail` and asks
  `memberships.any((m) => m.planType == 'trial')` (`MembershipInfo.planType` is
  a plain `String?` there, not the `PlanType` enum). The backend applies **no
  lifecycle filter** to that list, so a trial cancelled or finished a year ago
  still counts — which is the question being asked. Never use a
  currently-active-trial flag instead.
- **It reads TWO facts and drops the rest.** The billing detail is a heavy staff
  payload (rank, charges, redemptions, streak, an address) and a lobby iPad
  prints none of it. Nothing renders, logs or persists any part of that response
  beyond the trial boolean and the held-recurring plan ids below; never reuse it
  to prefill a form.
- **Only for a person the kiosk did not create.** `wasExisting` + a known
  `memberId`; somebody registered during this signup has no history by
  construction, so no call is made at all. Answers are cached per member id for
  the flow (`_planChecked`), and a FAILED read counts as asked.
- **It FAILS OPEN** — the exact opposite of the money-path reads, and on
  purpose. A throw leaves `KioskSignupPerson.hadTrial` false and the trial stays
  on offer: a second trial slipping through costs one free week the desk can
  undo, while turning a legitimate first-timer away sends a paying customer out
  of the door.
  **The waiver-status read in §11.4a is the deliberate INVERSE** — it fails
  CLOSED, because a needless signature costs twenty seconds while a missing one
  voids the gym's legal protection.
- **A blocked trial can never be SELECTED, and always EXPLAINS** — see "Two
  plan-block reasons" above for the shared mechanics. Both halves matter: an
  unselectable card keeps a blocked plan off the review (where it would fail at
  pay), and the popup keeps it from being a greyed-out dead end with no answer.

### The already-on-plan rule — the backend's own conflict, enforced at PICK

**A member may not start a RECURRING plan they already hold, and the kiosk closes
that card on the grid rather than letting them find out at the review.**

**Why it is a hard block, not an annotation.** The charge preview runs the SAME
`MemberMembershipsStartValidation.validate` as the real start
(`memberships_start_preview.py` and `memberships_start.py` both call it), which
includes the per-plan duplicate-recurring check, and that raises a plain 400. The
kiosk therefore hits it in `_loadPreview`, whose catch is
`_stop(previewFailed)` — a **retryable** stop. So an unblocked card leads
straight to "We couldn't work out your total just now" with a *Try again* that
returns to a preview which can never succeed. In a **group** it is worse: the
check runs per member inside one `validate()`, so **one child's already-held plan
kills the entire family's signup** with that same generic message.

**The rule mirrors the backend's conflict GUARD, which is not the same as
matching its two literal strings.**
`FastApiBackend/src/memberships/sql/member_memberships_check_existing.sql`
conflicts on `plan_id = ANY(:plan_ids)` with `status IN ('active','frozen')` AND
`mp.plan_type = 'recurring'`, reading the `member_memberships_status` view. So:

- **per PLAN, not per member** — a member on "Unlimited Monthly" may freely buy a
  DIFFERENT recurring plan, and the kiosk must offer it;
- **recurring only** — one-time and trial packs are allowed to STACK, so a held
  pack blocks nothing;
- **`{active, frozen, overdue}` client-side, for those two SQL strings** — and
  that is the mirror, not a widening. `overdue` **is not a database status at
  all**: `Database/supabase/schemas/member_memberships.sql`'s view CASE emits
  only `cancelled / ended / frozen / active`, and a past-due row falls through to
  `active`. `overdue` is a CRM **display** status derived in Python
  (`members_status_mapping.is_membership_overdue` — not cancelled, and a
  `next_due_date` already passed) that MASKS the raw status on the way out. So
  the client enum SPLITS the backend's `active`, and matching only `active` +
  `frozen` **under**-blocked: the guard rejects a member in arrears, so the
  kiosk offered them the plan they already hold, took a card and ate the 400 (in
  a group, killing the whole family's signup). It cannot over-block either — a
  recurring membership never gets an `end_date` (`memberships_base` resolves one
  only for non-recurring plans; cancel only ever touches `cancel_date`), so an
  `overdue` RECURRING row can only be masking raw `active` or `frozen`.
  `dormant` and `trial` are still excluded: neither can mask a raw
  `active`/`frozen` **recurring** row.

**Both clients now derive this ONE rule from that ONE guard.** The CRM's own
`start_plan_rules.dart` (`disabledPlanReasons`) was aligned to the same
recurring + `{active, frozen, overdue}` shape, so a divergence in either
direction is a bug rather than a deliberate asymmetry — the only difference that
remains is the CONSEQUENCE: at a desk a false block is visible and staff reason
about it, while at a kiosk it silently turns away a paying customer with no
override. The kiosk still does not IMPORT `start_plan_rules.dart` (the kiosk is
kiosk-native presentation over the shared data layer), so the two must be kept
in step by hand: **change one, check the other, and both against the SQL.**

**Zero new requests, and the ids live on the PERSON.** The held set is derived
from the SAME `getMemberDetail` response the trial rule already fetches, and is
stored on `KioskSignupPerson.heldRecurringPlanIds` — never on the state root. The
plan step is walked once per training person under a fixed layout, so a
state-root map would be one stale read away from printing a parent's membership
on a child's turn; per-person storage makes that leak **unrepresentable**,
exactly as `hadTrial` does. `bloc/kiosk_signup_plan_block_test.dart` asserts it
by advancing the active person and checking that the notice text *and* the
blocked set both change with them.

**It FAILS OPEN too, and the cost is stated rather than hidden.** On a read
failure the kiosk does not know WHICH plan somebody holds, so a fail-closed
posture would have to block the whole grid — the worst outcome available. The
cost of failing open is the dead end above; it is accepted, not airtight.

**The membership is STATED, not only marked.** `KioskInlineNotice` at the top of
the plan step's body says which plan they are on before they start picking, so
the marked card has an answer above it and not only behind a tap. It is
self-gating (nothing held → no notice), so a brand-new member never sees it. See
§8.1a for the body order and §9 for the privacy allow/deny list.

**The picker offers the ROSTER first, then the CRM.** The people already on
this signup are standing right there, so they are listed and directly pickable;
the shipped kiosk name search (`KioskMatchSearch(forPayer: true)`) sits under
them for anyone not on the roster yet, driving the **one** debounced,
sequence-guarded search the cubit already owns. Both lists render through the
same affordant `KioskNameRow` — a **contained, bordered, ripple + chevron** row
(the kiosk's ONE "tap a member" affordance, shared with the home check-in
search), because a pickable member must read unmistakably as pressable rather
than as a heading. The section heads (`KioskSectionHead(quiet: true)`) are
demoted to quiet left-aligned labels so the rows dominate. **The current payer
is not offered** while one exists — picking whoever is already paying is a no-op
dressed as a choice — and is named in the pinned `PAYING NOW` strip instead. In
the NO-PAYER state there is no one to exclude and no strip: every remaining
person (index 0 included) is a candidate (`payerCandidateIndexes`), and the
member must pick one to continue.

**One seat path, uniformly.** `_seatPayer` is the ONE path a payer is ever
seated by, and **nothing is special-cased**. Its single precondition is
`canAssignPayer` (nothing linked, nothing signed), which covers BOTH a switch
and a first choice after a delete — so a payer chosen after the previous one was
deleted goes through exactly the same code. One path means one place the seat
rules live and no branch a future change could route around.

Two seatings, one path:

- **CRM pick** (`_seatNewPayer`) — INSERTS them at the head; the person who
  started the signup keeps their seat as a payee and every index shifts by one.
- **Roster pick** (`_promoteRosterPayer`) — a straight SWAP of positions 0 and
  k, so every other index (and every signature, link and plan keyed on one) is
  untouched. The promoted person keeps their own membership choice and plan:
  they were signing up before and they still are.

Either way **only the payer role moves**, so the demoted person now needs the
payer-authorization waiver like any other payee — which `everyPayeeLinked`
enforces for free (see §11.5). A hit already on the roster is answered
**inline** on the picker (a redirect to the list above), never a stop.

**The offer is withdrawn the moment anything commits.**
`KioskSignupState.canSwitchPayer` is false once any payee is `linked` or
anything is signed — there is no unlink call, so a later swap would leave the
roster authorized to somebody who is no longer paying and assemble a start
request against a payer the backend never authorized. **Until then, switching
is freely REPEATABLE** — changing who pays is not capped at one swap, and the
demoted former payer (an adopted `wasExisting` outsider included) simply becomes
an ordinary unlinked roster payee, keeping their membership/training choice and
removable via the trash. Nothing is stranded, so nothing is refused on "who was
paying before"; a link or a signature is the ONE thing that pins the payer.

#### Everyone on the roster chooses, and at least one must say yes

`KioskSignupPerson.training` is the same control on **every** roster row —
"{Name} is getting a membership as well", or "I'm getting a membership" on a
roster of one, where the comparison has nobody to be against — rendered with
the shipped `KioskConsentCheck` and **defaulting ON** for everybody: payer,
payee, created here or adopted. A payer-only special case was one more thing
to explain on a screen that has to explain itself.

It is **stacked**, on its own line under the identity row. Inline it was a
15px label competing with an avatar, a pill and two icon buttons — unreadable
at arm's length, on the one control in the row that decides whether a person is
charged.

**At least one person must keep it ticked** (`anyoneTraining`). An empty cart
would send `memberships: []` and take a 400, so the roster cannot leave — and
because every check is individually untickable, a member can reach that state
by hand. The step therefore disables Continue **and says why**: "Tick whoever's
getting a membership — we need at least one to carry on." A dead button with no
explanation beside it is the failure mode that copy exists to prevent. Ticking
anybody releases it immediately.

`trainingPersonIndexes` drives the rest unchanged: only ticked people get a
plan, their plan's waivers and a line in `memberships[]`. An unticked person is
still created and still on the roster — a parent paying for their kids is
exactly this, and so is a member who registers today and buys later.

#### The plan step's "Skip" — changing your mind mid-way

**Somebody halfway through a family signup may decide they don't want a
membership after all** (founder ruling), so the plan step carries a
**`Skip`** control in `KioskFlowFoot`'s right-hand Skip gutter —
the same gutter the optional-details step's Skip uses, a full stage away from the
escape and from the primary.

- **GROUP only.** `onSkip` is null in a solo signup and `skipPlanForPerson`
  refuses the call anyway: skipping the only person would empty the cart, and at
  least one person must get a membership.
- **It reuses `training`, never a parallel concept.** "Not getting a membership"
  is precisely what that flag already means, so the cart, the waiver queue, the
  review and the roster chip all follow for free. Their plan is dropped with it,
  exactly as `setPersonTraining(_, false)` does.
- **It advances to the next person who still needs a plan**, and to the waiver
  run when nobody is left.
- **Skipping EVERYBODY returns to the People step** (founder's explicit
  resolution — better than a guard). The roster is where a person can be ticked
  back on or removed, and it already blocks Continue on the empty cart and says
  why ("Tick whoever's getting a membership…"), so the backend's empty-cart 400
  stays unreachable by construction.

The label is the bare verb `Skip`: the pinned identity band already says who
is being skipped ("PICKING FOR · Ella"), so repeating it in the gutter would say
the same thing twice. It deliberately overrides `KioskFlowFoot`'s default
`Skip for now`, which would promise a later that does not exist here.

#### Removing somebody asks first — the payer included

The roster's remove control is a **trash** glyph and it opens
`KioskRemoveConfirm` — the shipped `KioskIdleWarning` / `KioskAbandonConfirm`
surface reused whole, so the kiosk keeps exactly ONE modal vocabulary. It
**names the person** (a roster of four all wearing the same glyph cannot
otherwise say which one is going), and it follows that pattern's weighting:
**the SAFE choice is the primary**, so a member reaching for the biggest,
bluest thing on the screen lands on "Keep them". Removal has no undo and the
rows sit close together at kiosk scale.

The control is still offered only while removal is FREE — the moment that
person is `linked` or has signed anything it disappears rather than becoming a
button that cannot do what it says (§11.5).

**The PAYER is deletable too** (founder ruling: nobody on the roster is
special). It is offered only in a group (never the sole person — that is what
"Start over" is for) and only while `canRemovePerson` holds for them: nothing
`linked`, nothing signed — the same "nothing committed" condition a payer SWITCH
needs, because deleting a payer a payee has authorized would strand that
commitment. Unlike a switch, removal takes them off entirely, so an ADOPTED
`wasExisting` payer CAN be deleted (there is no one to strand); clearing them
leaves the roster coherent (their shell is left alone, like any removal, and
surfaces in the Incomplete tab).

**Deleting the current payer ALWAYS asks who pays next** (never auto-assign).
`removePerson` clears the payer designation — the signup now has NO payer, none
of the remaining people is one — and routes straight into `payerPick` to choose
(`KioskRemoveConfirm` says so: "they're paying for everyone, so next you'll
choose who pays"). The **no-payer state** can exist ONLY on the People and
payer-pick steps: it is `!hasPayer` (`payerOrNull == null`), and the People step
blocks Continue on it (in addition to the empty-cart guard) with a plain
blame-free reason ("Choose who's paying to continue.") beside a "Choose who's
paying" affordance — never a dead button. `continueToPlans` and
`_buildStartRequest` both guard on `hasPayer`/`payerOrNull`, so **a no-payer
signup can never reach Pay or assemble a charge.**

#### An adopted existing member is a record the kiosk does not own

`wasExisting` marks them, and it means the kiosk neither prints nor overwrites
their stored details: no Edit affordance on their roster row, no per-person
details step when they are added, and — for an adopted **payer** — no Back out
of the roster at all, because the only screen behind it is a form whose
Continue would PUT the kiosk's typed guess over the gym's own record.

#### The returning abandoner

A member who started a signup, typed enough to create their payer row, then
walked away before paying is a member with no membership. Coming back, they hit
the duplicate check on their OWN half-finished account and "Is this you?" simply
picks the thread up. The CRM's **Incomplete** tab on the members list is the
staff-side counterpart: it lists exactly these no-membership shells (a member
who holds no membership and pays for nobody else's —
`src/members/sql/crm_views/_member_incomplete.sql`), and each row's **Finish
signup** button opens that member's page straight into the CRM's own
start-membership wizard.

The entered card is **always** kept (`set_default: true`, whatever the cart
holds — §11.4), so the attach → pay → detach path the backend runs for a
one-time-only cart with `set_default: false` is never taken from here.

This is a **frontend guard** (accepted, given the supervised iPad + Guided
Access). Which means: it holds only as long as no kiosk screen imports a
saved-card/payer-selection widget. Treat any such import as a defect.

#### The card surface, and naming the profile it lands on

`presentation/widgets/signup/kiosk_card_step.dart` is the ONE card surface on
the kiosk: it wraps the shared
`member_details/presentation/dialogs/card_field_box.dart` (a single-line
combined Stripe element — the mockup's four separate boxes are superseded),
tokenizes there with `Stripe.instance.createPaymentMethod`, and hands the cubit
only `pm.id` / `pm.card.brand` / `pm.card.last4`. It copies the tokenize CALL
from `one_time_card_dialog.dart` but **may never import it** — that module is on
the banned list below. `set_default` is unconditionally true, never a picker and
never a branch.

**The card is tokenized on the gym's CONNECTED account, not the platform.** The
backend runs direct-charge Connect (customer + card + subscription all live on
the gym's connected account), and a platform-owned `pm_…` cannot attach to a
connected-account customer — so the browser must mint the PaymentMethod on the
connected account. `CardFieldBox` gates its Stripe `CardField` on the
`stripeAccountContext` seam (`lib/core/network/stripe_account_context.dart`),
which `selectedGym.setActiveGym(...)` drove with the gym's `stripe_account_id`
at login; the field mounts only once the account is applied (a `CardField` binds
to whichever JS Stripe object exists at mount time). This is not kiosk-specific
plumbing — it is the same seam the CRM billing dialogs use — but it is what makes
the kiosk's browser-tokenized card actually attachable. A gym with no connected
account (not onboarded) fails closed: the field never mounts, mirroring the
backend's `paymentsUnavailable` stop.

**Every attempt gets a genuinely FRESH field.** The `CardField` is a Stripe
iframe whose web platform view is CACHED across mounts, so re-entering the step
would otherwise reuse the iframe still holding the last number typed while the
step's own `_complete` flag resets to false — leaving *Review* permanently
unreachable and the member unable to type anything at all. The step keys
`CardFieldBox` (`fieldKey: ValueKey('kiosk-card-${state.cardAttempt}')`), and
**every route back into the step bumps `cardAttempt`** — `retryCard()` after a
decline, and `back()` out of the review — so it always mounts a brand-new, empty
iframe. Both routes drop the tokenized card, the key and the preview with it, so
state never claims a card the member cannot see. `CardFieldBox` exposes an
optional `fieldKey` (null for every non-kiosk caller) for exactly this.

**The step names the PAYER, pinned, and reads them off the roster's payer seat
— never off `activePersonIndex`.** In a family the active person is usually a
child while the payer is the parent, so a name taken from the wrong place would
be confidently wrong about which profile a card attaches to, which is worse
than naming nobody. The `KioskWhoFor` strip carries it ("CARD FOR Marcus
Bell"), and the notice under the field attaches the same name to the promise, so
*saved*, *to whom* and *what it displaces* are one sentence. With no name to
hand it degrades to "your profile" rather than to a wrong one. The card step's
subtitle is dropped in a group for the same reason: `selectedPlan` reads the
active person's plan, which at that point is whoever signed last.

**The body order is `[KioskSecureStrip] → [CardFieldBox] → [error?] →
[KioskInlineNotice] → [KioskCardFacts]`, and each position is an argument.**
The secure strip sits ABOVE the field because it answers "is it safe to type
this here", which has to arrive before the box does. The replacement notice sits
BELOW it because it is a what-happens-afterwards fact — and it rides
`KioskInlineNotice` (17px `kioskBody` on the warm fill, 24px glyph) rather than
joining `KioskCardFacts`, whose lines each sit behind a GREEN CHECK meaning
*good news, don't worry*. Rendering "we are replacing your card" as a green tick
would be actively misleading. What is left in the facts block is genuinely
reassurance: "Cancel any time at the front desk." (only when the cart has
something recurring to cancel) and the always-on "This screen wipes itself if
you walk away…".

**It is enforced in CI, not by convention.**
`CRM/test/features/kiosk/kiosk_forbidden_imports_test.dart` walks every file
under `CRM/lib/features/kiosk/` and fails on an import of `saved_card_section`
· `one_time_card_dialog` · `update_card_dialog` · `discount_picker_dialog` ·
`draft_discounts_card` · `added_discount_chip` · any `custom_discount_*` ·
`live_discounted_price` · `start_payer_step` · `choose_payer_view` ·
`payer_radio_tile`, and separately fails on the word "discount" appearing
anywhere in the kiosk feature at all. It also asserts each guarded file still
EXISTS, so a rename can't silently turn the ban into theatre — if one of those
modules is legitimately renamed, rename it in both lists in the same change.

Those bans are on the **CRM's own** payer-selection and saved-card surfaces,
which offer a card the kiosk did not take. The kiosk's own payer picker is not
one of them: it only ever names WHO pays, and whoever it names still types a
fresh card at the end. `bloc/kiosk_signup_payer_test.dart` is the behavioural
half of the enforcement — all three entry points, and the one seat path.

### NO discounts reach the kiosk — enforced structurally

Neither staff-applied discounts nor member-entered promo codes exist on the
kiosk. **This is enforced by the kiosk never IMPORTING a discount-shaped widget,
not by a flag.** A `showDiscounts: false` parameter is one wrong default, one
flipped boolean, or one new call site away from a member discounting their own
membership.

The invariant: **`grep -ri discount CRM/lib/features/kiosk/` returns
nothing**, and the forbidden-imports test above is what keeps it that way.
Phase D does not reuse the CRM's `start_memberships/` wizard at all — it is
kiosk-native presentation over the existing data layer, precisely so the kiosk
is never dragged through a future discount change; `add_member/` and
`start_memberships/` are READ-ONLY pattern references.

### The app invite is never asked about — `send_invite: true`, always

`MembersManagementCreateRequest.send_invite` is **required with no default** on the backend
(`FastApiBackend/src/members/schema/members_schema.py`; omitting it is a 422), and the CRM's admin
dialogs answer it with a two-action footer — "Create & invite" vs. create without. **The kiosk does not
ask. It hardcodes `sendInvite: true` at BOTH of its create sites** — `kiosk_signup_cubit.dart:289` (the
signup lane's ONE `createMember` for the person being signed up) and `:702` (the payee/payer create on
the already-a-member fork).

This is a founder decision, not an oversight, and it should not be "fixed" into a prompt:

- **The intent a prompt would ask about has already been expressed.** Someone signing up on the gym's
  own iPad is standing there typing *their own* email into it. The admin dialogs ask precisely because
  staff are creating a row **for** someone else, and only staff can know whether that person wants mail;
  here there is no third party to ask about.
- **The lane is tuned for speed.** A prompt is one more screen and one more tap on a surface whose whole
  design goal is a member getting through unattended (§0). Adding a question a member has no basis to
  answer trades that away for nothing.
- **The outcome is deliberately not surfaced either.** The create's `invite` field
  (`queued` / `held` / `skipped_no_email` / `skipped_suppressed` / `not_requested`) is read and
  discarded here. A member can't act on "held" — that is a deploy fact about `EMAIL_ENABLED_KINDS`, not
  something the person at the iPad did wrong — and putting it on the welcome screen would be an error
  message for a problem only staff can fix. The admin dialogs report it because staff CAN act on it.
- The member app invite is a **`marketing`** kind (`FastApiBackend/src/emails/emails_registry.py`), so
  every send carries an unsubscribe link and a prior unsubscribe silently resolves to
  `skipped_suppressed` — the opt-out lives with the member, at the address, not in a kiosk checkbox.

Both call sites carry the reasoning as a comment; keep the two in sync if either is touched.

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

**PAUSED classes never reach the kiosk at all.** `GET
/api/v1/classes/instances` takes `include_inactive` and defaults it to
**false**, so a paused class (`gym_classes.is_active = false`) contributes no
occurrences to either list here — server-side, for free, with nothing to
remember. Do NOT add an `isActive` filter in the cubit and do NOT pass the
flag from any kiosk read. (Check-in would reject a paused class with
`code: class_inactive` anyway — see §4 — which is exactly the bare-400 the
default exists to prevent.) Full contract: the `class-system-guide` skill §3.

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

## 7. Seven clocks, and which one owns which screen

Seven independent timers exist. Confusing them is a recurring source of bugs, so
name them precisely:

| clock | length | scope | on expiry |
| --- | --- | --- | --- |
| **Runway** (`KioskSessionCubit`) | 12h absolute, lockout at 11h45 | the whole session | sign out |
| **Flow-idle** (`kKioskIdleTimeout`) | 5 min, then a 30s visible countdown (`kKioskIdleCountdown`) | any *engaged* flow page | `goHome()` — abandons the draft |
| **Signup stop** (`kKioskSignupStopHold`) | 15s | a terminal signup stop only | abandon → `goHome()` |
| **Signup popup** (`kKioskSignupPopupHold`) | 60s | every BLOCKING read-and-decide signup surface — the decline popup, the plan block, and the per-person **results** receipt | abandon → `goHome()` |
| **Signup welcome** (`kKioskSignupWelcomeHold`) | 60s | the signup's welcome terminal only | abandon → `goHome()` |
| **Glance hold** (`kKioskGlanceHold`) | 10s, started at the LAST reveal beat | the glance only | `goHome()` |
| **App modal** (`kKioskAppModalTimeout`) | 60s | the modal overlay only | `goHome()` |

**Every blocking overlay in the signup lane carries a VISIBLE countdown, drawn
INSIDE the popup** (the shipped `KioskReturnTimer`, the same component the stop,
welcome, glance and get-app surfaces use — never a second timer). This is a
shared community iPad: no screen may hold it forever, and a countdown drawn
behind a popup sneaks the surface away without the member seeing it go (founder
ruling).

**The 60-second popup clock covers THREE surfaces, not one, and that is
deliberate.** The decline popup, the plan block and the results receipt are the
same kind of screen — a read-and-decide surface somebody is standing at — which
is exactly why that constant is 60s and not the stop screen's 15s. A separate
named constant for the results screen would add a row to this table for an
identical duration, which is how a set of clocks desyncs.

Three things about that clock are easy to conflate and must not be:

- **It is a RETURN clock, never a cooldown.** It decides how long the iPad may
  sit unanswered, not how soon an action may be taken. On the decline popup and
  on a partial results receipt, Retry is live from the first frame, uncapped and
  unthrottled (§11.3a).
- **It is 60s, not the stop screen's 15s.** A terminal stop can be reached with
  nobody standing there; these are read-and-decide screens somebody is looking
  at, and 15 seconds is not enough to read three lines and choose.
- **On the two surfaces that do NOT release the flow count on entry** (the
  decline, and a PARTIAL results receipt) this clock is what finally releases it
  when nobody answers.

**Expiry runs the ordinary `abandon()`, never a new exit.** That is what keeps
the flow count balanced by the one latch — and it matters most on the decline,
which deliberately does NOT release on entry (§11.3): if nobody answers it, this
is the thing that finally releases it.

`_syncIdleTimer()` is the arbiter: the idle guard runs only while `_engaged`
(past home, or typing into home's search) and is **suppressed entirely** on the
glance (`view == checkedIn`), while the app modal is open, and on the signup
view. Any pointer-down on the kiosk surface calls `registerActivity()` ("I'm
still here") — except while the modal is open, where it is a no-op.

**The signup lane runs its OWN flow-idle guard**, in `KioskSignupCubit`, off
the SAME `kKioskIdleTimeout` / `kKioskIdleCountdown` constants. It is a
separate timer, not a shared one, because only that cubit knows which of its
steps may be interrupted (it suspends across the payment step and skips the
stop / welcome terminals, which own their own clocks). Two guards over one
surface would race — `KioskFlowCubit`'s would abandon to home mid-signup
*without* releasing the signup's flow count — hence the early return in
`_syncIdleTimer()`. `KioskSignupScreen` therefore hosts its own pointer
`Listener` (the body-level one in `kiosk_screen.dart` reads a cubit provided
ABOVE the signup subtree and cannot reach into it), and `KioskIdleWarning`
takes an optional `onStillHere` so the button answers the clock that is
actually ticking. Omitted, it still defaults to `KioskFlowCubit`.

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

**Ghost is the ESCAPE tier and nothing else uses it** — `KioskEscapeFoot` and
`KioskFlowFoot`'s left gutter are its only call sites, which is what makes the
rule above true rather than aspirational.

`KioskFlowFoot` lays those three slots out as a **Stack, not a three-way Row**,
and that is a robustness property rather than a style: the decision pair is
centred on the WHOLE band, so its optical centre is identical on a step with a
Skip and a step without — and the longest primary the foot ever carries
(`Sign Memberships · $149.00` beside Back, §11.4) can never squeeze a gutter
into an overflow on a short fold. The gutters keep their intrinsic size and the
band simply gets tight. `kiosk_signup_chrome_test.dart` holds it at 1180×820 and
1024×700. It renders a back-chevron, so putting
a non-escape action on it read as a way *out* of the flow; every secondary
action that is a way *in* ("Add someone new", "or find an existing member",
"Change who is paying") rides `KioskOutlineButton` instead.

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

The signup lane's own controls follow the same discipline. Its footer's Skip
rides `KioskOutlineButton` exactly like Back rather than styling an
`AppOutlineButton` at the call site (the mockup's quieter "soft outline" rung
does not exist as a token, and half-adding it is how a ramp desyncs); its
input is `KioskFieldBox`, which reuses `KioskNameSearch`'s box geometry and
`kioskFieldText` verbatim and only adds the focus/error border pair.

**A kiosk surface built on the shared `AppDialog` keeps the DIALOG's own
scale**, body included — `AppDialog` owns an internally-proportional ladder
(title `h1` 24 > body `pBig` 16 > `AppDialogActions`' 13px buttons), and
putting *only* its body on the kiosk ramp desyncs it from the title and
buttons around it the next time the kiosk ramp moves. A genuinely kiosk-scale
dialog shell means a `kiosk` opt-in through `AppDialog` / `AppDialogTitle` /
`AppDialogActions` — a separate call, not something to half-do. (The kiosk
mounts no `AppDialog` today; the signup's modals are the `KioskIdleWarning`
composition instead — see the abandon confirm in §2.)

### 8.1a A signup step's TOP BAND is pinned, exactly like its footer

`KioskStage` pins a `header` to the top of the fold the same way it pins a
`footer` to the bottom, and `KioskSignupStepScaffold` puts the step rail, the
screen head (title + one answering line) and an optional identity strip in it.
The body scrolls beneath.

**The reason is correctness, not tidiness.** The plan step is walked once per
training person and the waiver run once per person per document, so "who is
this for" is the single most load-bearing thing on those screens — and it was
scrolling away the moment anyone touched the grid or the document. The cost of
losing it is the wrong membership bought for the wrong child, or a card
attached to the wrong profile.

`widgets/signup/kiosk_who_for.dart` is the ONE identity element, `KioskSignPanel`'s
"signing for" banner laid on its side (avatar + eyebrow + name). Three call
sites, and **who they name is not the same question**:

| step | names | eyebrow |
| --- | --- | --- |
| plans (group only) | the ACTIVE person | `PICKING FOR` |
| liability waiver (group only) | the ACTIVE person | `SIGNING FOR` |
| payer-auth waiver (always) | the ACTIVE payee | `PAYING FOR` |
| card (always) | **the PAYER** | `CARD FOR` |

**The card step is the one that inverts, and getting it backwards is worse than
omitting it.** In a family the active person is usually a child while the card
attaches to the parent's profile — so the card step reads `state.payer`, never
`activePersonIndex` (§3). The plan and waiver steps omit the strip in a SOLO
signup: with one person there is nothing to disambiguate, and telling somebody
their own name is a strange way to address them.

The same rule runs through the titles: **in a group, EVERY turn is named,
including the payer's own.** An unnamed screen in the middle of a run of named
ones is ambiguous exactly when it matters most.

**The plan step's BODY has a fixed order: the notice, then the picked banner,
then the grid.** Context before confirmation-of-the-action-just-taken. The
`KioskInlineNotice` states the membership the active person already holds (§3's
already-on-plan rule) and the `KioskPlanPickedBanner` confirms what they just
tapped; reversed, the member reads a confirmation before the context that
explains the marked card. Both **scroll with the body**, which is correct: they
are read-once facts, not correctness controls like the pinned `KioskWhoFor`. The
notice passes `onRetry: null` — its optional "Try again" has no meaning here.

**The plan step confirms the pick, and returns to the top after one.** Tapping a
card low in a tall grid otherwise gives no feedback and strands the member at
the bottom, so on a pick `KioskPlanPickStep` scrolls its body back to the top
(the scaffold threads a `bodyController` into `KioskStage`'s pinned scroll view)
and surfaces `KioskPlanPickedBanner` there — a prominent "YOU'VE PICKED {plan}"
confirmation that names the membership in words (the pinned identity strip
already says WHO, so the banner never repeats the person). In a group each
person's turn also starts at the top. The banner **names the plan, never a
price** — money comes from the server preview on the review, so nothing is
derived from a plan row here; and the plan card keeps its own selected mark, so
"which card" and "which plan in words" agree. One plan per person, single-select,
`quantity: 1` — no stepper — is unchanged.

**The waiver's reading box fills the fold.** The waiver steps ask the scaffold
for `fillBody: true`, which hands the body a bounded height instead of a
scroll view; the doc/sign row stretches, `KioskWaiverDocPanel` takes all of it
with an `Expanded` editor, and the signing column carries its own
`SingleChildScrollView` as the short-fold valve. A long agreement therefore
scrolls INSIDE its panel rather than pushing the footer away, and a short one
simply fills. **The panel now requires a bounded height** — it must never be
dropped into a scrolling context. `DesignConstants.dialogWaiverEditorHeight`
(240) stays exactly as it is for the admin dialog and the desk's
`sign_waiver_panel.dart`; it was never a kiosk measure, and a full-screen legal
document a member is being asked to sign does not borrow one.

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
- **Order: "Start Trial / Membership" sits ABOVE the strip.** Both are
  footer-weight bands and only one can own the terminal slot, so the strip's
  hairline is the home's single categorical boundary: above it, every way to get
  in RIGHT NOW (scan / search / buy); below it, the one thing that is about
  later. Somebody with nothing to train on is *blocked* at the kiosk and
  outranks a nudge nobody
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

### The lobby line on a member's OWN stored data

The kiosk runs on a **shared lobby iPad**, so what it may print about a
self-identified member is a short allow-list. Naming the PLAN a member holds, on
their own signup turn, is inside the line the match card already draws (a full
name plus a masked email). Everything else is outside it.

**May appear:** the plan **name** of an `active`/`frozen` `recurring` membership
held by the **active person**, and only when that plan is in the warmed
catalogue. A held plan the gym no longer offers resolves to nothing and is
silently omitted — it cannot be picked, so there is nothing to prevent, and
storing its name would create a second source of truth for something the
catalogue owns.

**Must NOT appear, anywhere:**

- **No price they pay.** The card shows the plan's own CATALOGUE price, which it
  always did; nothing reveals their actual billed amount or their pinned price
  version. (§3's structural no-discounts rule means the kiosk has no vocabulary
  for the rest of it — keep it that way.)
- **No dates.** No start date, no `nextDueDate`, no renewal date, no freeze
  window.
- **No status word.** "Frozen" / "Overdue" is billing state about a person,
  printed in a lobby. A frozen plan is blocked and labelled `You have this`
  identically to an active one: the member learns *that* they hold it, never
  *how it is doing*.
- **No one-time or trial packs.** They are not conflicts (they stack), so
  surfacing them would be pure disclosure with no purchasing consequence.
- **No count**, and **no other member's memberships, ever** — the notice and the
  blocked set both read `state.activePerson`, which is what makes the group leak
  unrepresentable rather than merely avoided (§3).

**Every IDENTIFICATION line masks the address; the two RECEIPT lines do not, and
that split is the rule.** An identification line exists so the member can tell
"that's my account", which a masked address does — so the roster row, the payer
picker, the match card **and the solo review's "YOU" row**
(`kiosk_review_side_panel.dart`) all render `kioskMaskedEmail`, and a person with
no address gets no line at all rather than an empty one. The exceptions are the
money panel's *"Your receipt goes to …"* and the results receipt's *"Your receipt
is on its way to …"*: those exist so the payer can VERIFY where a receipt lands,
which needs the real address, and both are about the payer's own address on a
screen they are standing at. Anything new that merely says WHO somebody is masks;
only a line about where a receipt is being sent does not.

The same rule governs the results receipt: it names the person and the plan and
states the outcome, and it never prints a raw backend error string
(`item.error` is Stripe or internal prose — right at a staff desk, wrong in a
lobby) — see §11.6.

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

- **Phase D — the SOLO signup, end to end.** The kiosk's "Start Trial /
  Membership"
  calls `KioskFlowCubit.startSignup()` (the same `canStartFlow` gate
  `selectMember` uses; it does **not** `beginFlow`), which routes
  `KioskView.signup` to `KioskSignupScreen`. That screen provides its own
  **`KioskSignupCubit`** — a sibling of `KioskFlowCubit`, never more fields on
  it — so the cubit's lifetime IS the flow's lifetime and PII disposal is
  structural. Built: the `KioskSignupStep` spine + flat `KioskSignupState`,
  the details and extra-details steps, the ONE `createMember` call carrying
  both, **the plan pick, the waiver run, the card, the review, the pay lock,
  the per-person results receipt, the decline and the welcome**, every
  front-desk stop, the lane's own 5-min
  idle guard, the abandon path, and the shared chrome under
  `presentation/widgets/signup/` (flow rail, three-slot foot, field box,
  consent check, DOB wheel, stop screen, abandon confirm). See §11 for the
  money-path rules that lane encodes.

- **The lane's own front door — new here, or already a member.** The spine
  opens on `KioskSignupStep.entry` (`kiosk_entry_choice_step.dart`, the home's
  own `KioskHomeColumns` composition over two `KioskSectionHead` halves,
  scaffold `fillBody: true` because those bands need a bounded height). "I'm new
  here" goes to `details`; "Find my name" goes to `KioskSignupStep.identify`
  (`kiosk_identify_step.dart`, `KioskMatchSearch(forPayer: true)` with its own
  `noMatchMessage`), where an existing member taps their own name and confirms
  it on the shipped `payerMatch` card. Neither step carries a `KioskWhoFor`
  strip (nobody is seated yet) and **neither adds a rung** — both light rung 0,
  the same precedent `payerMatch` set on rung 1. See §3 for what the identify
  route seats.

- **The per-person results receipt.** `KioskSignupStep.results`, between
  `paying` and `welcome`, drawn by `widgets/signup/kiosk_results_screen.dart`
  over the new `kiosk_result_row.dart` and `kiosk_results_foot.dart` (and the
  `kiosk_two_charges_note.dart` the review now shares). It answers BOTH a fully
  successful start (a receipt, one `Next` into `welcome`) and a **partial** one
  (the decline ladder at a narrower scope); an ALL-failed start still goes to the
  decline popup. See §11.6.

- **The two plan-block reasons and their ONE popup.** `KioskPlanBlock` over the
  plan grid, `presentation/kiosk_plan_block_copy.dart` as the reason→words map,
  `KioskPlanCard`'s `blocked` + `blockedLabel` state
  (`Already used` / `You have this`), the plan step's `KioskInlineNotice`
  stating the membership already held, and
  `KioskSignupStopReason.trialAlreadyUsed` / `alreadyOnPlan` as the two desk
  handoffs. See §3.

- **The plan step's "Skip" control** — group-only, reusing `training`, and
  skipping everybody returns to the roster. See §3.

- **Phase E — the GROUP (family) signup.** The roster loop is built on the same
  cubit: `people` (always visited — ruling 8), `personDetails`, `match`, the
  per-payee payer-auth link, per-person plans and waivers, and the group
  review. `KioskSignupPerson` grew `linked`; `KioskSignedWaiver` grew
  `memberId`. Screens under `presentation/widgets/signup/`: `kiosk_people_step`
  + `kiosk_roster_row` + `kiosk_person_adder`,
  `kiosk_match_step` + `kiosk_match_card` + `kiosk_match_search`,
  `kiosk_payer_waiver_step`, and `kiosk_review_group_panel` +
  `kiosk_person_block` + `kiosk_money_labels`. `kiosk_signup_optional_step`
  serves BOTH the payer's D1a and every payee's E1a (one widget, parameterized
  by the active person; the fields live in `kiosk_optional_fields`). See §11.5
  for the group's own money rules.

- **The payer's three entry points.** `KioskSignupStep.payerMatch` +
  `kiosk_payer_match_step` (the "is this you?" confirm, reached from the
  identify search OR from a duplicate 409, with a subtitle and a "no" that both
  branch on which) and `KioskSignupStep.payerPick` + `kiosk_payer_pick_step`
  (the "someone else is paying" picker, over
  `KioskMatchSearch(forPayer: true)`), all seating through the one
  `_seatPayer`. See §3.

- **The pinned step band.** `KioskStage`'s `header` + `fillBody` slots,
  `KioskSignupStepScaffold`'s `identity`, and the one
  `widgets/signup/kiosk_who_for.dart` element the plan, waiver and card steps
  share. See §8.1a.

- **`date_of_birth`, end to end.** The optional-details step's DOB wheel
  writes through to a real column: `members.date_of_birth` (nullable `DATE`,
  hand-authored migration `20260724013459_members_date_of_birth.sql`) is
  carried by the create/update request + response schemas, `insert_member.sql`
  / `update_member.sql`, and the billing-detail read
  (`members_billing_detail_service.py`) alongside the other optional contact
  fields (phone, address, emergency contact) it sits beside.

- **The CRM's Incomplete tab, the staff-side counterpart of an abandoned
  signup** — see §3 for the duplicate-gate mechanics it resolves.

**Not built:**

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

## 11. The signup's money path — the rules that keep it from charging twice

The solo signup is the kiosk's only money-moving surface. Everything below is
structural: it holds by construction, not by remembering.

### 11.1 Two independent double-charge defences, not one

`KioskSignupCubit.pay()` carries both, and **neither may be removed on the
grounds that the other covers it**:

1. **The synchronous step guard.** `pay()` returns immediately if the step is
   already `paying`, and it emits `paying` **before its first `await`** — so a
   second tap in the same frame sees the new step. A double-tap is exactly one
   charge. (The Paying screen also has no buttons at all; that is a third
   layer, not a substitute.)
2. **The "sent" latch** (`_sentAttempts`). Once a start POST has gone out for an
   idempotency key, that key is **never posted again**, whatever happened to the
   response. An ambiguous outcome (a dropped connection, a timeout) therefore
   routes to `KioskSignupStopReason.paymentUnconfirmed` — a front-desk handoff
   that says plainly it will not retry — and **never auto-retries**.

The backend's `ON CONFLICT (idempotency_key)` replay guard is the second line,
not the first. The client latch has to stand on its own.

### 11.2 Response routing — a decline is a RESULT, not an error

| outcome | goes to |
| --- | --- |
| 201 / 207, **every item created** | `results` — the per-person receipt, one `Next` into `welcome` |
| 201 / 207, **PARTIAL** (some created, some not — or any `unknown` status) | `results` — money HAS moved for the group that cleared, so the decline popup's "you haven't been charged" would be false. It carries the retry ladder **and** a `Next` into `welcome` (§11.6) |
| 207, **every item failed** | `declined`, unchanged — the popup's copy is true exactly here, and it is where the founder's retry ladder lives |
| a landed 2xx with **no items at all** | `welcome` — a receipt with no rows is worse than the warm welcome |
| **409** `MembershipStartReplayError` | `welcome`, unchanged — an idempotent replay; the ORIGINAL start stands, charging again is the one thing it must never become, and the 409 body carries **no** `MemberMembershipsStartResponse`, so there is nothing to itemise |
| 422 `WaiverGateException` | back to `waivers`, seeded with exactly the ids the server named |
| 500 / transport | `stop` — "nothing was charged" |

A 207 is a **2xx**, so the split is read off the response's own ITEMS, never off
a status code. Treating a 409 as a failure would double-charge on the retry;
treating a 207 as a success would tell a member they joined when they did not.

**The split is THREE ways, and the middle branch is a repaired honesty bug.**
Every failure used to collapse onto `declined`, whose body says the member has
not been charged. On a partial that is **false** — the succeeded charge group's
money has moved. The three-way split fixes it without touching the decline popup:
`declined` keeps the all-failed case where that copy is true, and the partial
gets a screen that can be honest about split money.

**Reachability, worth stating:** a partial needs a cart with **both** a
one-time/trial plan and a recurring plan, where exactly one of the two charge
groups failed. A kiosk **solo** cart is one person, one plan, one item, one charge
group — so **partial failure is structurally group-only.**

`unknown` (`MemberMembershipsStartStatus`'s forward-compatible fallback) is
neither created nor failed, so it falls into the partial branch: the member is
never told "you're all set" about a row the backend would not confirm, and that
row's own line claims nothing about money in either direction.

**The 422 route drops the named waivers from the signup's own signed set.** The
server is authoritative — skipping a waiver it is blocking on loops the member
forever.

### 11.3 Flow-count discipline on the money screens

| screen | releases on entry? | why |
| --- | --- | --- |
| `paying` | **never** | a live charge is exactly what the T+11h45 grace window exists for |
| `results`, every item created | **yes** | the money has landed and every row exists; nothing is left but to read and tap Next. This is EARLIER than the old welcome-only release, which is strictly better for the lockout |
| `results`, **partial** | **no** | Retry is live on that screen, and `pay()` would then run a live charge with no flow held — the exact thing this section forbids. Its `Next` into `welcome` is what releases it (below), and the 60s expiry's `abandon()` if nobody answers |
| `declined` | **no** | the member is still standing there and can retry, however many times |
| `welcome`, every terminal `stop` | **yes**, exactly once | |
| a **retryable** stop (`plansUnavailable`, `previewFailed`) | **no** | "Try again" returns to a live flow |

`_flowStarted` is a latch, so `_enterWelcome`'s own `_endFlowIfStarted()` is a
harmless no-op on the all-created path — and it is still the ONLY release for
every other route into welcome (the 409 replay, a landed start with nothing to
itemise, and **`Next` off a PARTIAL receipt**, which by definition did not
release on entry). **Never delete it**: deleting a release call is how the kiosk
stops signing itself out at its lockout (`CRM/CLAUDE.md`, kiosk bullet 4).

Wherever a screen does not release on entry, its own 60-second return countdown's
`abandon()` releases it if the member walks off.

### 11.3a A decline is never an ending, and there is no wait between attempts

**No number of declines ends a signup, and no attempt is ever gated by a
client-side wait.** Mistyped cards and short balances are ordinary, so a member
may retry immediately, as many times as they like. The declined screen's
reassurance is warm and **uncounted**: a tally next to a bank refusal reads as a
countdown to being cut off, which is not something that happens here.

**The decline popup stacks THREE live actions, Retry first** (founder: retry is
the most common case, because the most common decline is insufficient funds —
the member moves money and tries the exact card again):

- **Retry** (`KioskPrimaryButton` → `retrySameCard`) — re-attempts the **SAME**
  card the member already entered, keeping `paymentMethodId` / `cardBrand` /
  `cardLast4` and minting a **NEW** idempotency key, then re-firing `pay()`. It
  does **not** clear the field or bump `cardAttempt`. A new key is mandatory:
  reusing the sent key would replay the decline through the `_sentAttempts` latch
  instead of making a genuine fresh attempt.
- **Try another card** (`KioskOutlineButton` → `retryCard`) — CLEARS the card,
  bumps `cardAttempt` (so the Stripe iframe re-mounts empty, §3), and drops the
  member back on the card step for a different card, which re-mints its key
  through `submitCard`.
- **Get help at the desk** (`KioskOutlineButton` → `getHelpAtDesk` →
  `_stop(cardDeclined)`) — the always-available handoff, holding committed state
  for the staff Incomplete list. **Never the destination** — nothing routes a
  member to the desk on their behalf.

There is no cooldown, no attempt cap, and no `pay()` gate on a decline run — a
member can retry the same card back-to-back with no wait. Attempt-velocity
throttling (the card-testing vector on an unattended device) rides **entirely on
the platform Stripe Radar rule** (a founder decision), not the client. This is
the industry shape: rate limiting + Radar, not a client-side strike count. **Do
not model Visa's per-card reattempt limit client-side** — every "Try another
card" tokenizes a brand-new payment method, and classifying decline codes is the
processor's job.

**The popup's 60-second `KioskReturnTimer` is not a cooldown and must never be
conflated with one** (§7). It answers a different question — how long a shared
iPad may sit here with nobody answering — and it gates nothing: Retry is live
from the first frame. The two were conflated once, and the countdown went out
with the cooldown; the surfaces test now asserts both halves.

None of it weakens the money-safety properties: **both** retry paths mint a NEW
idempotency key, re-send **only** what the landed start did not CREATE
(`state.retryMemberIds` — see §11.5), and never re-create a member, re-sign a
waiver or re-link a payer. `pay()`'s synchronous `paying`
guard + the sent-key latch keep a double-tap (of Retry or of Pay) to exactly one
charge, and a 500 / transport failure is still the "nothing was charged" stop —
this is the 207 path only. The popup's own 60-second return countdown is what
finally releases a declined screen nobody is standing at, through the ordinary
`abandon()`.

### 11.4 The rules the copy and the request encode

- **`set_default` is unconditionally TRUE, whatever the cart holds.** The kiosk
  takes a fresh card every time and always makes it the payer's default,
  replacing whatever was on the profile — which is what lets an existing member
  self-serve here at all (§3). It does not branch: a recurring cart needs it
  anyway (a subscription can only bill the saved default, and the backend
  rejects a recurring start without one), and sending it on a one-time-only cart
  is legal — the backend only rejects `set_default: false` on a recurring cart —
  and simply means the attach → pay → **detach** path is not taken, so the card
  is not ripped back off. The card step's notice states that consequence in as
  many words (§3, "The card surface"). **Do not copy
  `start_memberships_wizard.dart`'s retry card logic** — the CRM deliberately
  sends NO card for a recurring cart because it reuses the payer's saved
  default, and the kiosk has none.
- **ONE request builder.** `_buildStartRequest` is the only place a start
  request is assembled, for the preview and the charge alike, so there is a
  single place to audit that nothing price-reducing is ever sent (each item
  carries the model's empty defaults) and that `paidWithCash` is pinned false.
- **The ONE piece of client arithmetic** is due-today =
  `(oneTime?.total ?? 0) + (dueNow?.total ?? 0)`
  (`KioskSignupState.dueTodayMinorUnits`), mirroring the CRM's
  `start_preview_step.dart:281-284`. It is safe **only because the kiosk pins
  `prorate_to_anchor`** — the CRM reads `_effectiveDueNow`, which nulls the
  due-now half for `no_charge`, a proration the kiosk never offers. Never derive
  a price from a plan row.
- **The "two separate charges today" note tests AMOUNTS**, not nullness, and
  never falls back to `recurring`:
  `(oneTime?.total ?? 0) > 0 && (dueNow?.total ?? 0) > 0`
  (`start_preview_step.dart:276-278`). A $0 one-time line is a present invoice
  with nothing on it; calling that two charges lies about the member's own bank
  statement. **ONE widget carries the sentence on both screens** —
  `KioskTwoChargesNote`, called by the review's money panel and by the results
  receipt — so the member reads the identical string before and after the card is
  taken. **Never gate it on the start response's own `multiple_charges` flag**:
  the backend computes that from the request's plan TYPES without looking at
  amounts, so it is true even when one group's invoice is $0, which is precisely
  the lie this predicate exists to avoid. The receipt's full condition is
  `state.allCreated && state.chargedTwiceToday` — on a partial one of the two
  charges did not happen, so "two separate charges" would be false there too.
- **`declined` is a POPUP acknowledgement whose primary action retries the SAME
  card.** `KioskDeclinedScreen` is the kiosk's one modal vocabulary (veil +
  centered popup card) carrying the blameless reason ("Your bank declined the
  payment"), the card chip, **three stacked buttons** and the 60-second
  `KioskReturnTimer` (§7): "Retry" (primary, → `retrySameCard`, re-charges the
  same card with a new key), "Try another card" (secondary, → `retryCard`, drops
  the member back on the card step with a fresh empty field), and "Get help at
  the desk" (the always-available handoff, → `getHelpAtDesk` →
  `_stop(cardDeclined)`, holding committed state). All three are live from the
  first frame, there is deliberately no "Start over" (§2), and none is ever
  forced (§11.3a). Three kiosk-scale labels do not fit side by side in a
  `dialogMaxWidth` popup, so they stack; a test renders all three plus the
  countdown at 1180×820 with no overflow.
- **The decline body is scoped to what is actually still true — it may NOT
  reassure about the ACCOUNT.** The start attaches the fresh card, promotes it to
  the payer's Stripe default and detaches the previous one **before** it attempts
  the charge, and a decline reverts **neither** (founder ruling, option 4:
  accepted, because "this makes everything more complicated for an edge case
  that'll likely be fixed by them choosing a new card"). So the charge half
  stands — nothing was taken — while the card on file has already been replaced.
  The popup says both:
  *"You haven't been charged, and nothing you filled in is lost. The card you
  entered is now the one saved on your profile."*
  The retired sentence was "…and everything else you filled in is saved": its
  "everything ELSE" invited exactly the reading that nothing else about their
  account had changed. **The `cardDeclined` STOP reassurance
  (`kiosk_signup_stop_copy.dart`) carries the same correction**, because
  `getHelpAtDesk` is only ever reached FROM that popup and the two must not
  disagree. `paymentFailed` is deliberately left alone — it also covers the
  nothing-was-sent cases (no card, an unassemblable request) where "nothing
  changed" is exactly true.
- **The review's committing button reads by WHAT is being bought.** `Sign Trial`
  only when every training person's pick is `PlanType.trial` (a mixed group cart
  is a membership purchase taken as a whole), `Sign Membership` otherwise, both
  pluralised past one training person, and `Verb · Amount` whenever anything is
  due today. **The amount stays on the button** — that is the shipped safety
  property: the button is inert until the amount is real, so a member can never
  commit before the screen can tell them what for. A trial is a plan CATEGORY,
  not a price (a gym may sell a paid two-week trial), so the amount is not
  optional on a trial either; it collapses to the bare verb exactly when there is
  nothing to say. The review's subtitle is deliberately **button-agnostic**
  ("Nothing is charged until you confirm.") so the two strings cannot drift.
- **A part-period charge SAYS it is one.** The kiosk pins `prorate_to_anchor`,
  so a mid-cycle joiner's due-today and per-cycle figures differ; the review
  explains that in one receipt-shaped line
  (`KioskProrationNote`) — "Today is a part-period charge — it covers you up to
  1 February 2026. The full amount starts then." It renders **only** when the
  preview's own lines carry `is_proration`, never because two figures happen to
  differ, and the date is the preview's `next_payment_date` rather than
  anything derived here. `KioskSignupState.chargedProrated` /
  `prorationUntil` are those two reads, beside `chargedTwiceToday`, which they
  compose with: one is about what today's amount BUYS, the other about how many
  lines the statement shows.
- **The start call, and only the start call, runs on a ~90s `receiveTimeout`**
  (`kKioskSignupStartTimeout`, passed through `MemberRepository.startMemberships`
  to `ApiClient.post`). A Connect charge legitimately takes 10–60s and the
  shared 30s default would false-fail a charge that actually went through.
- **A waiver read/sign failure is an INLINE retry, never a stop.** By that point
  a member row and a Stripe customer exist; ending the signup over one flaky
  call orphans them for nothing. A **preview** failure is different — it is a
  retryable stop, because a review with no figures on it is a blank screen. **A
  request that cannot be ASSEMBLED takes the same stop**, for the same reason: a
  bare return leaves the review on a spinner that never resolves, and a kiosk
  screen with no countdown and no way on is fatal. That stop is scoped to the
  review step, the only step that renders a preview and the only place its "Try
  again" returns to (a retry's re-price rides alongside a live charge — §11.6).
- **No money-path return is ever silent.** `pay()` with no card, or with a
  request that will not assemble, ends on the `paymentFailed` stop rather than
  returning — nothing left the device, so "nothing was charged" is exactly true,
  and there is a 15-second countdown home. A quiet return there parked the iPad:
  `retrySameCard` cancels the popup's own return countdown before it calls
  `pay()`, and the decline screen deliberately has no escape (§2).
- **Signed stays signed.** Signatures append to `KioskSignupState.signedWaivers`
  and are keyed on the MEMBER (`signedWaiverIdsFor(memberId)`); walking Back
  skips what that person already signed and nothing un-signs it. Back out of
  the card lands on the PLAN, not the waiver behind it, for exactly that reason. A
  waiver signed BEFORE this signup is skipped too, by a different mechanism —
  see §11.4a.
- **Every new waiver body CLEARS the signature inputs — a legal invariant.** The
  signer-name field and the consent tick are wiped the moment a new waiver body
  loads (`KioskWaiverStep` / `KioskPayerWaiverStep`'s `BlocConsumer.listener`, on
  every `waiver` / `payerAuthWaiver` change; every load path emits `null` first,
  so it fires on each new document). A signature must be a fresh, deliberate act:
  a name carried over from a previous waiver would let someone "sign" a document
  they never actually typed their name on — the SAME person's next waiver, a
  republished version, or (worst, on a shared iPad) a DIFFERENT person's. It
  clears **every time, no exceptions** — the earlier "the typed name persists for
  the same person" behaviour is overruled (founder ruling). Guarded by
  `test/features/kiosk/presentation/kiosk_signup_waiver_clear_test.dart`.

### 11.4a The waiver run asks only for what is actually OWED

**A member is never asked to re-sign a waiver the gym already holds a compliant
signature for.** An existing member self-serving here has history, and asking
them to sign again what they signed last year is the bug this rule exists to
prevent.

- **The signal is the SERVER's verdict, `meets_floor`.**
  `MembershipsRepository.listMemberWaiverStatus` reads
  `GET /api/v1/waivers/signatures/by-member/{member_id}?gym_id=` into
  `MemberWaiverStatus`, whose `meetsFloor` says that member's latest signature
  sits at a version at or above the waiver's re-sign FLOOR
  (`MAX(version_number) FILTER (WHERE requires_resign)`, defaulting to 1). That
  is the SAME compliance rule the 422 purchase gate and the check-in gate
  apply. **The kiosk never re-derives the floor** — one rule, one owner. There
  is no kiosk-specific endpoint and no backend change behind this.
- **The skip predicate is exactly `signed && meetsFloor`, per (member, waiver).**
  Nothing else skips anything.
- **It is read at the PLANS step** — `_loadPriorWaiverStatus`, fired beside
  `_loadPlanEligibility` from `continueToPlans` — because the waiver run is two
  taps away (pick a plan, Continue), so the answer is in hand before the first
  waiver is drawn and the step never briefly shows one it is about to skip.
- **Both reads gather the roster CONCURRENTLY, and each per-member read owns its
  own failure.** The two functions run side by side (two `unawaited` calls) and
  each fans out over its members with `Future.wait`, so a family of four costs one
  round trip per read rather than four — on a path that is two taps from the
  waiver run. The concurrency is only safe because the per-member helpers
  (`_readPlanHistory` / `_readSatisfiedWaivers`) **never throw**: `Future.wait`
  propagates the FIRST error and cancels nothing, so an uncaught failure would
  discard sibling answers that had already landed and silently FLIP an asymmetry —
  one member's timeout re-asking a whole family for signatures the gym already
  holds, or a failed waiver read wiping a held-plan block. Each helper returns a
  per-member record instead: the plan side returns the fail-OPEN answer itself
  (no trial, nothing held), the waiver side returns `satisfied: null`, whose
  NULLNESS is the fail-CLOSED signal and must never be written to the cache as an
  empty set. `bloc/kiosk_signup_waiver_skip_test.dart` holds all of it — the
  in-flight PEAK (2 members = 2 open calls per read), each posture surviving the
  sibling's throw, and one member's failure never discarding another's answers.
- **Only for a person the kiosk did not create**: `wasExisting` + a known
  `memberId`, exactly like the eligibility read. Somebody registered during this
  signup has no signature history by construction, so no request is spent.
  Answers are cached per member id for the flow (`_waiverStatusChecked` /
  `_priorSatisfiedWaiverIds`) and a FAILED read counts as asked.
- **The cache is a private cubit field keyed by member id, never state** (the
  shape `_planChecked` and `_sentAttempts` use). It has no render path, so a
  cross-person leak is unrepresentable; and because it never emits, an answer
  landing late can never re-shape a queue the member is already looking at.
- **It FAILS CLOSED — the exact inverse of the two plan-block reads, and that
  inversion is the whole design.** `_loadPlanEligibility` fails OPEN because
  refusing a paying customer is worse than a rare second trial. Waivers invert
  the cost: a needless signature costs the member twenty seconds, a MISSING one
  voids the gym's legal protection. So every shade of "we don't know" collapses
  to **ask**:
  - a read that threw → no cache entry → nothing skipped for that person;
  - a waiver **ABSENT** from the response → asked. This is real, not
    theoretical: the query's result set is `required ∪ ever-signed`, where
    `required` comes from the member's **CURRENT** memberships' plans — so a
    waiver belonging to the plan they are about to BUY, and never signed, is not
    in the response at all. Absence must never read as "no need to sign";
  - `signed` with `meetsFloor` false → asked (that IS the re-sign case);
  - a missing `meets_floor` → parses as false (`@JsonKey(defaultValue: false)`)
    → asked.
- **The 422 purchase gate stays the authoritative backstop, and it OUTRANKS the
  skip.** Anything `state.waiverGate` names for a person is folded into their
  queue and can never be dropped by a prior-signature read — if the server says
  unsigned, the server wins. That backstop is what makes a client-side skip safe
  at all.
- **The queue's LENGTH is honest.** A skipped waiver is dropped from
  `waiverQueue` rather than stepped over, so the subtitle's "waiver 2 of 3"
  counts the signatures the member is about to give — telling somebody
  "waiver 1 of 3" and then showing them one is worse than a correct "1 of 1". A
  waiver signed DURING this signup stays in the queue and the index moves past
  it instead (`_firstUnsigned` over `signedWaiverIdsFor`), so the count cannot
  shrink under their hands mid-run. `_enterLiability` builds that one filtered
  list, so the index maths, `_advanceWaiver`, Back-then-forward and the
  per-person group walk agree by construction.
- **The payer-auth link is untouched.** It is a different waiver type
  (`payer_auth`), signed as part of `PUT /members/{payee}/link` and gated on
  `KioskSignupPerson.linked` — no part of it routes through this skip.

Guarded by `test/features/kiosk/bloc/kiosk_signup_waiver_skip_test.dart`.

### 11.5 The GROUP's own money rules

- **Link before start, structurally.** The start call never links, so
  `_buildStartRequest` returns null unless `KioskSignupState.everyPayeeLinked`.
  That one guard covers the preview and the charge alike: a roster with an
  unauthorized payee cannot assemble a request at all, let alone send one.
  **Its scope is the payees the request CARRIES** (`isBeingCharged`), which is
  the backend's own scope verbatim — `_check_links`
  (`memberships_start_validation.py`) reads `request.memberships`' member ids
  minus the payer. Demanding a link from somebody who is not in the cart both
  dead-ends the whole family on an unassemblable request AND means asking them
  to authorize a payer for a membership they are not buying.
- **`PUT /members/{payee}/link` signs and links in ONE call** and commits
  immediately — there is no group transaction and no rollback. A 409 means the
  gym republished the payer-auth agreement, so the body reloads and the payer
  re-signs; nothing is recorded against text nobody saw.
- **Waivers are grouped by PERSON, not by document** (ruling 9): every payee
  **who is getting a membership** first (their payer-auth, then their own
  liability waivers), the payer's own
  liability waiver last. `waiverPersonQueue` / `waiverPersonIndex` drive it, and
  `payerAuthPending` is what splits the one `waivers` step between
  `KioskPayerWaiverStep` and `KioskWaiverStep`. The iPad changes hands once per
  person.
  **Somebody who Skipped (§3) is not walked at all** — the queue reads the same
  `isBeingCharged` predicate `everyPayeeLinked` does, so the run collects
  exactly the links the start demands and the two cannot disagree. Asking a
  skipped person for a payer authorization is consent taken from the wrong
  person for a purchase that is not happening; the payer's own rung has always
  worked this way (`training || gated`) and the payees now match it. Anything a
  server gate named stays in the queue either way — the gate is authoritative.
- **A signature is keyed on (member, waiver).** Two children on the same plan
  each sign that plan's waiver; keying on the waiver id alone would skip the
  second child and hand the backend an unsigned member at the start.
- **The membership check decides who is in the CART, per person.**
  `payer_member_id` is identity-only server-side, so an unticked payer pays for
  others with no membership of their own. `anyoneTraining` is the empty-cart
  guard: a roster with nobody ticked would send `memberships: []` and take a
  400, so it cannot leave the People step — see §3 for the control and the
  legible block.
- **A retry carries ONLY what did not get CREATED, and an empty retry set sends
  NOTHING.** `_startItems` filters through
  `KioskSignupState.isBeingCharged`, over
  `KioskSignupState.retryMemberIds` — every landed item that is not `created`.
  **The null-vs-empty distinction in that getter IS the defence:** `null` means
  nothing has landed (a first attempt, send the cart), an EMPTY set means the
  landed start left nothing to re-send. Collapsing them — the shipped bug, an
  `isNotEmpty`-guarded filter over `failedItems` — re-sent the WHOLE cart for a
  `[created, unknown]` partial (no row is `failed` there) under the fresh
  idempotency key every retry mints, which the backend's
  `ON CONFLICT (idempotency_key)` guard cannot dedupe: a second real charge on a
  membership that had already started. Keying on "not created" rather than on
  `failed` is the other half — `failedItems` is the DISPLAY set the receipt
  marks, never the retry set. Nothing already created is re-charged, and no
  member, signature or link is ever re-executed. The retry mints a new key (and
  `retryCard` a new `pm_`).
- **`retrySameCard` cannot fire from an all-created state at all.** Its gate is
  `KioskSignupState.canRetryStart` (the retry set is non-empty), not the step —
  the all-created receipt is `results` too, and the step check alone let it
  re-post the entire cart from a screen where every membership had started.
- **Roster removal is offered only while it is FREE.** There is no unlink call,
  so `canRemovePerson` goes false the moment that person is linked or has
  signed anything. A person created but never linked simply drops out of the
  cart; their member shell is harmless and surfaces in the staff "Incomplete"
  list.
- **The lobby-screen privacy rules.** A person matched to an EXISTING member
  **skips the per-person details step entirely**: the kiosk can neither show
  their stored details on a shared screen nor overwrite a record it does not
  own, so a blank-field pass would be a form that can only ever ask for what
  the gym already has. They land straight back on the roster, their row carries
  no Edit affordance, and `editPersonDetails` refuses them even if a call is
  routed in. (`KioskSignupOptionalStep` still seeds a `wasExisting` person's
  form blank; that path is unreachable by design and the guard stays because it
  is the structural reason a lobby iPad can never print stored details.) The
  match card shows a full name and a MASKED email (`kioskMaskedEmail`), never a
  phone, photo or membership status. The name search is avatar-free for the
  same reason the home's is.
- **Both duplicates end in an offer, through DIFFERENT screens.** A PAYEE 409
  lands on the roster's "is this her?" match; a PAYER 409 lands on "is this
  you?", confirming their own account back to them. Both reuse the existing
  account rather than making a second one, and the payer's "no" is what reaches
  the terminal duplicate stop (§3).
  `test/features/kiosk/bloc/kiosk_signup_group_test.dart` holds the payee side;
  `bloc/kiosk_signup_payer_test.dart` holds the payer side.
- **A partial failure is structurally group-only** (§11.2), so the results
  receipt's partial branch is a group surface — and the retry it offers carries
  only the un-created items, so nothing already created is re-charged (§11.6).
- **The group review MARKS an already-started person; it never drops their row.**
  "Try another card" off a partial re-enters the review, and
  `KioskReviewGroupPanel` lists the whole roster on purpose (the same rule that
  keeps a non-training payer on it: removing a row is indistinguishable from
  forgetting them). So `KioskSignupState.alreadyStarted(person)` — a landed
  response plus `!isBeingCharged`, i.e. the inverse face of the ONE
  "who does the next request carry" predicate — puts a **`STARTED`** eyebrow on
  their name line, beside (never instead of) the existing `PAYING` / `MEMBER` /
  `NEW` role label: the payer can easily be the person who already started, and
  the payer marker is the fact that explains the whole screen. The word is the
  receipt's own ("The ones marked Started are paid for"), so it re-uses a
  vocabulary the member read one screen earlier. Two things it deliberately is
  not: `unknown` rows are **not** marked (they sit in `retryMemberIds` because the
  backend confirmed nothing, so "started" would be a guess), and a non-training
  person is **not** marked (they are not in any cart — the landed-response check
  is what separates "not charged because they already paid" from "not charged at
  all").
- **A swapped payer keeps everyone's seat.** A CRM pick inserts at index 0 and
  shifts every index by one (`activePersonIndex` included); a roster pick swaps
  positions 0 and k and shifts nothing. Either way the person who started the
  signup stays on the roster — only the payer role moves — and the new payer
  defaults to getting a membership like everybody else. `everyPayeeLinked` then
  covers the demoted signer, so the new payer must authorize them before a
  request can assemble.
- **`canSwitchPayer` closes only when a link or a signature pins the payer.**
  It goes false once anything is `linked` or signed (there is no unlink call, so
  a later swap would leave the roster authorized to a payer who no longer pays).
  Before that, switching is **freely repeatable** — the payer can be reassigned
  as many times as needed, because seating a payer writes nothing a later change
  could strand: whoever it displaces is left as an ordinary unlinked roster
  payee (an adopted `wasExisting` outsider included — demotion doesn't remove
  them, it just makes them a payee like any other). `canSwitchPayer` is
  `hasPayer && canAssignPayer`; `canAssignPayer` is the shared seat gate
  (nothing linked, nothing signed) that also permits CHOOSING the first payer in
  the no-payer state. `bloc/kiosk_signup_payer_test.dart` holds the "repeated
  swaps stay open until a payee is linked" guard.
- **The roster row's trailing controls are EDIT and a TRASH that asks.** What
  is or is not on file is nobody's business at a glance on a shared iPad, and
  "None yet" beside a name only ever read as a nag; Edit reuses
  `editPersonDetails` rather than adding a parallel path, and is absent for
  `wasExisting` people per the rule above. Both ride the one `KioskRowAction`,
  so the two cannot drift apart in size. **The trash is on the PAYER's row too**
  (group-only, while nothing has committed against them); deleting the payer
  clears the payer and asks who pays next (§3). See §3 for the membership check,
  the remove confirmation, and the no-payer state.

### 11.6 The per-person results receipt

**`KioskSignupStep.results` is the LEDGER, and the welcome screen stays the
celebration.** The receipt answers "who got what, and did it start" — factual,
with per-row square marks and no green confirmation disc. The welcome screen keeps
`_Greeting`'s disc and the composed `get_app/` set, unchanged: two celebrations
for one event teaches neither of them.

It is entered only with a LANDED response in hand — `paying` owns in flight — and
it draws two branches off one panel (§11.2 decides which):

| branch | title / subtitle | actions | card chip |
| --- | --- | --- | --- |
| every item created | `You're all set` · `Your membership started today.` solo, `Every membership below started today.` in a group | one `Next` → `welcome` | no — the money already moved, so it is noise |
| **partial** | `Some of these didn't go through` · `Have a look — you can try the rest on the same card.` | the decline popup's THREE, in its order and wired to its methods: **Retry the rest** (`retrySameCard`), **Try another card** (`retryCard`), then **Next** (`nextFromResults` — outline tier, see below), then **Get help at the desk** (`getHelpAtDesk`, always the bottom rung) | yes — which card was used is the fact a member wants before retrying |

Rules the screen holds:

- **The rail lights the `Pay` rung** and the templates stay 6 solo / 7 group.
  The receipt IS the outcome of paying, so it joins that arm rather than adding a
  rung. No identity strip: it is about the signup as a whole.
- **Row order is the ROSTER's order** (payer first), not the response's, so the
  receipt reads in the same order as the review the member just approved. Each row
  is `<Person> · <Plan>`; an item whose member is not on the roster (unreachable
  — `_startItems` builds from the roster) is appended last and degrades to the
  **plan name alone**, never a stand-in human name (§9).
- **Three sub-lines, one per status**: `created` → "Started today"; `failed` →
  "Not started — nothing was charged for this one." (true by construction — the
  failure granularity is the charge group, and a failed group's invoice did not
  charge); `unknown` → "We couldn't confirm this one — the desk can check it for
  you.", which claims nothing about money in either direction.
- **No red, and no raw `item.error`.** Every kiosk failure surface is warm
  `yellowDark` / `okYellow` — nothing is broken and nobody did anything wrong, and
  a red row on a lobby iPad reads as a verdict on the person standing at it. The
  backend's error string is Stripe or internal prose; the row states the
  CONSEQUENCE in the kiosk's own words instead. There is also no right-hand status
  word: the mark and the sub-line already carry the outcome.
- **No escape, on either branch.** Money has moved; there is nothing to start
  over. So the foot is **`KioskResultsFoot`**, built from
  `KioskWelcomeScreen._Foot`'s shape (hairline → the 60s `KioskReturnTimer` →
  centred actions) and deliberately **not** `KioskFlowFoot`, whose left gutter is
  the ghost escape by construction.
- **A partial's retry is still money-safe.** `retrySameCard` is gated on
  `canRetryStart` — a landed start with something un-created — and then on the
  step (`declined || results`); `_startItems` re-sends only the un-created items
  and mints a NEW idempotency key, so nothing already created is re-charged and
  no member, signature or link is re-executed (§11.5).
- **A partial's retry also RE-PRICES.** `state.preview` prices the whole cart,
  and the paying screen states that figure as *what is being taken* — so
  `retrySameCard` clears it and re-runs `_loadPreview()` against the same
  filtered items the charge carries (what `retryCard` gets for free by passing
  back through the card step). Two consequences that are easy to undo: the
  preview must be fired BEFORE `pay()` (which clears `startResult`, the thing
  that narrows both requests), and a preview failure there is SILENT — the
  retryable stop belongs to the review step alone, or a failed read would yank
  the member off a landed receipt mid-charge. `KioskPayingScreen` renders the
  amount only while a preview stands behind it, because `dueTodayMinorUnits`
  falls back to `0` and "$0.00 is being taken" is a worse lie than saying
  nothing.
- **A retry's response is MERGED into the one it retried**
  (`_mergeStartResults`), newer outcome replacing older for the same
  (member, plan). A retry names only the previously un-created items, so without
  the merge a partial-then-successful retry would print a one-row receipt headed
  "every membership below started today" while omitting the row an earlier attempt
  created. Because a retry carries EVERY un-created item, `retryMemberIds` over
  the merge is identical to the latest response's own un-created set — the retry
  set cannot go stale, and nothing already created can re-enter it.
- **A partial gets a working `Next`, and it is ADDITIONAL to the retry ladder**
  (founder ruling, verbatim: *"We should add a next on partial its fine, we can
  add text to say ask the frontdesk to fix it or som and next goes to get mobile
  app page."*). The earlier rule — no fourth action, on the grounds that
  "continue without them" is a desk decision — is **superseded**: with the retry
  ladder alone, a member who did not want to retry was held on the receipt until
  the 60-second expiry `abandon()`ed the flow, and the people whose memberships
  DID start never reached the app push they were standing there for. So the
  all-created branch's `Next` also appears on the partial, one tier down
  (`KioskOutlineButton`, because retrying is still the loudest thing to do), and
  it routes to exactly the same `welcome`.
  - **`nextFromResults` must NOT be gated on `allCreated`.** Adding that guard is
    precisely the behaviour this ruling reversed. It is safe ungated because
    advancing charges nothing: the money-safety gate lives on the RETRY
    (`canRetryStart`), which is false on an all-created receipt.
  - **The screen says where the rest goes**, in the partial's existing
    `KioskInlineNotice`: *"The ones marked Started are paid for. Trying again only
    charges for the ones that didn't go through. Or tap Next and ask the front
    desk to finish the rest."* Without that third sentence a bare "Next" beside
    "Retry the rest" leaves the failed rows' fate to be guessed at.
  - **The welcome screen must not then read as "you're all set".** Its greeting is
    an unconditional green check over "Welcome to {gym}, {name}!", so
    `KioskSignupState.welcomeAfterPartial` (set by `_enterWelcome(afterPartial:)`
    from the branch that routed there — welcome CLEARS `startResult`, so nothing
    else still knows) renders one `KioskInlineNotice` under it: *"Some memberships
    didn't go through — ask the front desk to finish them."* The greeting itself is
    unchanged and stays true; no second celebration idiom, no restyled disc. Every
    other route into welcome (all-created, the 409 replay, an empty itemisation)
    has nothing outstanding and carries no notice — a warning on a clean signup is
    the mirror-image lie.
  - **It is also the flow-count release** for a partial receipt, which
    deliberately does not release on entry (§11.3).

---

## Key files

**CRM — the kiosk feature** (`CRM/lib/features/kiosk/`):

- `bloc/kiosk_session_cubit.dart` + `kiosk_session_state.dart` — the security
  runway (§1), `beginFlow`/`endFlow` (§2).
- `bloc/kiosk_flow_cubit.dart` + `kiosk_flow_state.dart` — the check-in lane,
  the two class lists (§5), the four catalogues (§6), the timers (§7). All the
  tunable constants live at the top of the cubit file.
- `bloc/kiosk_signup_cubit.dart` + `kiosk_signup_state.dart` — the SIGNUP lane
  (§10, §11): the `KioskSignupStep` spine, the roster (`KioskSignupPerson`), the
  `committedSteps` marker that turns a second Continue into a PUT instead of a
  second create, the waiver queue + `signedWaivers`, the front door
  (`startAsNewMember` / `startAsExistingMember`) and the three routes to a
  seated payer (`_offerPayerMatch`, `_offerIdentifiedMatch`,
  `confirmPayerMatch` / `declinePayerMatch` with its `payerMatchFromIdentify`
  fork, `openPayerPick` / `pickPayerRow` / `pickPayerFromRoster` over the ONE
  `_seatPayer`, `canSwitchPayer`), the TWO plan-block rules
  (`_loadPlanEligibility` → `KioskSignupPerson.hadTrial` +
  `heldRecurringPlanIds`; `KioskSignupState.planBlockReason` /
  `planBlockReasonFor` / `heldPlanNames`; `selectPlan`'s
  explain-don't-select branch; `_clearBlockedPick`; `_openPlanBlock` /
  `dismissPlanBlock` / `planBlockHelp`), the plan step's group-only skip
  (`skipPlanForPerson` / `_advancePlanPerson`), the waiver run's
  already-signed skip (`_loadPriorWaiverStatus` → `_readSatisfiedWaivers` →
  `_priorSatisfiedWaiverIds` /
  `_satisfiedWaiverIdsFor`, folded into `_enterLiability`'s queue — §11.4a), the
  two never-throwing per-member readers behind those gathers
  (`_readPlanHistory` / `_readSatisfiedWaivers`, over the `_KioskPlanHistory` /
  `_KioskWaiverHistory` records that carry each posture in the TYPE — §11.4a), the
  money path
  (`_buildStartRequest` / `_startItems` over
  `KioskSignupState.isBeingCharged` → `retryMemberIds` / `canRetryStart` —
  the ONE "who does the next request carry" predicate, shared with
  `everyPayeeLinked`, the waiver run, `kiosk_money_labels` and (inverted)
  `alreadyStarted`
  (§11.5) — / `pay`'s three-way split / `_enterResults` /
  `_mergeStartResults` / `nextFromResults` (live on BOTH branches, §11.6) /
  `_onDeclined` /
  `retrySameCard` (same card, new key, re-priced) / `retryCard`
  (new card) / `_enterWelcome(afterPartial:)`, the `_sentAttempts` latch,
  `kKioskSignupStartTimeout`), the blocking surfaces' shared return countdown
  (`_startPopupCountdown`, `kKioskSignupPopupHold`), the
  `KioskSignupStopReason`s and their `isRetryable` split, and the lane's own
  begin/endFlow latch + idle guard.
- `presentation/screens/kiosk_signup_screen.dart` — provides that cubit (so its
  lifetime is the flow's), hosts the signup's activity listener, and routes
  `abandoned` → `goHome()`.
  `presentation/widgets/signup/` — the signup chrome (rail, three-slot foot,
  field box, consent check, DOB wheel, stop screen, abandon confirm) and the
  built steps: `kiosk_plan_pick_step` + `kiosk_plan_card` + `kiosk_plan_labels`
  (a COPY of the CRM's `planAllowanceLabel` vocabulary, never an import) +
  `kiosk_plan_picked_banner` (the "YOU'VE PICKED" confirmation, §8.1a),
  `kiosk_waiver_step` + `kiosk_waiver_doc_panel` (read-only
  `WaiverMarkdownEditor`) + `kiosk_sign_panel` + `kiosk_waiver_status`,
  `kiosk_inline_notice` (the lane's ONE warm "important, not your fault, not a
  dead end" strip — the waiver notices, the picker's redirect, the card step's
  replacement notice, the plan step's already-held-membership notice, and the
  partial receipt's "the ones marked Started are paid for"),
  `kiosk_entry_choice_step` + `kiosk_identify_step` (the front door),
  `kiosk_plan_block` (the ONE blocked-plan popup, over
  `presentation/kiosk_plan_block_copy.dart`'s reason → title / body / glyph /
  card-tag map),
  `kiosk_card_step` + `kiosk_secure_strip` + `kiosk_card_facts` (wrapping the
  shared `CardFieldBox`), `kiosk_review_step` + `kiosk_review_side_panel` +
  `kiosk_money_panel` + `kiosk_buy_row` + `kiosk_card_chip` +
  `kiosk_two_charges_note` (the ONE two-charges sentence, shared with the
  receipt),
  `kiosk_paying_screen`, `kiosk_results_screen` + `kiosk_result_row` +
  `kiosk_results_foot` (the per-person receipt, §11.6),
  `kiosk_declined_screen`, and `kiosk_welcome_screen`
  (which COMPOSES the shipped `get_app/` set off the flow cubit's warmed
  catalogues — zero fetches, plus the `welcomeAfterPartial` front-desk notice,
  §11.6), plus the GROUP half: `kiosk_people_step` +
  `kiosk_roster_row` + `kiosk_person_adder`,
  `kiosk_match_step` + `kiosk_match_card` + `kiosk_match_search`,
  `kiosk_payer_waiver_step`, `kiosk_review_group_panel` + `kiosk_person_block`
  (which marks an already-started person, §11.5),
  and `kiosk_money_labels` (the by-person attribution of a preview line, via
  its `stripe_price_id`); the payer gate's `kiosk_payer_match_step` +
  `kiosk_payer_pick_step` over the shared `kiosk_name_row`; the roster's
  `kiosk_row_action` (Edit + trash) and `kiosk_remove_confirm`; the pinned
  `kiosk_who_for`; and `kiosk_proration_note` (the part-period line, §11.4).
  `presentation/kiosk_signup_stop_copy.dart` — the ONE map from a stop reason to
  member copy, mirroring `kiosk_blocked_copy.dart`.
  `presentation/kiosk_name_format.dart` — `kioskFirstName` + `kioskMaskedEmail`,
  the two display transforms the kiosk shares.
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

- `GET /api/v1/members/{member_id}/billing` — the billing detail, consumed via
  `MemberRepository.getMemberDetail`. The kiosk reads it for exactly TWO facts —
  the one-trial rule's `memberships.any((m) => m.planType == 'trial')` and the
  held-recurring plan ids (`planType == 'recurring'` at
  `{active, frozen, overdue}` — this endpoint returns the CRM DISPLAY status, so
  `overdue` here is a raw `active`/`frozen` row in the guard's own view, §3) —
  and renders/logs/persists nothing else from it (§3).
- `FastApiBackend/src/memberships/sql/member_memberships_check_existing.sql` —
  the duplicate-recurring conflict the kiosk's already-on-plan block mirrors
  verbatim. It runs on the PREVIEW as well as the start
  (`MemberMembershipsStartValidation.validate`, called by both
  `memberships_start_preview.py` and `memberships_start.py`), which is why an
  unblocked card dead-ends on a retryable stop (§3).
- `FastApiBackend/src/checkin/service/checkin_member_gate.py` — the `is_member`
  split; `schema/checkin_schema.py` — `CheckinWarning`, `CheckinRequest`,
  `CheckinResponse` (incl. `class_streak_weeks` + `current_week_days`).
- `FastApiBackend/src/checkin/checkin_exceptions.py` — `CheckinErrorCode`, the
  public code contract.

**Specs for unbuilt phases (repo root):** `PHASE_G_QR_PLAN.md` (G),
`APP_DOWNLOAD_PAGE_MOCKUP.html`. (The D+E signup mockup was removed once the
flow shipped.)

**Tests:** `CRM/test/features/kiosk/` — `kiosk_forbidden_imports_test.dart`
(the fresh-card law in CI, §3), `bloc/kiosk_session_cubit_test.dart`
(the runway + the SEC-1/2/3 seams), `bloc/kiosk_flow_cubit_test.dart`,
`bloc/kiosk_signup_cubit_test.dart` (the signup lane's flow-count discipline,
the one-call create, ruling 11's PUT-not-create, the stops, the idle guard),
`bloc/kiosk_signup_money_test.dart` (the §11 money path: double-tap Pay = ONE
repository call, the sent latch, 409-as-success, the THREE-way start split —
all-created → `results` releasing the flow exactly once and `Next` → `welcome`,
all-failed → `declined` holding it — the receipt's own 60s countdown, 422 →
waivers, 500 → "nothing charged", the uncapped no-wait decline model — Retry
re-sends the SAME card with a NEW key while "Try another card" re-enters, a
double-tap Retry is one charge, and neither re-creates/re-signs anything — the
two retryable stops, Back out of the review handing the card step a genuinely
EMPTY field (the `cardAttempt` bump, §3), the request builder's
empty price-reduction fields + `paidWithCash: false` + `set_default`, and the
due-today / two-charges arithmetic),
`bloc/kiosk_signup_group_test.dart` (the §11.5 group rules: the payee 409
offer, adopt-vs-recreate, link-before-start both ways — including that neither
dead end is SILENT (an unassemblable preview and an unassemblable Pay each land
on a stop with a countdown) — the per-training-person
cart, the 207 partial — which lands on `results`, NOT the decline popup, and
holds the flow count — the **un-created-items-only retry** and its three
regression guards (a `[created, unknown]` partial re-sends ONLY the unconfirmed
row, an ALL-CREATED receipt has nothing to retry and its clock is left alone,
and a retry RE-PRICES against the same filtered items), the waiver run asking
consent only of the people being charged (a SKIPPED payee is never asked to
authorize the payer and no longer blocks the start), roster removal, the
empty-cart guard, the plan step's group-only "Skip" control including
skip-everybody → People, the search
debounce + sequence guard, and the per-member signature keying),
`bloc/kiosk_signup_payer_test.dart` (the §3 seat rules: the entry fork, the
identify search and its confirm-first tap, the duplicate 409 offer and where
each "no" goes, the picker's roster-redirect — including the person at index 0
once the payer has been DELETED, who is a real candidate and gets the redirect
rather than a dropped tap — adoption that never creates a
member, the link-before-charge invariant after a payer swap, `canSwitchPayer`,
and the existing-member skip / new-member edit round trip),
`bloc/kiosk_signup_trial_test.dart` (the §3 one-trial rule: any prior trial
closes every trial, a cancelled trial still counts, a member created here is
never asked, the read FAILS OPEN, a blocked card explains without selecting,
and the popup's countdown returns home releasing the flow exactly once),
`bloc/kiosk_signup_waiver_skip_test.dart` (the §11.4a waiver skip: a
`meets_floor` signature is not asked for again and the QUEUE COUNT follows, an
all-compliant person is skipped entirely, Back-then-forward re-derives the same
queue off ONE read, and the four fail-CLOSED shades — signed below the floor, a
waiver ABSENT from the response, an empty response, a THROWN read — plus the 422
gate item that is never skipped, the member created here who is never asked, and
the group walk where one person's compliance never covers the other's),
`bloc/kiosk_signup_plan_block_test.dart` (the §3 already-on-plan rule: the
`recurring` + `{active, frozen, overdue}` scope mirroring the guard — a DIFFERENT
recurring plan stays selectable (the over-block guard), `frozen` blocks without
ever saying "frozen", **`overdue` DOES block** (it masks a raw `active` the guard
rejects) while a held one-time/trial pack blocks nothing, the read
FAILS OPEN, the popup NAMES the plan while the trial popup does not, the desk
handoff's own stop reason, a late answer clearing a pick, and the group leak
guard — advancing the active person flips BOTH the notice and the blocked set),
and the
presentation guards `kiosk_type_ramp_test.dart`, `kiosk_group_steps_test.dart`
(the roster / match / details screens compose at 1180×820 with the email
masked, Edit only for people this signup created),
`kiosk_signup_chrome_test.dart` (§8.1a: the pinned identity survives a scroll,
a group names every turn, the card step names the PAYER and not the active
person, the waiver box fills the fold, the GROUP rail SCALES rather than clips at
either fold, the §11.4 proration line renders only on
a prorated preview, and the §11.4 committing CTA — trial vs membership, the
`$0` collapse, and no foot overflow at 1180×820 or 1024×700 with the longest
label),
`kiosk_signup_surfaces_test.dart` (the founder-called-out surfaces at the real
fold: the front door's two ways in, the payer picker's affordant rows, the
deletable payer and its legible block, the plan pick's confirmation + BOTH block
labels with the held-membership notice + the over-block guard, the decline
popup's three live actions over its countdown **and its account-honest body**
(§11.4), and §11.6's two receipt branches — five rows, one `Next` vs the retry
ladder PLUS a live `Next` and the front-desk line, both at 1180×820 and
1024×700 with no overflow),
`kiosk_review_panels_test.dart` (the review's left half: the solo "YOU" row's
MASKED address and its dropped-when-empty line, and the group panel's `STARTED`
mark — present for an already-created person, absent before a start lands, never
on a non-training payer),
`kiosk_welcome_partial_test.dart` (the welcome's front-desk notice on a partial
arrival, and its absence on every other route in),
`kiosk_flow_rail_index_test.dart` (every `KioskSignupStep`'s rung, by
name — a miscount there is otherwise SILENT),
`kiosk_get_app_modal_test.dart`
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
