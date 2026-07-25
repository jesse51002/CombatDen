# PR #59 — open decisions

Everything the post-build audit (`refine-backend`) and the `/code-review high`
pass surfaced that I did **not** act on, because each has more than one
reasonable answer. The clear defects are already fixed and committed; this is
only the list that needs you.

Each entry has a **recommendation** so you can rubber-stamp a section rather
than reason through all of it. Reply with IDs (e.g. "B1 yes, B2 option 2, skip
the P4 cluster") and I'll implement.

**Where the two audits agreed:** `B1` was found independently by both, from
opposite directions. That's the one I'd read first.

---

## P0 — Billing. Decide before this ships to a real gym.

`FastApiBackend/CLAUDE.md` gates `src/memberships/` and `src/sync/` behind
per-piece approval, so none of these were touched.

### B1 — A declined kiosk card is left as the payer's default, and their working card is already detached
`src/memberships/service/memberships_start.py:118-133`
→ `src/payments/service/payments_stripe_members_service.py:168-172`

`_set_default_card` runs **before** any charge and is never reverted.
`update_customer` attaches the new card, makes it the customer default, then
**detaches the old one** — and a detached PaymentMethod cannot be re-attached.

The kiosk is the first caller ever to send `set_default: true` (the CRM wizard
never did), so nothing before this PR exercised promote-then-decline.

**Failure:** an existing member with a working card adds a membership at the
kiosk. New card attaches, old card is deleted, the recurring first invoice
declines. The kiosk says *"Your bank declined the payment — you haven't been
charged"*, which is true about this purchase and false about their account:
their **pre-existing** subscription now bills the refused card, and next cycle
they go overdue on a membership they never touched.

| # | Option | Cost |
|---|---|---|
| 1 | Revert the default after a decline | Doesn't help once the old card is detached — partial fix only |
| 2 | **Don't detach on the kiosk path.** Attach + set default, leave the old card attached | The kiosk stops "replacing" the card literally; old cards accumulate on the customer |
| 3 | **Charge first, promote second** | Recurring needs the default *before* the subscription bills, so this only works for one-time-only carts |
| 4 | Accept it, change the copy | Cheapest, but the member still silently loses a working card |

**Recommendation: 2, plus 3 where it applies.** The detach is what makes this
unrecoverable — stop that first. Then promote only after a successful charge for
carts that don't need the default up front. Recurring still promotes first, but
with no detach a decline costs the member nothing.

### B2 — A non-card failure after the one-time leg already collected returns 500 "nothing created"
`src/memberships/service/memberships_start.py:315-322`

Order in `start()` (`:139-144`): insert all rows → charge one-time → converge
recurring. `_verify_group(keep_unverified=True)` at `:274` deliberately **keeps**
billed one-time rows. So a non-card failure in the recurring converge re-raises
→ the router's 500, whose OpenAPI description at `:325` reads *"Total failure —
nothing created."* Money moved and a membership is live.

`origin/main` returned a 207 breakdown here; this PR changed it to prioritise
"a system failure must never masquerade as a decline."

| # | Option |
|---|---|
| 1 | **207 with the failed item carrying a system-failure reason** — honest per-item truth, but a 2xx for an outage |
| 2 | Keep 500, fix the description, client treats 500-after-partial as "see the front desk" |
| 3 | A distinct status for "partially succeeded then broke" |

**Recommendation: 1.** Your own rule is that a 2xx no longer implies money moved
and the client branches on the per-item result — this is that case. A 500 saying
"nothing created" over a collected charge is the worse lie.

### B3 — The same arm orphans the recurring rows
`src/memberships/service/memberships_start.py:266-273`

`_cleanup_states(group)` deletes only the group passed in, but `_insert_all` has
already **committed** every row including recurring. So a non-card failure on the
one-time leg leaves recurring rows as `not_added` ghosts still holding their
idempotency keys. Then: same-key retry → `ON CONFLICT DO NOTHING` drops it →
shortfall → **409 forever**; new-key retry → trips the same-plan trigger →
**500**. The member cannot start that membership until the reconciler sweeps it.

I think this one is unambiguous — cleanup should cover every un-billed row, not
just the failing group — but it's inside the billing fence.
**Recommendation: fix as described.**

### B4 — `LockBusyError` surfaces as 500 instead of 409
`src/memberships/memberships_router.py` (retry-card's `except Exception`)

`retry_card` acquires the payer lock *inside* its try, and `LockBusyError`
subclasses `Exception`, so the global 409 handler in `main.py` can never fire.
Front desk clicks Retry while a bulk reprice holds the lock → 500 instead of a
retryable 409.

`FastApiBackend/CLAUDE.md` names this exact hazard and prescribes the fix (a
typed arm that re-raises). **Recommendation: do it** — mechanical, and your own
doc specifies it. Listed here only because of the billing fence.

### B5 — The not-collected / SCA outcome still returns 500
`src/payments/service/payments_stripe_payment_service.py:592-608`

If the invoice never reaches `paid`, this raises → 500. That's a definitive
"we could not collect, staff must act" outcome — the same *kind* of thing as a
decline, now on the opposite side of the contract from `CardError`. Your own
rationale ("reporting it as a 500 buries real outages under ordinary declines")
applies verbatim.
**Recommendation: fold it into the 207 contract** with its own reason.

### B6 — The start route's 207 declares no response model
`src/memberships/memberships_router.py:319-321`

You deliberately gave retry-card's 207 a `"model"` with a comment on why a client
generator must see the decline body. The start route — the primary kiosk decline
surface — has the description but no model. **Recommendation: add it.**

### B7 — `update_customer`'s attach carries no idempotency key
`src/payments/service/payments_stripe_members_service.py:145-151`

Its sibling `attach_payment_method` requires one. Every external write is
supposed to carry a deterministic key. Note the ordering too: it sets the new
default *before* detaching the old PM and *before* the DB write, so a detach
failure leaves Stripe on the new card and the `members` row on the old one.
**Recommendation: add the key; revisit ordering with B1.**

### B8 — Should a retry re-send `unknown` rows?
`CRM/lib/features/kiosk/bloc/kiosk_signup_state.dart` (`retryMemberIds`)

I fixed the retry to key on **not-created**, so an `unknown` row gets retried.
Today `unknown` is only the parse fallback for an unrecognised status string, so
it's unreachable. But if a future backend returns a status meaning "it landed"
that this client parses to `unknown`, the retry would charge it. The alternative
— never retry `unknown` — means a partial receipt whose Retry does nothing.

**Recommendation: keep current behaviour**, and treat "never add a status string
without teaching the client" as the rule. Flagged because it's a money-adjacent
judgement I made inside a fix.

### B9 — `nextFromResults()` has no all-created guard
`CRM/lib/features/kiosk/bloc/kiosk_signup_cubit.dart`

The UI only offers `Next` on the all-created branch, so a partial can't reach the
welcome celebration today — but the cubit would allow it.
**Recommendation: add the one-line guard**, so a future UI change can't
congratulate someone whose payment partly failed.

---

## P1 — Contracts and correctness

### C1 — Members error `code`: ship it or drop it
`src/members/members_exceptions.py`, `src/main.py`

The new typed hierarchy declares a `MembersErrorCode` StrEnum and locks it in
tests, but **`code` never reaches the wire** — that needs a ~12-line handler
registration in `main.py`. It's currently the one incoherent state: declared,
tested, invisible.

Your `FastApiBackend/CLAUDE.md` says codes are opt-in per domain and *"a domain
whose clients never branch past the status (most of them) needs only `detail` and
no code machinery."* No CRM client branches on a members code today.

**Recommendation: drop the enum**, keep the typed exceptions for status mapping.
Option 2 is register the handler and add the OpenAPI model. Either is coherent;
the half-state isn't.

### C2 — Three blanket `except ValueError` → 404 arms
`src/members/members_router.py:331` (`GET /{id}`), `:383` (`GET /{id}/billing`),
`:1012` (authorized-payer-waiver)

A pydantic `ValidationError` **is** a `ValueError`, so a broken response model on
the large billing payload answers **404 "Member not found"** and hides a 500. Not
narrowed because `_find_target_profile` also raises there, and flipping an
unknown deep `ValueError` from 404 → 500 is a contract change.
**Recommendation: narrow the first two** (~6 lines). The third needs `waivers`.

### C3 — Where should `date_of_birth` be bounded?
`Database/supabase/schemas/members.sql:47`,
`src/members/schema/members_schema.py:28,71,109`

Both bare — no CHECK, no validator. The kiosk can post `2035-06-01`, or a
fat-fingered `0202-06-01`, and get a 201 with the value stored verbatim.

Options: Pydantic `field_validator` rejecting future dates · DB
`CHECK (date_of_birth <= CURRENT_DATE)` · a plausible-range floor (≥ 1900) ·
accept-as-is because the CRM picker bounds it.

**Recommendation: both the CHECK and the validator.** The picker isn't the only
writer — kiosk, admin form, seed and any future import all write here — and your
belt-and-suspenders rule covers anything a UI could bypass. The DB half needs a
hand-written migration, which **you** run.

### C4 — `DELETE /{id}/payment`'s OpenAPI description is false
It claims it *"immediately cancels all active recurring memberships"*, but
`unlink_payment` only clears the card fields and detaches from Stripe. Whether
unlink *should* cancel is a product question.
**Recommendation: tell me which is wrong** — prose or behaviour — and I'll fix
that one.

### C5 — A paid-but-unconfirmed membership reads as an "incomplete signup"
`src/members/sql/crm_views/_member_incomplete.sql:32-40`

The fragment reads `member_memberships_status`, which hides non-`applied` rows.
But `memberships_start.py:274` deliberately **keeps** a one-time row whose
writeback failed ("billed lines are never un-billed"). So a member who paid for a
10-class pack at the kiosk lands in the Incomplete tab with `days_waiting`
climbing, and staff chase someone who already paid.
**Recommendation: exclude billed-but-unconfirmed rows** — they need
reconciliation, not a signup.

### C6 — The Incomplete tab can list a member whose detail page 404s
`src/members/sql/member_details/member_details.sql:141-142` drives from
`member_billing_profile`, which requires a Stripe customer id. Verified live: 26
members match the incomplete predicate, 1 has none. Pre-existing shape, but the
Incomplete tab is the list that surfaces such shells, so "click the stalled
signup → 404" is newly reachable from a new affordance.
**Recommendation: make the detail read tolerate a customer-less member.**

### C7 — Three `/link*` handlers still dispatch on prose
`src/members/members_router.py:742,747,809,969` — marked `KNOWN GAP` in place.
Their `ValueError`s come from `src/memberships/service/memberships_linked.py` and
`src/waivers/service/waivers_signatures.py`, including a `"reload"` → 409 match.
Fixing them means typed exceptions in those domains — and `memberships` is a
money domain, so its base must stay on `Exception`, not `ValueError`.
**Recommendation: do `waivers` now, leave `memberships` for its own pass.**

### C8 — The duplicate-member 409 sends `detail` as an object
`src/members/service/management/members_management_create.py:131`

`FastApiBackend/CLAUDE.md` forbids this outright — the CRM's `_extractDetail`
only reads a `String`, so a non-string degrades every error to "Server error 409:
Conflict". Either the CRM special-cases this 409 (then the rule needs the
carve-out written in) or the kiosk's duplicate-match flow relies on something the
doc says can't work.
**Recommendation: let me trace the CRM side and report before changing
anything** — I genuinely don't know which yet.

### C9 — CRM `start_plan_rules.dart` blocks more broadly than the backend rejects
The CRM refuses any non-one-time plan at active/trial/frozen/overdue; the backend
SQL rejects only **recurring** at active/frozen. The kiosk uses the narrower
backend truth, so the CRM wizard refuses sales the backend would take.
**Recommendation: align the CRM to the backend.** (Carried from an earlier
session, still open.)

---

## P2 — Product gaps

### G1 — The Get-the-App QR points at a page that does not exist
`CRM/lib/features/kiosk/presentation/widgets/kiosk_get_app_modal.dart:15`
encodes `https://www.combatden.net/get-app/{gymId}`. There is no such page in
`LandingPage/`. Every member who scans it after paying hits a dead link — the
terminal step of the adoption funnel.

### G2 — The per-gym app-store URLs have no write path
`gyms.app_store_url` / `play_store_url` exist and are read by
`/gyms/{id}/app-links`, but they're absent from `GymUpdateData`, the only
mutable-gym-fields model. So the per-gym branch can never fire and the endpoint
always returns the `config.py:337-344` fallbacks — self-labelled `PLACEHOLDER`,
pointing at unpublished listings.

**Recommendation for both: ship the page (Phase G) or hide the QR until it
exists.** Today it's a live dead link on 100% of gyms. The write path is ~10
lines whenever you want it. This is the one item I'd flag as
"don't demo this yet."

### G3 — The seed mints zero reward redemptions
`Database/python_data/generators/rewards.py` (costs now 1000–2500, raised from
50–500 to mirror the real preset catalogue) vs `generators/members.py:164`
(`points_balance=random.randint(0, 500)`) vs `generators/redemptions.py:40`
(`if m.points_balance < r.point_cost: continue`).

Max balance is now below the cheapest reward, so **every** draw is skipped, for
every gym, deterministically. The Loyalty approval queue and all redemption
history seed empty — silently. This contradicts `bootstrap/rewards.py:31-32`,
which promises "a steady stream of pending rows in the CRM approval queue's demo
data."

Options: raise the ceiling · a distribution where some fraction clears ~2500 ·
**give members points proportional to their attendance history.**

**Recommendation: the third.** Points-from-attendance is what production does, so
the seed stops being a special case, and members with long histories naturally
afford the expensive rewards — the more convincing demo too.

### G4 — Seeded linked children get adult birth dates
`_form_linked_families` runs after `_demographics`, so a kid-aged band for
`is_linked_child` members needs a second pass. Cosmetic, but the family/payer
demo is exactly where someone checks ages.
**Recommendation: do it** — small, and it makes the parent-pays story read right.

---

## P3 — CRM correctness and polish

### U1 — A gym switch can mount the card field against the wrong connected account
`CRM/lib/core/state/selected_gym.dart:164`,
`CRM/lib/core/network/stripe_account_context.dart:84`

On switch, `stripeAccountContext.apply()` is fire-and-forget while
`isReady`/`paymentsAvailable` keep the **previous** gym's `true` values — so the
documented "await before mount" guarantee doesn't hold and a `CardField` can
mount in the old gym's context. Since cards are tokenized on the gym's connected
account, I rate this above its "cleanup" label.
**Recommendation: drop both flags to false while a new account is applying.**

### U2 — The reward badge field silently truncates existing labels
`CRM/lib/features/rewards/presentation/widgets/value_badge_field.dart:79` gained
`LengthLimitingTextInputFormatter(16)` where the old field had no cap, so an
existing longer badge is destroyed the moment staff touch the field.
Options: raise/remove the cap · keep the cap but don't mutate an over-length
existing value until it's edited · show a counter and allow invalid.
**Recommendation: the second.** Silent data loss on focus is the bug; the
16-char badge design is fine.

### U3 — Staff can no longer open a paused class's occurrence screen
`CRM/lib/features/schedule/presentation/screens/schedule_screen.dart:135` — the
guard narrowed to `entry.isActive && !canEditSchedule`, so a front-desk or
trainer tap on a **paused** entry does nothing.
**Recommendation: restore the read-only path for paused entries.**

### U4 — The last `margin:` in `CRM/lib`
`CRM/lib/features/memberships/presentation/screens/waiver_editor_screen.dart:538`
— and the only genuine "gap between siblings" one, which your rules forbid
outright (the five kiosk ones I fixed were insets). Untouched because the file
isn't in this PR and `_versionTile`'s first call site relies on that top margin,
so moving to `spacing:` deletes the gap above the first tile.
**Recommendation: fix in its own commit**, accepting the tightened first gap.

### U5 — The payer's own address still prints in full on three kiosk surfaces
`kiosk_review_side_panel.dart:43`, the money panel's receipt line, and
`kiosk_results_screen.dart:191`. Two are arguably correct — the payer verifying
where their own receipt lands. `_WhoRow` is the odd one out against "no screen in
this lane prints an address in full"; the group review panel prints none at all.
**Recommendation: mask `_WhoRow`, leave the two receipt lines.**

### U6 — The group review panel names people whose membership already started
`kiosk_review_group_panel.dart` lists every roster person with a plan row. After
a partial failure, re-entering review via "Try another card" still shows a plan
row for someone already charged — the same over-naming class as the
`kioskLineLabel` bug I fixed. But the panel *deliberately* lists everyone (its
docstring explains why a non-training payer must appear), so swapping the
predicate would silently drop a row, which on a review screen reads as "we forgot
them."
**Recommendation: mark the already-started rows rather than hide them** — needs a
design pass, so it's yours.

### U7 — The kiosk pulls the full staff billing payload to read two booleans
`kiosk_signup_cubit.dart:1234` fetches `/members/{id}/billing` — a heavy payload
of stored PII — onto a shared lobby iPad, to derive `hadTrial` and the held-plan
set. Nothing renders it, but it crosses the wire and sits in memory on a device
in a public room.
**Recommendation: add a narrow read** (`GET /members/{id}/plan-eligibility`
returning just the two facts). Also resolves U8.

### U8 — Two independent per-member reads are serialised
`kiosk_signup_cubit.dart:1230` — `_loadPlanEligibility` and
`_loadPriorWaiverStatus` await one member at a time on the two-taps-from-waivers
hot path. `Future.wait` halves it.
**Recommendation: do it** — moot if U7 lands first.

### U9 — The group step rail overflows at a 1024 fold
The 7-rung rail is 1093px intrinsic vs 960px available, currently handled with
`FittedBox(scaleDown)`. **Needs eyeballing on the real iPad** — alternatives are
shorter labels or numbers-only. I can't verify this without the device.

---

## P4 — The duplication cluster (one decision covers all ten)

| Where | What is duplicated |
|---|---|
| `kiosk_payer_waiver_step.dart:97` | a 251-line copy of `KioskWaiverStep`, **including the legal clear-signature-on-new-body invariant** |
| `kiosk_signup_cubit.dart:2493` | the `beginFlow`/`endFlow` balance latch — which `CRM/CLAUDE.md` calls load-bearing |
| `:2453` | the 5-minute idle guard, over the same constants |
| `:2166` | the countdown `Timer.periodic` idiom, written out seven times |
| `:901` | the debounced, sequence-guarded member search |
| `:516` | name-splitting hand-rolled three times instead of `kiosk_name_format.dart` |
| `kiosk_signup_state.dart:293` | no `fullName`, so twelve sites hand-roll it (sibling `KioskSignupMatch` has one) |
| `kiosk_match_search.dart:153` | the four-state search ladder, verbatim across both lanes |
| `kiosk_declined_screen.dart:54` | five modals hand-copy the scrim + card shell |
| `kiosk_streak_week_strip.dart:62` | re-implements `showcase/support/streak_week_strip.dart` |

**Recommendation: take the two cheap ones now, defer the rest.** Add `fullName`
to `KioskSignupPerson` (deletes twelve hand-rolls, zero risk) and extract a
shared `KioskModalCard` shell (would have made the `margin:` fix one line instead
of five).

**Defer the flow-latch and idle-guard consolidation.** Those are the mechanisms
your own docs call load-bearing — an unbalanced flow count means the kiosk never
signs itself out at its 12h lockout. That deserves its own PR with its own tests,
not a cleanup rider.

`kiosk_payer_waiver_step` I'd rank above the rest on *risk* rather than tidiness:
the same legal invariant living in two files means a future fix lands in one and
is missed in the other.

---

## Not decisions — things only you can do

- **Block Link on the connected accounts**: Stripe Dashboard → Settings →
  Connect → Payment methods → Link → **Blocked**, in both Test and Live.
- **Enable Radar's "block if card tested at multiple merchants."**
- **Run the live browser smoke test.** Nothing in this PR has touched a real
  card: full solo signup, a decline with `4000 0000 0000 0002`, a group with
  mixed recurring + one-time, the keyboard on the real iPad, and start-call
  latency against the 90s timeout.
- **Your local `main` has diverged** — 3 unpushed commits, one named `todo`.
  Everything here is based on `origin/main` (c5c7d428), because local `main` is
  not an ancestor of HEAD.
