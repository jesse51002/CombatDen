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
  hazard, the fresh-card law and the structural no-discounts rule, the TWO
  rejection shapes (a 200 with `skip_reason` vs a thrown error carrying a stable
  `code`), the TWO separate class lists (check-in window vs the forward-looking
  showcase), the four gym-wide catalogues warmed once at entry, the four
  independent timers, the kiosk type ramp / AA contrast / fixed QR polarity
  design laws, the PINNED per-step identity band, the real-vs-illustrative
  data rule, and the built SOLO + GROUP self-serve **signup** lane (its own
  cubit, the double-charge defences, the fail-closed payer gate and its two
  entry points, the uncapped, no-wait decline model with same-card + new-card
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
  "kiosk signup", "duplicate payer", "payment-method-status", "someone else is
  paying", "decline retry", "retry same card", or "Incomplete tab".
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
member instead taps *"New here? Sign up"* and walks a self-serve **signup**
spine — details, plan, waiver, card, review, pay, welcome (§10, §11), solo or
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
`welcome` or `stop`, on `abandon()`, and in `close()`; `declined` does **not**
release (the member is still there and can retry) and `paying` **never** does.
The latch makes the pair exactly-once however many of those run.

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

**The kiosk never charges a PRE-EXISTING card.** Every card it charges is one
entered during the current signup. That is the whole invariant, and everything
below is how it is held.

**Why it is the invariant and not "the payer must be new".** A recurring cart
sends `set_default: true` — a subscription can only bill the saved default —
so the card typed at the iPad **becomes that member's Stripe default**. If the
kiosk could seat a payer who already had a card, it would be attaching a
stranger's card to somebody's account, and the next front-desk "charge the card
on file" would bill the wrong person.

#### The gate: no attached payment method, or no

An **existing** member may be the payer **only if they have no payment method
attached at all**. They then still type a fresh card, which is the first one
that account has ever had. Any attached payment method → refuse and hand off to
the front desk.

`GET /api/v1/members/{member_id}/payment-method-status` → `{"has_payment_method":
bool}` is the read (`MemberRepository.getPaymentMethodStatus` →
`MemberPaymentMethodStatus`, whose `has_payment_method` is REQUIRED so a broken
body fails to parse rather than defaulting to `false`).

`KioskSignupCubit._payerEligibility` maps it to `KioskPayerEligibility`, and
**`eligible` is the only value that permits adoption**:

| verdict | means |
| --- | --- |
| `eligible` | the check answered, and there is no payment method |
| `hasPaymentMethod` | the check answered: there is one. Refuse. |
| `unknown` | the check did NOT answer — 404, 5xx, timeout, dropped connection, unparsable body. Refuse. |
| `alreadyInSignup` | decided locally before the check: the CRM search turned up somebody already on this roster. A **redirect**, not a rejection — they are listed above and pickable there — and it still stops the CRM path INSERTING a second entry, which would be two cart items for one person. |

> **FAIL CLOSED.** An indeterminate check is NOT eligible. A `false` inferred
> from a failure is a billing incident, so `_payerEligibility` catches
> everything and returns `unknown`, and every caller tests `!= eligible` rather
> than testing for a specific refusal.

#### The two entry points

**A — "Is this you?" on a payer duplicate.** `POST /members/` 409s because the
person standing there already has an account. The first match is put through
the gate: **eligible** → `KioskSignupStep.payerMatch`, a single confirm card
(`KioskPayerMatchStep` over the shipped `KioskMatchCard`, full name + the same
masked email `kiosk_name_format.dart`'s `kioskMaskedEmail` renders for a payee)
— they typed this exact name and email one screen ago, so confirming their own
account back to them leaks nothing. "Yes, that's me" adopts the id;
"No" and **every ineligible or unanswered check** land on the unchanged
terminal stop. A LIST of matches is still never rendered, and never a phone,
photo or membership status.

**B — the payer picker (`KioskSignupStep.payerPick`).** One screen serves two
situations. **Changing** who pays while a payer exists — a secondary-tier
affordance under the roster ("Change who is paying"), a change-of-ROLE action
whose label says so ("someone else is paying" announced a fact about a third
party, which is not what the button does). And **choosing** the first payer
after the previous one was DELETED — reached straight from the trash, and
re-openable from the People step's "Choose who's paying" affordance in the
no-payer state (below).

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

**The gate runs on whoever is picked, uniformly.** `_gateThenSeat` is the ONE
path a payer is ever seated by, and **nothing is special-cased for a person
this signup created** — not even on the reasoning that they obviously have no
card yet. It runs for BOTH a switch and a first-choice after a delete (gated on
`canAssignPayer`, which is true whenever nothing has committed the payer,
whether or not one currently exists), so **a payer chosen after the previous one
was deleted is seated through exactly this fail-closed gate — never a shortcut.**
One code path means one place the invariant lives and no branch a future change
could route around; the cost is one cheap call.

Two seatings, one gate:

- **CRM pick** (`_seatNewPayer`) — INSERTS them at the head; the person who
  started the signup keeps their seat as a payee and every index shifts by one.
- **Roster pick** (`_promoteRosterPayer`) — a straight SWAP of positions 0 and
  k, so every other index (and every signature, link and plan keyed on one) is
  untouched. The promoted person keeps their own membership choice and plan:
  they were signing up before and they still are.

Either way **only the payer role moves**, so the demoted person now needs the
payer-authorization waiver like any other payee — which `everyPayeeLinked`
enforces for free (see §11.5). Ineligible, or a failed check, is an **inline**
refusal (`kiosk_payer_refusal_copy.dart`), never a stop: they pick somebody
else or carry on paying themselves.

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
the duplicate check on their OWN half-finished account — and that account has
no payment method, so the gate passes and "Is this you?" simply picks the
thread up. The CRM's **Incomplete** tab on the members list is the staff-side
counterpart: it lists exactly these no-membership shells (a member who holds no
membership and pays for nobody else's —
`src/members/sql/crm_views/_member_incomplete.sql`), and each row's **Finish
signup** button opens that member's page straight into the CRM's own
start-membership wizard.

For a **recurring** plan the entered card IS kept (a subscription can only bill
the saved default, so `set_default` must be true); for **one_time / trial** it is
attach → pay → detach. The card copy branches on the plan for exactly that
reason — writing "only used for this signup" on a recurring plan would be a lie.

This is a **frontend guard** (accepted, given the supervised iPad + Guided
Access). Which means: it holds only as long as no kiosk screen imports a
payer/card-selection widget. Treat any such import as a defect.

#### The card surface, and naming the profile it lands on

`presentation/widgets/signup/kiosk_card_step.dart` is the ONE card surface on
the kiosk: it wraps the shared
`member_details/presentation/dialogs/card_field_box.dart` (a single-line
combined Stripe element — the mockup's four separate boxes are superseded),
tokenizes there with `Stripe.instance.createPaymentMethod`, and hands the cubit
only `pm.id` / `pm.card.brand` / `pm.card.last4`. It copies the tokenize CALL
from `one_time_card_dialog.dart` but **may never import it** — that module is on
the banned list below. `set_default` is decided by `cartHasRecurring`, never by
a picker.

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
iframe whose web platform view is CACHED across mounts, so a retry after a
decline would otherwise reuse the iframe still holding the declined number and
the member could not type a new card at all. The step keys `CardFieldBox`
(`fieldKey: ValueKey('kiosk-card-${state.cardAttempt}')`), and `retryCard()`
bumps `cardAttempt` — so returning to the card step mounts a brand-new, empty
iframe. `CardFieldBox` exposes an optional `fieldKey` (null for every non-kiosk
caller) for exactly this.

**The step names the PAYER, pinned, and reads them off the roster's payer seat
— never off `activePersonIndex`.** In a family the active person is usually a
child while the payer is the parent, so a name taken from the wrong place would
be confidently wrong about which profile a card attaches to, which is worse
than naming nobody. The `KioskWhoFor` strip carries it ("CARD FOR Marcus
Bell"), and `KioskCardFacts` attaches the same name to the promise — "Saved to
Marcus Bell's profile so the membership keeps running" / "Charged once, and not
saved to Marcus Bell's profile" — so *saved* and *to whom* are one sentence.
With no name to hand both degrade to the unattributed wording rather than to a
wrong one. The card step's subtitle is dropped in a group for the same reason:
`selectedPlan` reads the active person's plan, which at that point is whoever
signed last.

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
one of them: it can only ever seat somebody whose first card is the one about
to be typed. `bloc/kiosk_signup_payer_test.dart` is the other half of the
enforcement — the gate, both entry points, and the fail-closed pair.

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

## 7. Four clocks, and which one owns which screen

Four independent timers exist. Confusing them is a recurring source of bugs, so
name them precisely:

| clock | length | scope | on expiry |
| --- | --- | --- | --- |
| **Runway** (`KioskSessionCubit`) | 12h absolute, lockout at 11h45 | the whole session | sign out |
| **Flow-idle** (`kKioskIdleTimeout`) | 5 min, then a 30s visible countdown (`kKioskIdleCountdown`) | any *engaged* flow page | `goHome()` — abandons the draft |
| **Signup stop** (`kKioskSignupStopHold`) | 15s | a terminal signup stop only | abandon → `goHome()` |
| **Glance hold** (`kKioskGlanceHold`) | 10s, started at the LAST reveal beat | the glance only | `goHome()` |
| **App modal** (`kKioskAppModalTimeout`) | 60s | the modal overlay only | `goHome()` |

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
rule above true rather than aspirational. It renders a back-chevron, so putting
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

- **Phase D — the SOLO signup, end to end.** The kiosk's "New here? Sign up"
  calls `KioskFlowCubit.startSignup()` (the same `canStartFlow` gate
  `selectMember` uses; it does **not** `beginFlow`), which routes
  `KioskView.signup` to `KioskSignupScreen`. That screen provides its own
  **`KioskSignupCubit`** — a sibling of `KioskFlowCubit`, never more fields on
  it — so the cubit's lifetime IS the flow's lifetime and PII disposal is
  structural. Built: the `KioskSignupStep` spine + flat `KioskSignupState`,
  the details and extra-details steps, the ONE `createMember` call carrying
  both, **the plan pick, the waiver run, the card, the review, the pay lock,
  the decline and the welcome**, every front-desk stop, the lane's own 5-min
  idle guard, the abandon path, and the shared chrome under
  `presentation/widgets/signup/` (flow rail, three-column foot, field box,
  consent check, DOB wheel, stop screen, abandon confirm). See §11 for the
  money-path rules that lane encodes.

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

- **The payer gate, both entry points.** `KioskSignupStep.payerMatch` +
  `kiosk_payer_match_step` (the "is this you?" confirm on an eligible payer
  duplicate) and `KioskSignupStep.payerPick` + `kiosk_payer_pick_step` (the
  "someone else is paying" picker, over `KioskMatchSearch(forPayer: true)`),
  behind `KioskPayerEligibility` and its fail-closed check. Copy lives in
  `presentation/kiosk_payer_refusal_copy.dart`. See §3.

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
| 201 (no failed items) | `welcome` |
| **409** `MembershipStartReplayError` | `welcome` — an idempotent replay; the ORIGINAL start stands, and charging again is the one thing it must never become |
| 207 (`results` carries failed items) | `declined`, carrying `failedItems` |
| 422 `WaiverGateException` | back to `waivers`, seeded with exactly the ids the server named |
| 500 / transport | `stop` — "nothing was charged" |

A 207 is a **2xx**, so the split is read off `result.hasFailures`, never off a
status code. Treating a 409 as a failure would double-charge on the retry;
treating a 207 as a success would tell a member they joined when they did not.

**The 422 route drops the named waivers from the signup's own signed set.** The
server is authoritative — skipping a waiver it is blocking on loops the member
forever.

### 11.3 Flow-count discipline on the money screens

`paying` **never** releases (a live charge is exactly what the T+11h45 grace
window exists for) · `declined` **does not** release on entry (the member is
still standing there and can retry, however many times) · `welcome` and every
terminal `stop` release exactly once · a **retryable** stop
(`plansUnavailable`, `previewFailed`) deliberately does **not** release,
because "Try again" returns to a live flow; its auto-return `abandon()`
releases it if the member walks off.

### 11.3a A decline is never an ending, and there is no wait between attempts

**No number of declines ends a signup, and no attempt is ever gated by a
client-side timer.** Mistyped cards and short balances are ordinary, so a member
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

There is no cooldown, no timer, and no `pay()` gate on a decline run — a member
can retry the same card back-to-back with no wait. Attempt-velocity throttling
(the card-testing vector on an unattended device) rides **entirely on the
platform Stripe Radar rule** (a founder decision), not the client. This is the
industry shape: rate limiting + Radar, not a client-side strike count. **Do not
model Visa's per-card reattempt limit client-side** — every "Try another card"
tokenizes a brand-new payment method, and classifying decline codes is the
processor's job.

None of it weakens the money-safety properties: **both** retry paths mint a NEW
idempotency key, re-send **only** `state.failedItems`, and never re-create a
member, re-sign a waiver or re-link a payer. `pay()`'s synchronous `paying`
guard + the sent-key latch keep a double-tap (of Retry or of Pay) to exactly one
charge, and a 500 / transport failure is still the "nothing was charged" stop —
this is the 207 path only. The 5-minute idle guard remains the backstop for a
declined screen nobody is standing at.

### 11.4 The rules the copy and the request encode

- **`set_default` branches on the cart.** A recurring cart MUST keep the card (a
  subscription can only bill the saved default, and the backend rejects a
  recurring start without one); a purely one-time cart is attach → pay → detach.
  The card step's "what happens to my card" line branches on the same predicate,
  because writing "only used for this signup" on a recurring plan is a lie.
  **Do not copy `start_memberships_wizard.dart`'s retry card logic** — the CRM
  deliberately sends NO card for a recurring cart because it reuses the payer's
  saved default, and the kiosk has none.
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
  statement.
- **`declined` is a POPUP acknowledgement whose primary action retries the SAME
  card.** `KioskDeclinedScreen` is the kiosk's one modal vocabulary (veil +
  centered popup card) carrying the blameless reason ("Your bank declined the
  payment"), the card chip, and **three stacked buttons, no timer** (§11.3a):
  "Retry" (primary, → `retrySameCard`, re-charges the same card with a new key),
  "Try another card" (secondary, → `retryCard`, drops the member back on the card
  step with a fresh empty field), and "Get help at the desk" (the
  always-available handoff, → `getHelpAtDesk` → `_stop(cardDeclined)`, holding
  committed state). All three are always available, there is deliberately no
  "Start over" (§2), and none is ever forced (§11.3a). Three kiosk-scale labels
  do not fit side by side in a `dialogMaxWidth` popup, so they stack; removing
  the timer freed the vertical room, and a test renders all three at 1180×820
  with no overflow.
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
  retryable stop, because a review with no figures on it is a blank screen.
- **Signed stays signed.** Signatures append to `KioskSignupState.signedWaivers`
  and are keyed on the MEMBER (`signedWaiverIdsFor(memberId)`); walking Back
  skips what that person already signed and nothing un-signs it. Back out of
  the card lands on the PLAN, not the waiver behind it, for exactly that reason.
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

### 11.5 The GROUP's own money rules

- **Link before start, structurally.** The start call never links, so
  `_buildStartRequest` returns null unless `KioskSignupState.everyPayeeLinked`.
  That one guard covers the preview and the charge alike: a roster with an
  unauthorized payee cannot assemble a request at all, let alone send one.
- **`PUT /members/{payee}/link` signs and links in ONE call** and commits
  immediately — there is no group transaction and no rollback. A 409 means the
  gym republished the payer-auth agreement, so the body reloads and the payer
  re-signs; nothing is recorded against text nobody saw.
- **Waivers are grouped by PERSON, not by document** (ruling 9): every payee
  first (their payer-auth, then their own liability waivers), the payer's own
  liability waiver last. `waiverPersonQueue` / `waiverPersonIndex` drive it, and
  `payerAuthPending` is what splits the one `waivers` step between
  `KioskPayerWaiverStep` and `KioskWaiverStep`. The iPad changes hands once per
  person.
- **A signature is keyed on (member, waiver).** Two children on the same plan
  each sign that plan's waiver; keying on the waiver id alone would skip the
  second child and hand the backend an unsigned member at the start.
- **The membership check decides who is in the CART, per person.**
  `payer_member_id` is identity-only server-side, so an unticked payer pays for
  others with no membership of their own. `anyoneTraining` is the empty-cart
  guard: a roster with nobody ticked would send `memberships: []` and take a
  400, so it cannot leave the People step — see §3 for the control and the
  legible block.
- **A 207 retry carries ONLY the failed items.** `_startItems` filters to
  `state.failedItems` whenever it is non-empty, so anything already created
  stands and is never re-charged — and no member, signature or link is ever
  re-executed. The retry mints a new `pm_` and a new key.
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
- **Both duplicates end in an offer, through DIFFERENT gates.** A PAYEE 409 is
  offered straight away (a payee pays nothing, so reusing their account is
  simply correct). A PAYER 409 is offered only once the
  no-attached-payment-method check passes, and lands on the terminal stop
  otherwise (§3). `test/features/kiosk/bloc/kiosk_signup_group_test.dart` holds
  the payee side; `bloc/kiosk_signup_payer_test.dart` holds the payer side and
  its fail-closed pair.
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
  second create, the waiver queue + `signedWaivers`, the payer gate
  (`KioskPayerEligibility`, `_payerEligibility`, `_offerPayerMatch`,
  `confirmPayerMatch`, `openPayerPick` / `pickPayerRow` / `_adoptPayer`,
  `canSwitchPayer`), the money path (`_buildStartRequest` / `pay` /
  `_onDeclined` / `retrySameCard` (same card, new key) / `retryCard` (new card) /
  `_enterWelcome`, the `_sentAttempts` latch, `kKioskSignupStartTimeout`), the
  `KioskSignupStopReason`s and their `isRetryable` split, and the lane's own
  begin/endFlow latch + idle guard.
- `presentation/screens/kiosk_signup_screen.dart` — provides that cubit (so its
  lifetime is the flow's), hosts the signup's activity listener, and routes
  `abandoned` → `goHome()`.
  `presentation/widgets/signup/` — the signup chrome (rail, three-column foot,
  field box, consent check, DOB wheel, stop screen, abandon confirm) and the
  built steps: `kiosk_plan_pick_step` + `kiosk_plan_card` + `kiosk_plan_labels`
  (a COPY of the CRM's `planAllowanceLabel` vocabulary, never an import) +
  `kiosk_plan_picked_banner` (the "YOU'VE PICKED" confirmation, §8.1a),
  `kiosk_waiver_step` + `kiosk_waiver_doc_panel` (read-only
  `WaiverMarkdownEditor`) + `kiosk_sign_panel` + `kiosk_waiver_status`,
  `kiosk_card_step` + `kiosk_secure_strip` + `kiosk_card_facts` (wrapping the
  shared `CardFieldBox`), `kiosk_review_step` + `kiosk_review_side_panel` +
  `kiosk_money_panel` + `kiosk_buy_row` + `kiosk_card_chip`,
  `kiosk_paying_screen`, `kiosk_declined_screen`, and `kiosk_welcome_screen`
  (which COMPOSES the shipped `get_app/` set off the flow cubit's warmed
  catalogues — zero fetches), plus the GROUP half: `kiosk_people_step` +
  `kiosk_roster_row` + `kiosk_person_adder`,
  `kiosk_match_step` + `kiosk_match_card` + `kiosk_match_search`,
  `kiosk_payer_waiver_step`, `kiosk_review_group_panel` + `kiosk_person_block`,
  and `kiosk_money_labels` (the by-person attribution of a preview line, via
  its `stripe_price_id`); the payer gate's `kiosk_payer_match_step` +
  `kiosk_payer_pick_step` over the shared `kiosk_name_row`; the roster's
  `kiosk_row_action` (Edit + trash) and `kiosk_remove_confirm`; the pinned
  `kiosk_who_for`; and `kiosk_proration_note` (the part-period line, §11.4).
  `presentation/kiosk_signup_stop_copy.dart` — the ONE map from a stop reason to
  member copy, mirroring `kiosk_blocked_copy.dart`;
  `presentation/kiosk_payer_refusal_copy.dart` — the same for the payer
  picker's inline refusals.
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

- `GET /api/v1/members/{member_id}/payment-method-status` → `{"has_payment_method":
  bool}` — the payer gate's read (§3), consumed via
  `MemberRepository.getPaymentMethodStatus`.
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
repository call, the sent latch, 409-as-success, 207 → declined, 422 →
waivers, 500 → "nothing charged", the uncapped no-wait decline model — Retry
re-sends the SAME card with a NEW key while "Try another card" re-enters, a
double-tap Retry is one charge, and neither re-creates/re-signs anything — the
two retryable stops, the request builder's
empty price-reduction fields + `paidWithCash: false` + `set_default`, and the
due-today / two-charges arithmetic),
`bloc/kiosk_signup_group_test.dart` (the §11.5 group rules: the payee 409
offer, adopt-vs-recreate, link-before-start both ways, the per-training-person
cart, the 207 partial retry, roster removal, the empty-cart guard, the search
debounce + sequence guard, and the per-member signature keying),
`bloc/kiosk_signup_payer_test.dart` (the §3 payer gate: both entry points, the
**fail-closed pair** on each, adoption that never creates a member, the
link-before-charge invariant after a payer swap, `canSwitchPayer`, and the
existing-member skip / new-member edit round trip),
and the
presentation guards `kiosk_type_ramp_test.dart`, `kiosk_group_steps_test.dart`
(the roster / match / details screens compose at 1180×820 with the email
masked, Edit only for people this signup created),
`kiosk_signup_chrome_test.dart` (§8.1a: the pinned identity survives a scroll,
a group names every turn, the card step names the PAYER and not the active
person, the waiver box fills the fold, and the §11.4 proration line renders
only on a prorated preview), `kiosk_get_app_modal_test.dart`
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
