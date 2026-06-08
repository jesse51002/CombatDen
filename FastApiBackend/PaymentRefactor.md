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

## 1. Reconciler skip-if-equal guard (not built)

The scheduled reconciler itself is **shipped** — the `reconciler` domain: a
twice-daily sweep (invoice-fetch backfill -> orphan cleanup -> CRM->Stripe push),
started by APScheduler in the app lifespan. See `reconciler-guide` / `sync-guide`
for the detail. Only one optimization was deliberately deferred:

`PaymentSyncStripe.execute_sync` always issues a Stripe `update` for an existing
sub with items (it does not diff), so the push sweep writes to every active
family's sub every run — harmless with `proration_behavior="none"` (no charge),
but wasteful, and a proration risk if a future change makes the converge
non-idempotent. The deferred work is a **compare-desired-vs-actual, skip-if-equal**
guard on the scheduled push path: compare items / quantities, discounts, and
price / cost, and skip the Stripe write when already in sync. (Subscription
*status* drift is already handled — the sync cancels a gone sub natively
(`PaymentSyncCancel`): `canceled` / not-found → cancel the family + null the sub
id, never recreate.)

## 5. Post-discount amount PER MEMBERSHIP (not built)

> A new feature, separate from the engine itself. Today the CRM cannot read a single
> member's *own* discounted price off their membership row — only the plan-wide line
> total. This feature stores each membership's individual post-discount amount.

### Current state — per-PLAN total, fanned identically to every row
The price writeback (`price_writeback.py` → `sync_prices_by_plan.sql`) reads Stripe's
upcoming invoice, resolves each line's `stripe_price_id → plan_id`, **sums per
plan**, and writes that per-plan post-discount total onto **every**
`member_memberships.total_price` row in the family on that plan (scoped by
`member_id = ANY(family_ids)`). Because same-price family memberships consolidate
into **one Stripe line with quantity N**, the value written to each of those N rows
is the **whole line's discounted total**, identical across all N — not each member's
individual share. So `total_price` answers "what does this plan's consolidated line
cost the family" — it does **not** answer "what is *this* member paying."

### What's needed — each membership's own post-discount amount
Write each membership's **individual** post-discount amount onto its own row (a new
column, or a re-purposed/clarified `total_price`), so the CRM / billing detail /
receipts can show "this member pays $X" per membership — correct even when several
family members share a discounted, consolidated line.

### The hard part — apportioning the consolidated line back to each membership
A consolidated qty-N line has one post-discount total from Stripe; splitting it back
to per-member shares is the real work, and it is **not** simply "÷ N" once discounts
differ per member:
- `PaymentSyncDiscounts._aggregate_line_values` computes **line-level** effective
  values (per-membership-sequential percent, averaged across the line; summed
  dollars). The per-membership breakdown — each member's own pre-discount price minus
  their own discount contribution — has to be derived from the same inputs but kept
  **per membership** rather than collapsed to the line.
- Percent discounts are per-membership-sequential then averaged; dollar discounts
  apply to the whole quantity-N line — so a fixed-dollar coupon's split across members
  is a deliberate choice (proportional to pre-discount price? equal? — must be decided
  and must sum back to the line total).
- It must **reconcile to Stripe's actual post-discount line total** (the writeback's
  source of truth), i.e. the per-member shares sum exactly to what Stripe billed — no
  rounding drift.

### Open questions
- **Column shape:** a new `member_memberships.member_post_discount_price` (keep
  `total_price` as the plan-line total) vs. redefining `total_price` to be
  per-membership (and moving the line total elsewhere). The CRM read paths
  (`member_details` / billing grouper) and any existing consumers of `total_price`
  must be migrated together.
- **Dollar-coupon apportionment rule** across members on one line (proportional vs
  equal), and **rounding** so the shares sum exactly to Stripe's line total.
- **Where it's computed/written:** extend the price writeback (it already holds the
  upcoming-invoice lines + the family/plan grouping) to also emit the per-member
  split, vs. a separate pass.
- **Interaction with the per-member preview** (the add/remove discount preview) — the
  preview should be able to show the per-membership post-discount figure too.


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
(a brand-new `stripe_item_id`) — **never an in-place reassignment of the existing line**, and **not**
a `migrating` price-migration (that moves a line *within* one subscription). The existing `item_id`
(the membership PK / Stripe-item identity) and `stripe_item_id` are already immutable (the latter
only mutable during a price `migrating` migration), so this slots straight into that model.

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

