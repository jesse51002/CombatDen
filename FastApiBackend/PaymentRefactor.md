# Payment Sync — Remaining Work

> **Scope: this is the forward roadmap only — the work that is NOT yet built.**
> Everything the engine already does (re-derive-and-converge orchestration, the
> three-table discount model, sync-time coupon compute, the pre-sync once-discount
> settle, the price writeback, the DB-first caller contract with pre-sync +
> verify/revert) is **shipped** and documented in the skills:
> `sync-guide` (the engine), `discounts-guide` (the discount model),
> `memberships-guide` (the lifecycle callers), `payments-guide` (the Stripe
> primitives + webhooks). Read those for how the live system works.
>
> This file holds the deferred **features** and is **always forward-looking**: it
> lists only remaining work — when something ships it is **removed**, never
> annotated "done".

## 7. Per-membership `paid_by_member_id` — who actually pays each membership (not built)

> Linked (family) members currently have **no independent billing identity** — everything
> resolves to the paying parent. But a linked member will sometimes need to pay for their
> **own** things on their **own** payment method: a store purchase, a drop-in / daily class,
> or even carrying their own membership line — without routing it through the parent.

### Current state — everything resolves to the paying parent
`BillingParentResolver.resolve_parent` follows `members.account_linked_to_id` **once** to the
paying parent, who owns the `stripe_customer_id` and the subscription(s). The sync consolidates
the whole family's recurring memberships onto the parent's subscription, and every ad-hoc charge
(`charge_card`, one-time invoices) targets the **resolved parent's** customer. A linked child has
**no way to be billed on their own card** today — the resolver always redirects to the parent.

### What's needed — a per-membership `paid_by_member_id` (a payer reference, not a boolean)
Add a **`paid_by_member_id`** column on each `member_memberships` row — the member who actually
pays for that membership. **Always populated** (see Approach): for a normal family membership it
is the resolved paying parent; for a self-payer it is that member, whose own Stripe customer +
payment method is billed. This lets a family member buy from the store, pay a drop-in class, or
carry their own membership on their own card while still belonging to the family.

**Why a member-id reference, not a `paid_by_linked_account` boolean.** A boolean only encodes
"self vs parent," and the **linked relationship can change** — a child can be unlinked, re-linked
to a different parent, or the payer can shift — at which point a boolean is ambiguous about *who*
pays. Storing the concrete `member_id` of the payer pins it exactly, **survives re-linking**, and
lets *any* member (not just "the one linked account") be the payer.

### Immutable — changing the payer is a NEW row, never an in-place edit
`paid_by_member_id` must be an **immutable column** (added to the `MEMBER_MEMBERSHIPS` immutable set
+ a guard trigger, alongside the already-immutable `item_id`, `stripe_item_id`, `plan_id`,
`price_id`). Changing who pays is **a whole new `member_memberships` row** — cancel the old one,
insert a new one with the new `paid_by_member_id` — exactly the append-only model memberships
already follow (re-enrolling is always a new row, never a flip-back-to-active). This is required,
not stylistic: changing the payer moves the line from one Stripe customer's subscription to a
**different** customer's subscription, so it is a cancel-on-the-old-sub + create-on-the-new-sub
(a brand-new `stripe_item_id`) — **never an in-place reassignment of the existing line**. The
reprice already works exactly this way: `item_id`, `stripe_item_id`, and `price_id` are fully
immutable (trigger-enforced, even at service-role) and a reprice is a tracked
`membership_reprice` task that cancels the old row + inserts a successor — a payer change slots
straight into that model as a new `task_type` reusing the same tasks/task_items machinery,
executor shape (cancel-old + insert-successor + discount copy + convergent sync), in-task guard,
and CRM polling contract.

### Approach — group by `paid_by_member_id` (it's not a big change)
This is **not** a structural fight with the consolidate-to-parent model — it's a change of
grouping key. Today `PaymentSyncBuilder` resolves the family to **one** paying parent and
consolidates every membership onto that parent's subscription. With `paid_by_member_id` the builder
**groups by payer** instead: each distinct `paid_by_member_id` in the family is its own
consolidation → its own subscription → its own sync call. A family with one self-paying member is
simply **two sync calls** — the parent's payer-group and the self-payer's — each converging its own
subscription. The per-line discount math, writeback, and once-settle are unchanged *within* each
payer group.

