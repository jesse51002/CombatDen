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
> lock #25, the preview due-now/recurring split #19, the rewards endpoint) live in
> `FastApiBackend/TODO_SYNC_REFACTOR.md`. This file holds the deferred **features**.

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

## 6. Open questions & cross-cutting deferrals

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
- **`gyms_stripe_connect_service.py` calls Stripe directly** (Connect onboarding) —
  the one direct-Stripe caller outside `src/payments/`. Decide whether to route it
  through a payments service.
- **Session-level engineering TODOs** (the per-parent concurrency lock #25, the
  preview due-now/recurring split #19, the rewards `GET /rewards/{reward_id}`
  endpoint) are tracked in `FastApiBackend/TODO_SYNC_REFACTOR.md`, not here.