## 8. Full membership-row immutability — reprice & payer change become new rows (drop `migrating`)

> **Decision (recorded — build it with the reprice/payer rework, not now).** State it as
> **immutable once set**: `price_id`, `stripe_item_id` (and `paid_by_member_id`, §7) can never
> change once they hold a value — on top of the always-immutable PK/FK identity (`item_id` /
> `member_id` / `gym_id` / `plan_id` / `created_at`). So a **price or payer change is a new row**
> (cancel old + insert new), and `stripe_item_id` drops its `migrating` exception. **`cancel_date`
> keeps its current rule** (locked once `stripe_sync_status = 'deleted'`, clearable before — the
> failed-cancel revert stays). The remaining lifecycle/outcome columns stay writable (`cancel_date`,
> `end_date`, the §5 actual-price writeback, and the Stripe-mirror `next_due_date` /
> `last_paid_date` / `stripe_sync_status`).

### Why — the consolidated line forces it anyway
N family members on one price share **one** Stripe sub-item (`si_X`, quantity N); every one of those
`member_memberships` rows carries the **same** `stripe_item_id` (verified in the writeback —
"a consolidated line maps to every family membership on that price; they all get the same line id").
So:
- **Reprice one of them** can't repoint `si_X` — that would move all N. The repriced member must be
  **split onto a new sub-item** (`si_Y`, a new `stripe_item_id`). Today that's an in-place
  `stripe_item_id` overwrite — the *only* reason the `migrating` carve-out exists.
- **Change one member's payer** (§7) likewise moves their line to a different customer's
  subscription → a new sub-item.

Both already require a new Stripe line, so model them the same on our side: **a new row**. Then
`price_id` / `paid_by_member_id` / `stripe_item_id` are genuinely immutable and `migrating` goes away.

### The rule — immutable once set
- **Immutable once set (trigger-enforced even at service-role):** `price_id`, `stripe_item_id`
  (no more `migrating` exception), and `paid_by_member_id` (§7). Plus the always-immutable PK/FK
  identity: `item_id`, `member_id`, `gym_id`, `plan_id`, `created_at`. *"Once set" matters* because
  `stripe_item_id` is NULL on a pending row until the first sync stamps it — once it holds a value it
  is frozen. (`price_id` is already in the *user*-immutable set but the reprice service mutates it at
  service-role today — this adds the trigger so even the service can't.)
- **`cancel_date` keeps its current rule (unchanged):** locked once `stripe_sync_status = 'deleted'`,
  **clearable before** — that clear-path *is* the failed-cancel revert and it stays. So `cancel_date`
  is immutable-once-`deleted`, **not** immutable-once-set.
- **Writable:** `cancel_date` (per its rule above), `end_date`, the §5 **actual post-discount price**
  writeback, and the existing Stripe-mirror bookkeeping `next_due_date` / `last_paid_date` /
  `stripe_sync_status` (they update every cycle — outcomes, not identity).

### What it touches
- `MEMBER_MEMBERSHIPS` immutable set + the triggers: drop the `migrating` exception on
  `trg_prevent_stripe_item_id_overwrite`; add `price_id` / `paid_by_member_id` guards; retire the
  `migrating` enum value once nothing stages it. (`trg_prevent_cancel_date_overwrite` is **unchanged**
  — `cancel_date` stays locked-on-`'deleted'`, clearable before, so the failed-cancel revert keeps
  working.)
- `update_price` (`member_memberships_update_price.py`): re-shaped from the in-place `price_id` +
  `migrating` write into a **cancel-old-row + insert-new-row** flow.
- The sync builder/writeback: split the repriced / payer-changed member off the consolidated line
  (quantity N → N-1 on the old line; a new single line for the new row).
- **Applied discounts pin to `item_id`** → re-pin onto the **new row's** `item_id` whenever a reprice
  / payer change mints a new row (today they ride along for free on the same `item_id`).

### The writeback auto-creates the new row (upsert by line)
For the new-row model to happen **inside the sync** instead of needing the caller to pre-insert,
`PaymentSyncWriteback` becomes an **upsert by Stripe line**: as it maps live Stripe items back to
membership rows, a live line whose `stripe_item_id` has **no matching row** is **inserted as a new
immutable row** — not just skipped or force-updated onto an existing one (today it only ever
*updates* the rows it finds). So a reprice / payer change simply changes the desired state → the
sync creates the new sub-item → the writeback **materializes the new row automatically**; the old
row is left intact (its line continues at quantity N-1, or `_mark_removed_deleted` stamps it
`deleted` if its line is gone).

For the writeback to populate the new row's immutable columns (`member_id`, `plan_id`, `price_id`,
`paid_by_member_id`), the desired `SyncParams` must carry **which member / plan / price / payer each
desired line belongs to** — today it maps live items back only to *existing* rows, so that per-line
provenance has to be threaded through the build. (This is the same create-if-missing reconciliation
the scheduled reconciler, §1, needs in the Stripe→CRM direction.)