**Simplest version — always populate the column.** Default every membership's `paid_by_member_id`
to the resolved paying parent's `member_id` so it is **never NULL**, then make **every** engine
read / filter / grouping key on `paid_by_member_id` from now on. The parent-paid case is just
`paid_by_member_id = parent` and the self-paid case is `paid_by_member_id = self` — **no special
branch anywhere**, one uniform "who pays this line" column. `BillingParentResolver`'s parent-follow
becomes the rule that *sets* `paid_by_member_id` (default = parent) rather than a redirect every
read repeats.

### Still real work (not hard, just real)
- **The payer needs their own Stripe customer.** A self-paying linked member is billed on their
  **own** `stripe_customer_id` + payment method, which a linked child doesn't have today — so the
  link / payment flow has to create one for a member who is going to self-pay (membership or ad-hoc).
- **Ad-hoc charges follow the same key.** `charge_card` / store / drop-in target the paying
  member's customer — the store / drop-in cases are *charges*, not memberships, so they read the
  payer the same way (see open questions).

### Open questions
- Does a membership paid by a non-parent member still **consolidate for family discounts**, or is it
  priced on its own line? Grouping by payer naturally splits it off — confirm that's the intended
  discount behavior, or whether family-tier counting should still include it.
- **Ad-hoc charges:** the store / drop-in target is a *charge*, not a membership. Does the charge
  path read a per-membership `paid_by_member_id`, or does the paying member need a payer reference
  of its own?
- **Where the payer's Stripe customer lives and when it's created** — at link time, or lazily on the
  first self-paid action?
- **Freeze is account-level (on the parent)** — when a membership is paid by a non-parent member,
  does the parent's freeze still cascade to it, or does that payer group freeze independently? Plus
  the interaction with the consolidated subscription per interval (§2).

## 11. Per-membership PAYMENT TYPE — cash vs card per item, not per request (not built)

> One person frequently covers part of a cart for someone else: the payer's card
> auto-charges their own memberships while one membership in the same request is
> settled with cash someone handed over (or vice versa). Today that's impossible —
> payment type is one flag for the whole request. Decided as definitely-needed
> (2026-06-11) but deferred.

