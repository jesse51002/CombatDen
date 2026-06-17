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

## 7. Per-membership `paid_by_member_id` — who pays each membership (✅ BUILT)

Shipped on the `paid-by-member-id` branch. Every `member_memberships` row carries
an **immutable** `paid_by_member_id` (the resolved parent, or a self-paying linked
member). The payment engine is now **payer-centric**:
`update_payments_recurring(payer_member_id)`, reads scoped by `paid_by_member_id`,
one subscription per payer, per-payer freeze / cancel / charge_card (explicit
payer). `account_linked_to_id` is the **authorization layer** only (you must be
linked to pay for someone else; the payer must be the membership's member or that
member's linked parent), never the billing key — and the `linked_account_no_stripe`
CHECK is **dropped**, so a self-paying linked member holds their own card / sub /
freeze window. The full rationale + mechanics live in the **`sync-guide`** and
**`memberships-guide`** skills (the shipped-engine source of truth); the seed
gives ~50% of linked children a self-paid membership; the CRM payer UI lives in
`CRM/.../member_details`. (Kept here as an anchor — §8 and §11 below still cite §7
for the payer-change-is-a-new-row immutability and the per-payer groups.)

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