### Test to add (missing today)
- **Reprice one member off a shared consolidated line** (N>1 on one price, quantity-N `si_X`): assert
  the remaining N-1 stay on `si_X` at quantity N-1, the repriced member lands on a **new** sub-item at
  the new price, the **old row is cancelled and a new immutable row** carries the new line, and the
  applied discounts followed to the new row. **No such test exists today — and the current in-place
  path may not split the line correctly** (the repriced row still carries the old shared `si_X` when
  the bucket is built, so two desired items could collide on `si_X`). The *current* behavior is worth
  verifying now too.

## 9. Create a linked family's memberships in one call — multi-member, per-membership discounts at creation (not built)

`POST /api/v1/member_memberships/` (start) creates **one** membership for **one** member and accepts
**no discounts** (payload: `member_id` / `gym_id` / `plan_id` / `price_id` / `prorate` /
`idempotency_key`). Discounting is a **separate, after-the-fact** `POST .../discounts/add`. So a
family is stood up by N sequential calls — start parent → link each child → start each child → add
discounts per membership — and every membership's first invoice is undiscounted.

### Current state — sequential, post-hoc, undiscounted first invoice
- **Single-member, single-call.** No way to create several memberships in one operation.
- **Discounts are post-hoc.** Start cuts the proration / first invoice (`always_invoice`) **before**
  any discount exists; `add_discounts` only pushes the coupon for the *next* cycle. A member who signs
  up *with* a discount still gets an **undiscounted first charge**. The seed proves it: `_apply_discounts`
  runs *after* `_start_one`, so a fresh seed produces **zero discounted invoices** and the per-invoice
  discount audit (the `invoice.paid` capture) records nothing.
- **Every start re-syncs the family.** A linked family rides **one consolidated Stripe subscription**
  (the payer's), so each sequential start triggers its own family re-sync → N converges (and
  potentially N proration invoices) for what is really one sign-up event.

### What's needed — one batch op for a paying family
A single operation that creates memberships for **multiple members at once**, constrained to **one
paying family** (all paid by the same payer and linked to that payer), **each membership carrying its
own discounts**, all **applied at creation before the first invoice**, in **one Stripe converge**:
- **Request shape:** the payer + a list of memberships, each `{member_id, plan_id, price_id, prorate,
  preset_ids}`. Members not yet linked to the payer are linked as part of the op.
- **One build, one sync, one lock.** Link + insert all rows + apply each membership's discounts, then
  run the family sync **once** under a single `PayingMemberLock` / idempotency key → one consolidated,
  **per-membership-discounted** first invoice. Don't loop the single-create path (that re-creates the
  N-converge + post-hoc-discount problems).
- **Per-membership discounts on the consolidated line.** The aggregation already supports different
  discounts per membership on a consolidated line (see `discounts-guide`); the batch just feeds each
  membership's `preset_ids` into that same path. The discount must be on the sub **before** the
  proration invoice is cut (a single converge), not start-then-resync.
- Reuse the existing apply-discount machinery (`MemberMembershipsUpdateDiscounts` / preview-staging)
  and the start/link lifecycle — this is orchestration + ordering, not a new discount engine.
- Once it exists, the **seed builds each family in one call** (drop the sequential start → link →
  start → `_apply_discounts` dance), so seeded members get genuinely discounted first invoices.

### Open questions
- **Validation:** all members in one gym; the payer has a card; no child already linked to a different
  payer; the payer is (or becomes) the family root.
- **Atomicity / partial failure:** all-or-nothing for the batch, or per-member best-effort? (The single
  consolidated sync favors all-or-nothing.)
- **Proration:** one consolidated proration invoice for the whole batch, discounted per line.
- **Custom/linked discounts at create:** the add path takes `preset_ids`; creation may also want to
  mint a custom value inline — presets only, or the full value shape?
- **Relationship to the existing single-start + link + add endpoints:** does the batch op supersede
  them or coexist (single create stays the simple path)?


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
