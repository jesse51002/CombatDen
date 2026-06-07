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
> The transient **session-level engineering TODOs** (the per-parent concurrency
> lock #25, the rewards endpoint) live in `FastApiBackend/TODO_SYNC_REFACTOR.md`.
> This file holds the deferred **features**.

## 1. Scheduled reconciler (load-bearing, not built)

The engine self-heals drift **only when a member is actively touched** — every
mutation re-derives the desired state from the CRM and converges Stripe. Drift on
an **idle** member persists until the next manual op. A periodic sweep that runs
the sync on a clock, independent of user activity, closes that gap.

This is **load-bearing**, not merely a drift backstop, because two shipped
discount features depend on a sync running mid-cycle on idle members:

1. **Arbitrary `end_date` enforcement.** An ongoing discount's lifetime is an
   absolute `end_date` we enforce ourselves (Stripe coupons only know
   `once`/`forever`). The discount drops off the line the first time a sync runs on
   or after that date. An actively-billed member's end-of-cycle sync drops it on
   time; an **idle** member triggers no sync, so it would keep applying past its
   `end_date`. The sweep runs the sync on schedule.
2. **`once`-discount consumption finalization.** A `once` discount is consumed when
   Stripe invoices it; the once-settle stamps its `end_date` so it is never
   re-added. The `invoice.paid` webhook now triggers that settle promptly
   (`PaymentSyncService.settle_once_discounts`), so the common case is covered — the
   sweep is the backstop for a **missed** webhook on an idle member.

### What already exists (the sweep reuses, no rewrite)
- **`PaymentSyncService.bulk_payment_sync(member_ids)`** loops members, mints a
  fresh `uuid4()` idempotency key per member, and calls `update_payments_recurring`.
  A scheduled job is just a **third trigger** for it (alongside the lifecycle
  callers and the plan-reprice fan-out). The CRM→Stripe config push reuses as-is.
- **`PaymentSyncOnceDiscounts`** is the once-finalization duty factored into a
  standalone service so the sweep can call it directly; **`BillingParentResolver`**
  is the shared parent/family resolution it leans on. The once-consumption
  **read-half** (read the live subscription's coupons, set-math the consumed ones)
  is **built** — that part of the old "push-only" read gap is closed.

### What does NOT exist — the genuinely-new work
The sync only ever **pushes** CRM-derived desired state onto Stripe; it never reads
a subscription's **actual** Stripe lifecycle status. So a naive sweep will **not**
detect that Stripe's dunning engine moved a sub `past_due → unpaid → canceled` on
its own schedule — `PaymentSyncStripe.execute_sync` would just call
`update_subscription` on a now-cancelled sub, error
(`PaymentsResourceNotFoundError`), get logged, and **leave the CRM stuck on
"active."** The **Stripe→CRM outcome-absorption** half is new logic.

**Conflict-resolution rule (load-bearing).** When the sweep finds Stripe ≠ CRM, the
winner depends on the kind of difference:
- **Config drift** — wrong items / quantities / discount / price on the sub →
  **CRM wins** → push to Stripe (reuse the recompute). This is config the CRM
  authored (no member self-serves via a Stripe-hosted portal, so config never
  originates on Stripe's side).
- **Lifecycle / outcome drift** — Stripe shows `canceled` / `past_due` / `unpaid`
  from dunning → **Stripe wins** → absorb into the CRM (mark the member delinquent /
  cancelled). **Do NOT recreate the subscription or re-bill.** Blindly converging
  here resurrects a delinquent member's sub and fights Stripe's billing engine every
  run. This split is the difference between a safe reconciler and one that undoes
  Stripe's dunning.

### Other requirements
- **No-op when already in sync.** `execute_sync` always issues a Stripe `update` for
  an existing sub with items (it does not diff). Fine on a per-request change; on an
  hourly sweep it means pointless writes (and proration risk if anything is off). The
  scheduled path needs a **compare-desired-vs-actual, skip-if-equal** guard.
- **What to compare:** subscription status (to catch dunning), items/quantities,
  discounts, and price/cost.
- **The sweep validates convergence-to-our-logic, not correctness.** A bug in the
  desired-state computation reproduces identically in the per-request path and the
  sweep (same code). The independent correctness check on *outcomes* stays the
  webhook mirror + tests — not the sweep.

**Open questions:** cadence + scope (all active subs each run, or changed-since /
per-gym batching?); the exact **status-absorption mapping** — which Stripe statuses
(`canceled` / `unpaid` / `past_due`) map to which CRM member/membership states, and
how that interacts with the existing webhook handlers (`invoice.payment_failed`,
`account.updated`) to avoid double-applying.

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

## 6. Preview: split due-now vs recurring (not built)

**Current state — one flat preview.** Every preview path
(`preview_update_payments_recurring` → `PaymentSyncStripe.preview_execute_sync`)
returns a single `PaymentsInvoicePreviewResponse` — one `amount_due` for the
upcoming invoice, with no breakdown of what is charged **now** vs. what **recurs**,
and no per-line classification.

**What's needed — `{due_now, recurring}` with typed lines.** Restructure the preview
into two buckets, each line carrying a `kind` (base / proration / discount) and its
period, so the CRM can render "Due now $X = proration + first period − discount,
then $Y/mo after" instead of one opaque total. This applies to **every** preview
surface — start, price-change, and the add/remove-discount previews.

**Touches:** `payments_invoice_schema.py` (the response shape),
`payment_sync_stripe.py` (`preview_execute_sync` → emit the split), the preview
callers + the `member_memberships_router.py` preview endpoints (including the
`discounts/add` + `discounts/remove` previews), `Database/openapi.json` (regenerated,
gitignored), the CRM preview UI, and the preview tests.

**Open questions:** the exact line taxonomy (is `proration` always separable from
`base`? where do multi-membership consolidated lines land?); and a dedicated
due-now preview test landing with it. Confirm the shape before starting.

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
  verifying now too (tracked in `TODO_SYNC_REFACTOR.md`).

## 9. Persist invoice line items — itemization has never worked (not built)

> **Found + flagged.** Nothing in the codebase ever inserts into `member_invoice_line_items`. The
> `invoice.paid` webhook writes the invoice, updates membership dates, and inserts the charge, but
> **never persists the invoice's line items**. The table is **always empty** (the only reference to
> it is a *read* in `member_details_transactions.sql`).

### Consequences
- The CRM invoice popup has **always shown the single "Payment · $X" fallback** — itemization is
  **not a render bug**, there is simply **no line-item data** to render.
- Any **line-item count** can't exist — the rows don't exist. (This changes the scope of anything
  that counts line items.)
- `member_invoice_applied_discounts` (the per-invoice discount audit table) is in the **same
  boat** — also never written today.

### What's needed
Persist the invoice's lines when `invoice.paid` (and `invoice.payment_failed`) fire: write each
Stripe invoice line into `member_invoice_line_items` (the table already reuses the Stripe `il_…` id
as its PK, so it's idempotent for free), classified `membership` vs `custom`, with `item_id` set for
membership lines; and write `member_invoice_applied_discounts` for the discounts the invoice applied.
Then the invoice popup itemizes from real data and the line-item count becomes meaningful.

## 10. Open questions & cross-cutting deferrals

- **Discount auto-update (deferred).** Today a preset edit affects only *new*
  applications — existing snapshots stay pinned to their old value version (the
  predictability guarantee in `discounts-guide`). The **provenance fields**
  (`source_discount_id`, `linked_discount_planid` + `linked_discount_num`) exist
  precisely so a future "re-apply this preset to its existing holders" bulk action
  *can* find and update the snapshots deriving from a given preset. A possible "same
  membership type" constraint would make that edge-case-free (if every snapshot
  deriving from a preset sits on the same plan/quantity shape, re-applying a changed
  value is unambiguous). Not decided — enabled by the provenance fields but
  intentionally not built.
- **Session-level engineering TODOs** (the per-parent concurrency lock #25 and the
  rewards `GET /rewards/{reward_id}` endpoint) are tracked in
  `FastApiBackend/TODO_SYNC_REFACTOR.md`, not here.
