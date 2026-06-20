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

## 5. Prepay — mark a FUTURE invoice paid early in cash (tabled)

> A member pays cash now for their NEXT (not-yet-open) invoice; their card must
> not charge for it, while mid-cycle changes (adding a membership) must still
> bill normally. Tabled 2026-06-17: it cannot be made predictable without
> re-architecting the sync engine, and isn't worth that now. Today's stopgap —
> cash settles only an OPEN/overdue invoice (the existing `mark_paid_cash`
> out-of-band path, now wired into the CRM Invoices card); upcoming invoices
> show when they open. So "prepay" today = wait until the invoice opens, then
> mark it cash.

### Why it's hard
Future subscription invoices don't exist in Stripe yet, and a payer is billed as
ONE consolidated subscription. So "this one future slice is prepaid but
everything else bills normally" has no clean expression. Mechanisms explored,
each rejected:

1. **`once` dollar-off coupon** (apply an `amount_off` `once` coupon sized to the
   cash). A pending coupon lands on whatever invoice Stripe cuts next, not the
   renewal you meant. Coupons here are **item-scoped** (`sync_builder.py` attaches
   them per consolidated price line), so a *different-plan* add is safe — but a
   *same-plan* family add consolidates onto the **shared quantity line** and, with
   `prorate`, its immediate proration invoice consumes the coupon. An `amount_off`
   `once` coupon **forfeits the excess**, and `PaymentSyncOnceDiscounts`
   permanently stamps it consumed → cash taken AND the real renewal charges the
   card. Fails for exactly the family "whole bill" scope.
2. **`pause_collection` + mark the renewal paid when it opens.** `pause_collection`
   is **subscription-wide**, so it blocks charging for any membership added during
   the prepaid window. Breaks mid-cycle adds.
3. **Prebilling (`billing_schedules`).** Stripe's native "bill in advance," but
   (a) it **errors on `amount_off` coupons** ("amount_off coupons … return an
   error when used with a subscription that has billing_schedules configured") —
   the discount engine mints an `amount_off` coupon for **every** dollar discount,
   so any member with a dollar discount can't be prebilled; and (b) it stores
   `billing_schedules` as **subscription state the sync engine doesn't model** —
   the sync's per-mutation `Subscription.modify` (Stripe's pass-what-you-want-to-
   keep semantics) would likely wipe it, and a prebilled/skipped period would
   confuse `next_due_date`, the once-settle, and the reconciler. (Flexible billing
   mode itself is available and is NOT the blocker — the sync collision is.)
4. **Stripe customer credit balance — the recommended path when revisited.** A
   per-customer credit auto-applies to upcoming invoices, **charges the card for
   the remainder**, and **carries leftovers forward (no forfeiture)** — so it
   survives mid-cycle adds with no pause, and is **orthogonal to the sync engine**
   (it lives on the customer, not the subscription, so the sync never touches or
   wipes it). Caveat: it's **customer-wide** — applies to the next finalized
   invoice, can't be pinned to a specific one — which is benign because remainders
   carry, and matches the per-payer "whole bill" scope. (Billing Credits / credit
   grants were also checked and ruled out: metered/usage prices only.)

### What it takes (when revisited, via customer balance)
- A payments primitive to add a credit
  (`POST /v1/customers/{id}/balance_transactions`, negative `amount` → a
  `CustomerBalanceTransaction`).
- A CRM record of the cash receipt at prepay time (the credit itself is not a
  Stripe charge, so it won't arrive via the `invoice_payment.paid` webhook).
- Webhook handling so a balance-covered future invoice records cleanly
  (`starting_balance`/`ending_balance`, reduced/zero card charge) instead of
  looking like an underpayment.