### Current state — payment type is request-level
`paid_with_cash` lives on `MemberMembershipsStartRequest` (locked when the op was
designed: "payment method is request-level — the consolidated one-time invoice is
ONE charge"). It flips the WHOLE one-time invoice to `paid_out_of_band` and the
WHOLE recurring converge's first invoice to out-of-band. Mixed settlement within
one request cannot be expressed.

### What's needed — payment type on the ITEM
A per-item payment-type field (`paid_with_cash` on `MemberMembershipsStartItem`,
or a small enum if more types ever arrive), with the engine splitting by it:

- **One-time/trial:** group the pending rows by payment type → **one consolidated
  invoice PER type** (the card group charges normally; the cash group is
  `paid_out_of_band`). The family-sweep read gains the payment-type dimension
  (today `charge_one_time` sweeps ALL pending rows onto one invoice — it must not
  mix types). `charge_count` / `multiple_charges` count the extra invoice.
- **Recurring:** harder — the family's recurring memberships consolidate onto ONE
  subscription with ONE first invoice, so cash-vs-card granularity inside a single
  converge doesn't exist on Stripe. Likely resolution: the first-invoice
  out-of-band flag stays converge-level, and mixed-settlement recurring waits for
  (or composes with) §7's payer groups — a different payer group is a different
  subscription, which is also naturally a different settlement.
- **Composes with §7 (`paid_by_member_id`):** §7 answers WHOSE customer is billed;
  this answers HOW that charge settles. "Someone covering the cost for someone"
  often needs both — grandma pays cash for her grandkid's membership = the payer
  group is grandma's (§7) and its settlement is cash (§11).

--------------------------



# Later

## 2. Multi-interval recurring — weekly / yearly (not built)

> Recurring is **monthly-only** today; weekly and yearly are needed. The blocker
> that pushed this past MVP was the paid-time-preserving freeze (§3) — its interval
> math + Stripe billing-anchor work was too much for the MVP window, so a simple
> pause shipped instead.

### Current state — monthly only, one bucket, one sub
The DB `recurring_must_be_monthly` CHECK, the engine's single monthly
`IntervalBucket` ("exactly one bucket"), and the interval-named
`members.stripe_sub_id_month` column all assume one interval. The
`IntervalBucket.interval` field and the `_month` suffix were left in deliberately to
anticipate this extension.

### What it takes
- **Lift `recurring_must_be_monthly`** — allow recurring
  `duration_unit ∈ week / month / year`.
- **One Stripe subscription per interval.** Stripe cannot mix billing intervals on a
  single subscription, so a family with weekly + monthly + yearly memberships needs
  up to **three** subscriptions. `members` gains `stripe_sub_id_week` /
  `stripe_sub_id_year` alongside the existing `stripe_sub_id_month`.
- **One bucket per interval present.** The read path groups the family's active
  recurring memberships by `duration_unit`; the builder produces a bucket per
  interval instead of forcing a single month bucket; `execute_sync` runs per bucket
  (create/update/cancel its own sub); the writeback fans per sub. Per-line
  consolidation and the discount/coupon logic are unchanged **within** each bucket.

## 3. Paid-time-preserving freeze (not built)

**Why the current freeze is insufficient.** Today freeze = Stripe
`pause_collection` + a resume date. Pausing collection does **not** give the member
back the time they were frozen — the billing clock keeps ticking through the pause,
so they don't resume with exactly the remaining interval they had paid for. For
monthly that was "close enough" to ship; for **weekly** (day/week precision) and
**yearly** (a few frozen months is real money against a year) it is not.

**What a correct freeze does:**
1. **On freeze**, capture the **remaining time** until `next_due_date` — the credit
   the member already paid for (e.g. "11 days left in the cycle", "4 months left in
   the year").
2. **On unfreeze**, set the **next billing date = unfreeze_date + that remaining
   credit**, so the member resumes with exactly the interval they had left and the
   whole cadence shifts forward by the freeze duration — the billing clock
   effectively *stops* during the freeze instead of continuing to tick.
3. **In Stripe**, shift the subscription's **billing anchor** (`billing_cycle_anchor`
   / `trial_end` / proration controls) so the next invoice lands on the recomputed
   date — not merely pausing and resuming collection.
4. **Across every interval sub** (§2) — each interval subscription's anchor is
   recomputed independently; remaining time uses `relativedelta` for month/year and
   `timedelta` for week.

It builds on the **standalone `PaymentSyncFreeze`** service (already split out of the
main sync) so the freeze path can own this anchor math without running a full sync.

**Open questions:** the exact Stripe mechanism for the anchor shift
(`billing_cycle_anchor` reset vs `trial_end` vs pause + manual anchor) and its
proration / invoice-timing implications per interval; the freeze input shape
(explicit end-date vs a span) and how partial-cycle remaining time is computed and
stored per interval; the **discount-lifetime interaction** — an absolute discount
`end_date` does *not* move with a freeze, so a member loses discount time while
frozen; confirm that's intended or whether a freeze should extend it.

## 4. Configurable billing anchor — create-only (not built)

**Current state — forced to the 1st.** Every recurring subscription is pinned to one
fixed anchor day: `payments_subscription_create.py` sets `billing_cycle_anchor` from
`MONTHLY_BILLING_ANCHOR_DAY` via `_next_monthly_anchor_timestamp`, so all members
bill on the 1st.

**Needed — optional anchor date.** The anchor should be **configurable** — the
member/gym chooses what date to bill on, not hard-coded to the 1st. This matters more
with multi-interval (§2): the anchor generalizes to a **day-of-week** for weekly and
a **date** for yearly, and the paid-time-preserving freeze (§3) already manipulates
the anchor.

**Constraint — create-only, then locked.** The anchor is settable **only at
subscription create** (when there is no active sub). **Once a sub is active the
anchor is locked down** — re-anchoring a live subscription mid-life disrupts
billing/proration, so it must be immutable after create. Changing it would mean
cancel + recreate, never an in-place re-anchor.

**Open questions:** where the chosen anchor lives (per member? per membership? gym
default + override?); how it interacts with first-invoice proration; and the
per-interval anchor shape (day-of-month vs day-of-week vs date) under §2.
