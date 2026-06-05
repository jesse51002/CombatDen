---
name: sync-guide
description: >-
  The single source of truth for the CombatDen payment sync ENGINE —
  the code in src/member_memberships/service/payment_sync/ that re-derives the
  full desired Stripe subscription state from the CRM on every membership
  mutation and converges Stripe onto it (reconciliation toward desired state).
  Covers MembershipPaymentSyncService (update_payments_recurring,
  preview_update_payments_recurring, bulk_payment_sync), the read path
  (resolve_parent / family ids / active recurring / applied-discount snapshots
  in payment_sync_queries.py), the builder (build_desired_items,
  consolidate_by_price, build_subscription_bucket, plan_line_discounts in
  payment_sync_builder.py), the read-before-write _current_coupon_ids gate,
  coupon resolution orchestration (PaymentSyncCoupons + set_snapshot_coupon_id /
  stamp_snapshot_end_date writebacks), execute_sync (create/update/cancel +
  freeze) in payment_sync_stripe.py, and the post-discount price writeback
  (price_writeback.py). Load this whenever you touch the sync orchestration,
  the parent/family resolution, the per-line discount planner, the once
  consumption gate, the deterministic coupon find-or-create, the price
  writeback, the preview dry-run, or the deferred scheduled reconciler.
  Trigger on "payment sync", "update_payments_recurring", "re-derive desired
  state", "converge Stripe", "consolidate by price", "resolve_parent", "family
  ids", "plan_line_discounts", "current coupon ids", "read before write",
  "execute_sync", "price writeback", "preview sync", "bulk sync", "reconciler",
  "why did this re-sync", or any change to the payment_sync engine.
---

# Payment Sync — the re-derive-and-converge engine

This is the deep domain knowledge for CombatDen's **payment sync engine**: the
code that, on every membership mutation, throws away whatever Stripe currently
has and **recomputes the full desired subscription state from the CRM**, then
forces Stripe to match. It is the **source of truth** for how that engine
behaves; CLAUDE.md holds only the "how to work here" rules, and
`FastApiBackend/PaymentRefactor.md` (§1–§4, §6) holds the prose design
rationale. When the engine changes, **update this skill in the same change** (it
is a living document — see the bottom).

This skill owns the **orchestration / mechanics** in
`src/member_memberships/service/payment_sync/`. It does **not** own:

- **What discounts mean** — the three-table identity / versioned-value / snapshot
  model, the once-vs-ongoing lifetime spec, the `end_date` semantics, and the
  rationale for the percent×quantity fix are owned by `discounts-guide` (its
  §4–§5 is the seam). This skill describes how the engine *consumes* snapshots,
  not what they mean.
- **The low-level Stripe subscription/coupon primitives** (`get_subscription`,
  create / update / cancel subscription, coupon retrieve/create, upcoming-invoice
  preview) → `payments-guide`. The engine *calls* them; it does not redocument
  their internals.
- **The membership lifecycle callers** (start / cancel / freeze / price-change /
  discount-change / link) → `memberships-guide`. They *trigger* the engine.

---

## 1. What the engine is — re-derive, converge, self-heal

`MembershipPaymentSyncService` is a **declarative reconciler** (the same pattern
as Kubernetes controllers / Terraform): on every membership mutation it does not
apply a targeted delta to Stripe — it **rebuilds the entire desired
subscription** from the CRM and converges Stripe onto it. Any transient drift
(missed webhook, partial failure, race) **self-heals the next time that member is
touched**, because the next sync recomputes from scratch and overwrites.

Three properties fall out of "re-derive from scratch every time":

- **The CRM owns config / intent** (prices, plans, who's enrolled, which
  discounts are applied); **Stripe owns billing outcomes** (did the invoice
  clear, dunning lifecycle). The engine pushes intent → Stripe; webhooks mirror
  outcomes ← Stripe (see `PaymentRefactor.md` §3).
- **The desired state is a pure function of the member's own family.** There is
  no cross-member reshuffle — everything is computed from the paying parent +
  linked children, deterministically.
- **The one gap:** it only self-heals **when a member is actively touched.** Drift
  on an *idle* member persists until the next operation on them. The deferred
  scheduled reconciler (§10) closes that gap — and is now load-bearing for two
  discount features, not just a drift backstop.

---

## 2. Triggers + entry points

`MembershipPaymentSyncService` exposes exactly three public entry points (plus
`resolve_parent` for upstream validation):

| method | what it does | callers |
| --- | --- | --- |
| `update_payments_recurring` | the real sync: re-derive → freeze/unfreeze → attach coupons → execute → write sub id + prices back | every membership mutation |
| `preview_update_payments_recurring` | the dry run: same read/build, then a Stripe invoice *preview*, **no writes** (§9) | the CRM "what will this charge?" preview |
| `bulk_payment_sync` | loop members, fresh `uuid4()` idempotency key each, call `update_payments_recurring` with empty add/cancel | reprice fan-out; the future reconciler (§10) |

**What triggers a real sync** — each lifecycle caller (owned by
`memberships-guide`) calls `update_payments_recurring`:

| caller | trigger |
| --- | --- |
| `member_memberships_start.py` | new membership |
| `member_memberships_cancel.py` | cancel a membership |
| `member_memberships_freeze.py` | freeze / unfreeze (uses `freeze_end_date` / `unfreeze`) |
| `member_memberships_update_price.py` | mid-cycle price swap |
| `member_memberships_update_discounts.py` | apply / remove a discount (then re-sync resolves the coupon) |
| `members_management_linked.py` | link / unlink a family account |

The first five callers live in `src/member_memberships/service/memberships/`; the
last, `members_management_linked.py`, lives in `src/members/service/management/`
(linking is a member-management action, not a membership-lifecycle one).

Plus **plan reprice**: `membership_plans/service/plans/membership_plans_price.py`
fans out via `bulk_payment_sync` — the one *deliberate* bulk price migration that
survives (the two discount cascades were removed; see `PaymentRefactor.md` §6).

`add_ids` / `cancel_ids` are `SyncItem` lists; the empty/empty call is a pure
re-derive (used by `bulk_payment_sync` and freeze-only flows).

---

## 3. The orchestration sequence (`update_payments_recurring`)

The real path runs these steps in order. Read the method for the exact code; the
sequence is:

1. **Validate freeze params** (`_validate_freeze_params`): a freeze/unfreeze
   action **cannot** be combined with membership changes, and freeze+unfreeze
   together is rejected — billing order on Stripe matters, so these are separate
   operations.
2. **Build sync params** (`_build_sync_params`, §4) — the pure read path that
   resolves the parent, family, active memberships, applied-discount snapshots,
   and the desired `IntervalBucket`. No writes.
3. **Freeze / unfreeze first** (`PaymentSyncStripe.sync_freeze_state`) — applies
   `pause_collection` before any item change, because the billing order matters.
4. **Compute + attach this cycle's coupons** (`_attach_computed_coupons`, §6–§7) —
   read the live subscription's current discounts, plan each consolidated line,
   find-or-create the deterministic coupon, attach it to the bucket item, and
   write each resolved `stripe_coupon_id` (and any `once` consumption) back onto
   the contributing snapshots.
5. **Execute the sync** (`PaymentSyncStripe.execute_sync`, §8) — create / update /
   cancel the monthly subscription to match the bucket.
6. **Write the subscription id back** (`update_profile_sub_id` →
   `update_profile_sub_ids.sql`) — the new sub id (or `None` if cancelled) onto
   the parent's `members` row.
7. **Mirror post-discount totals back** (`PriceWriteback.sync_prices_from_stripe`,
   §8) — read the upcoming invoice and fan the post-discount line totals across
   the family's membership rows + the parent's monthly total.

Returns the `PaymentsSubscriptionResponse`, or `None` if the sync cancelled the
subscription (empty bucket).

---

## 4. The read path — parent / family / memberships / snapshots

`_build_sync_params` is the **pure read half** (no CRM or Stripe writes) shared by
the real and preview paths. It runs four reads via `PaymentSyncQueries`, resolves
the gym Stripe account, applies the cancel filter, then builds the bucket:

| step | how | SQL |
| --- | --- | --- |
| **resolve parent** | follow `account_linked_to_id` **once** (single-level hierarchy) to the paying parent; raise if no profile or no `stripe_customer_id` | `resolve_parent.sql` |
| **gym Stripe account** | `GymStripeService.get_stripe_account_id(gym_id)` | (payments-guide) |
| **family ids** | parent + every child whose `account_linked_to_id = parent` in that gym | `get_family_ids.sql` |
| **active recurring memberships** | `plan_type = 'recurring' AND cancel_date IS NULL`, joined to plan + price for `duration_unit`, `stripe_price_id`, `price` | `get_active_recurring.sql` |
| **applied-discount snapshots** | every snapshot on the family's memberships, joined to its value version (percent/dollar/mode) + plan (`plan_id`, `stripe_item_id`) | `get_applied_discounts_by_member.sql` |

`resolve_parent.sql` and `get_family_ids.sql` read **`member_billing_profile`** (a
`security_invoker` view over `members` exposing the billing columns incl.
`account_linked_to_id`); `resolve_parent` self-joins it via
`COALESCE(account_linked_to_id, member_id)` so a parent resolves to itself and a
child resolves up one level. The snapshot read joins the **unfiltered** base
tables (`member_membership_applied_discounts_unfiltered`,
`gym_discount_values_unfiltered`) at service-role — half-synced rows with no
`stripe_coupon_id` yet must still be visible to the sync that resolves them
(the filtered client view hides those).

### The cancel filter — full identity, not price

After reading active memberships, the engine removes `cancel_ids` by the
**`(member_id, plan_id)`** key, **not** by `stripe_price_id`:

```python
cancel_keys = {(item.member_id, item.plan_id) for item in cancel_ids}
memberships = [m for m in memberships if (m.member_id, m.plan_id) not in cancel_keys]
```

On a shared family plan every row shares the same price, so price-only filtering
would drop **every sibling** when one child cancels. This is a load-bearing
correctness rule.

New `add_ids` are resolved to `(duration_unit, price)` via `get_price_intervals.sql`
(`_resolve_add_intervals` → `map_add_ids_to_intervals`); existing rows already
carry their interval/price from the membership read.

---

## 5. The builder — consolidation + the per-line discount planner

`payment_sync_builder.py` is pure logic (no DB / Stripe). Three shaping
functions plus the planner:

- **`build_desired_items(memberships, add_intervals)`** — current memberships
  become `IntervalDesiredItem`s with `prorate=False` (existing items never
  prorate); adds keep the caller's prorate. Cancellations must already be
  filtered upstream (§4).
- **`consolidate_by_price(items)`** — group by `stripe_price_id`, **sum
  quantities**, sum prices, take the `stripe_item_id` from whichever member of
  the group has one, and resolve `prorate` by priority
  (`new_no_prorate > new_with_prorate > old`, via `_resolve_prorate`). This is
  the consolidation that produces a single quantity-N line per price — the reason
  the percent÷quantity fix exists.
- **`build_subscription_bucket(desired, existing_sub_id)`** — consolidate, then
  wrap into one `IntervalBucket` (all recurring plans are monthly, enforced by
  the DB `recurring_must_be_monthly` constraint, so there is exactly one bucket).

### The per-line discount planner (`plan_line_discounts`)

This is where the engine turns frozen snapshots into per-line effective values.
For every bucket item **that already carries a `stripe_item_id`** (an existing
Stripe line — a brand-new line with no item id yet is **skipped**, §11), it
gathers the snapshots frozen onto that line (`by_item[snap.stripe_item_id]`) and
runs `_plan_one_line`:

1. **`end_date` exclusion** (`_is_past_end_date`): drop any snapshot whose
   resolved `end_date` is `<= today` (inclusive cutoff). This is how the engine
   enforces arbitrary end dates Stripe can't express.
2. **`once`-consumption gate** (`_is_consumed_once`, §6): a `once` snapshot with a
   null `end_date`, a non-null stored `stripe_coupon_id`, and that coupon **no
   longer present** on the live subscription is **consumed** → its id goes into
   `consumed_ids` (the caller stamps its `end_date`) and it is dropped from this
   cycle. A `once` snapshot with no coupon yet is still **pending**.
3. **Per-mode aggregation** (`_aggregate_values`): the survivors are grouped by
   `discount_mode` so **`once` and `ongoing` never mix** into one value. Per mode:
   `line_percent = (Σ per-unit percents) ÷ quantity` and `line_amount = Σ
   per-unit dollar_offs`. A mode emits a percent value and/or a dollar value only
   when its sum is non-zero. Each value carries the `applied_discount_id`s of the
   same-mode snapshots that fed it (`contributing_ids`) — its writeback set.

The output is a `LineDiscountPlan` per line (`values` + `consumed_ids`). **The
planner does no Stripe or DB calls** — it only decides each line's value and
which snapshots fed / were consumed; the service owns the coupon find-or-create
and the writebacks.

> **The percent÷quantity split is the consumer side of the
> `discounts-guide` percent×quantity fix.** *Why* a 10%-off-1-of-2 must become
> 5%-on-the-quantity-2-line is owned by `discounts-guide` §4. This engine just
> divides by the consolidated quantity.

---

## 6. Read-before-write — `_current_coupon_ids` and why

Before computing anything, `_attach_computed_coupons` reads the **live
subscription's current discounts** via `_current_coupon_ids`:

```python
sub = await self._subscriptions.get_subscription(existing_sub_id, stripe_account_id)
coupon_ids = set(sub.discounts)            # subscription-level coupon ids
for item in sub.items:
    coupon_ids.update(item.discounts)       # plus every item-level coupon id
```

The live coupon set is the **union of `sub.discounts` + every
`item.discounts`** (both are `list[str]` of coupon ids on
`PaymentsSubscriptionResponse`). When there is **no** existing sub it returns the
empty set (a brand-new sub has no prior discounts, so every `once` snapshot is
still pending).

**Why this read is the genuinely new path:** the old sync only ever *pushed*
desired state built from the CRM — it never read Stripe's actual subscription.
Reading first buys two things:

- **`once`-consumption truth.** "Has Stripe already invoiced this `once`
  coupon?" can only be answered by Stripe (Stripe owns outcomes). A stored coupon
  still **present** ⇒ pending; **absent** ⇒ consumed. Without the read, the
  engine can't tell a consumed `once` from a pending one.
- **Drift safety.** Reconciling against the *actual* live coupon set, not a CRM
  guess, is what lets the converge step be correct after a missed webhook or
  partial prior run.

This is the read half `PaymentRefactor.md` §4 calls out as the gap the old
push-only `execute_sync` left open; the discount engine fills it for the coupon
computation. (The lifecycle/status-absorption half — Stripe-cancelled-by-dunning
— is still future work in the reconciler.)

---

## 7. Coupon resolution orchestration + writebacks

`_apply_line_plan` turns each `LineDiscountPlan` into real Stripe coupons + DB
writebacks. For one line:

1. **Stamp consumption** — for every `consumed_id` the planner found, call
   `stamp_snapshot_consumed` → `stamp_snapshot_end_date.sql` (service-role,
   writes the unfiltered base table, idempotent: only stamps a row whose
   `end_date IS NULL`). Recording the consumption date short-circuits all future
   presence checks — the `end_date` exclusion drops the snapshot forever after,
   so the engine **stops querying Stripe** for it.
2. **Find-or-create one coupon per surviving per-mode value** —
   `PaymentSyncCoupons.find_or_create(value, stripe_account_id)`.
3. **Write each value's coupon back onto its own contributing snapshots** —
   `set_snapshot_coupon_id` → `set_snapshot_coupon_id.sql` (service-role,
   unfiltered base table) for every `applied_discount_id` in
   `value.contributing_ids`. The writeback is **per-value**: a `once` value's
   coupon lands on the `once` rows, an `ongoing` value's on the `ongoing` rows,
   so the `once` presence handle stays exact.
4. **Attach to the line** — if the bucket item exists, set
   `item.discounts = [SubscriptionItemDiscount(coupon=cid) …]`.

### `PaymentSyncCoupons` — deterministic ids, no registry table

Coupons are **computed at sync, never pre-baked**. Each line value maps to one
Stripe coupon by a **deterministic id** that is a pure function of the value:

| value | coupon id (`PaymentSyncCoupons.coupon_id`) |
| --- | --- |
| percent | `pct_<bps>_<mode>` where `bps = round(percentage_off * 100)` (basis points) |
| dollar | `amt_<cents>_<mode>` where `cents = int(dollar_off or 0)` |

`<mode>` is the `DiscountMode` value (`once` / `ongoing`). Because the id is a
pure function, `find_or_create` is **idempotent**: it retrieves by id first, and
on create passes the id so a concurrent/repeat create **collides** on Stripe's
side; the `stripe.InvalidRequestError` is caught and treated as "already
exists." One coupon per distinct value+mode is **reused across every member** on
the gym's Connect account — **no coupon registry table** is needed.

Mode → Stripe duration (`_MODE_TO_STRIPE_DURATION`): `once` → Stripe **`once`**
coupon; `ongoing` → Stripe **`forever`** coupon. Stripe has no native arbitrary
end date, so an ongoing coupon is always `forever` on Stripe and the `end_date`
cutoff is enforced by **us** dropping the snapshot (the §5 exclusion). Percent
coupons round to 2 decimals (Stripe's `percent_off` limit); dollar coupons set
`amount_off` (integer cents) + `currency = "usd"`.

> **Discount *semantics* live in `discounts-guide`.** The meaning of `once` vs
> `ongoing`, the lifetime spec (duration-span XOR explicit `end_date`), and the
> snapshot model are owned there. This section documents only how the engine
> *resolves* a snapshot into a coupon and writes the result back. The low-level
> Stripe coupon retrieve/create calls themselves are `payments-guide`.

---

## 8. `execute_sync` + freeze + price writeback

### `execute_sync` (`payment_sync_stripe.py`)

`PaymentSyncStripe.execute_sync` dispatches off the bucket:

- **bucket has items** → `_sync_bucket`: **update** if `existing_sub_id` is set,
  else **create**. The `proration_behavior` is `"always_invoice"` if **any**
  bucket item requests `prorate` (a mid-cycle swap cuts the prorated delta as an
  immediate invoice), else `"none"`. Existing items always carry `prorate=False`,
  so this only fires when a caller opted into proration on a new/replacement item.
  Every subscription carries `StripeSubscriptionMetadata(member_id, gym_id)`.
  `pay_first_invoice_out_of_band` only applies on **create**.
- **empty bucket + existing sub** → **cancel** the subscription.
- **empty bucket + no sub** → `None` (nothing to do).

Sub-operation **idempotency keys are suffixed** off the base key:
`:sub_create`, `:sub_update`, `:sub_cancel`, and `:freeze` / `:unfreeze` on the
freeze path. The create/update/cancel calls themselves are `payments-guide`
primitives.

### Freeze (`sync_freeze_state`)

Freeze is `pause_collection`. Precedence: an explicit `freeze_end_date` freezes;
an explicit `unfreeze` resumes; otherwise it falls back to the parent profile's
intrinsic `is_frozen` (the freeze-window property on `ParentProfile`). No-op when
there's no `stripe_sub_id`. It is **idempotent** (re-freezing updates the resume
date; unfreezing a non-paused sub is a Stripe no-op) and it lets
`PaymentsResourceNotFoundError` **propagate** — a missing sub during freeze means
the CRM expects billing but Stripe has none, an out-of-sync state that must
surface.

### Price writeback (`price_writeback.py`)

After the sync, `PriceWriteback.sync_prices_from_stripe` mirrors **Stripe's
post-discount truth** back onto the CRM. It reads the **upcoming invoice**
(`fetch_upcoming_invoice`, payments-guide) and:

| writeback | SQL | target |
| --- | --- | --- |
| per-plan post-discount total fanned across the family's rows on that plan | `sync_prices_by_plan.sql` | `member_memberships_unfiltered.total_price` |
| the full monthly recurring charge on the parent | `sync_profile_monthly_total.sql` | `members.total_monthly_recurring_price` |

`sync_prices_by_plan.sql` resolves each invoice line's `stripe_price_id` → `plan_id`
via `membership_plan_prices`, sums per plan, and writes that onto every
`member_memberships` row in the family on that plan (scoped by
`member_id = ANY(family_ids)` so other families on the same plan are never
touched; uses `CAST(:param AS …)` — never `:param::type` — per the SQLAlchemy
`text()` bind gotcha). When `stripe_sub_id` is `None` (fully cancelled), the
parent monthly total is zeroed. **Writeback failures are logged at ERROR and
never re-raised** — Stripe is authoritative and a later mutation / the
reconciler re-corrects the mirror. (`update_stripe_item_id.sql` also exists in
this folder; the membership lifecycle callers use it to write back a new line's
`stripe_item_id` — owned by `memberships-guide`.)

---

## 9. Preview = no coupons, no writeback (a true dry run)

`preview_update_payments_recurring` runs the **exact same** `_build_sync_params`
(resolve, family, snapshots, bucket) as the real path, then calls
`PaymentSyncStripe.preview_execute_sync` — Stripe's invoice **preview**, never a
mutation. Critically it **skips two real-path steps**:

- **No `_attach_computed_coupons`.** A dry run must not find-or-create Stripe
  coupons or write `stripe_coupon_id` back, so the preview reflects the
  **pre-discount-resolution** bill. (This is the same boundary `discounts-guide`
  §4 records from the discount side.)
- **No DB writeback** — no sub-id write, no price writeback, no consumption
  stamping. Nothing in the CRM or Stripe changes.

`preview_execute_sync` mirrors `execute_sync`'s dispatch (`preview_update_…` for an
existing sub, `preview_create_…` for a new one) and returns `None` for a pure
cancellation or no-op — there's no upcoming invoice to preview. Freeze/unfreeze is
intentionally unsupported in preview (a `pause_collection` change produces no
invoice). The idempotency key is a throwaway `uuid4()` (preview writes nothing,
so the key is unused downstream — it only satisfies the shared request schema).

---

## 10. The deferred scheduled reconciler (load-bearing, not built)

A periodic sweep that runs `update_payments_recurring` on every member on a clock
is **not built yet** but is now a **functional dependency**, not merely a drift
backstop (`PaymentRefactor.md` §4):

1. **Mid-cycle `end_date` enforcement on an idle member.** An ongoing discount's
   cutoff is dropped only the first time a sync runs **on or after** that date. An
   actively-billed member's end-of-cycle sync drops it on time; an **idle**
   member (no changes near the cutoff) triggers no sync, so the discount would
   keep applying past its `end_date`. The sweep is the only thing that runs the
   sync on schedule.
2. **`once`-consumption finalization on an idle member.** Detecting that a `once`
   coupon was invoiced (and stamping its `end_date`) only happens when a sync runs
   after the invoice. The sweep guarantees prompt finalization instead of leaving
   it "pending" until the next manual touch.

`bulk_payment_sync` is already the seed — a scheduled job is just a third trigger
for it. The genuinely **new** work is the **Stripe→CRM outcome-absorption** half:
`execute_sync` only pushes CRM-derived state, so a naive sweep won't detect a
Stripe-dunning cancellation (it would just error and leave the CRM stuck on
"active"). The reconciler needs the conflict-resolution rule from
`PaymentRefactor.md` §4 — **config drift → CRM wins** (push), **lifecycle/outcome
drift → Stripe wins** (absorb, never re-bill) — plus a compare-and-skip-if-equal
guard so an hourly sweep isn't pointless Stripe writes.

---

## 11. Engine gotchas

- **A brand-new line with no `stripe_item_id` is skipped by the discount
  planner.** `plan_line_discounts` only processes bucket items that already carry
  a `stripe_item_id`; a just-added line gets no coupon **this** sync and picks one
  up on the **next** sync once Stripe has assigned its item id. The lifecycle
  caller writes the item id back (`update_stripe_item_id.sql`) so the follow-up
  sync sees it.
- **Idempotency keys are suffixed per sub-operation** (`:sub_create`,
  `:sub_update`, `:sub_cancel`, `:freeze`, `:unfreeze`) off one base key, so the
  several Stripe calls in one sync don't collide. `bulk_payment_sync` mints a
  fresh `uuid4()` per member (each member's sync is independent).
- **The family cancel filter keys on `(member_id, plan_id)`, never price alone**
  (§4) — price-only would nuke every sibling on a shared family plan.
- **Coupon swap when consolidated quantity changes.** Adding/removing a family
  member shifts the `÷ quantity` split, producing a different effective percent →
  a different deterministic coupon id → the line **swaps** to the new coupon. A
  pending `once` re-divides correctly on swap; an absolute `end_date` is invariant
  under swaps (the swap changes the coupon's value, never its end — the
  swap-invariance rationale is owned by `discounts-guide`).
- **`_current_coupon_ids` returns empty for a brand-new sub** — so the
  consumption gate treats every `once` snapshot as pending on first sync (correct:
  nothing's been invoiced yet).
- **`bulk_payment_sync` swallows per-member errors** —
  `PaymentsResourceNotFoundError` and any `Exception` are logged at ERROR and the
  loop continues, so one member's broken Stripe state doesn't abort the batch.
- **Price writeback never raises** — Stripe is authoritative; a failed mirror is
  re-corrected by the next mutation or the reconciler.

---

## Key files (where the engine actually lives)

- **Orchestrator:**
  `FastApiBackend/src/member_memberships/service/payment_sync/membership_payment_sync_service.py`
  (`MembershipPaymentSyncService` — `update_payments_recurring`,
  `preview_update_payments_recurring`, `bulk_payment_sync`,
  `_attach_computed_coupons`, `_current_coupon_ids`, `_apply_line_plan`,
  `_build_sync_params`).
- **Builder + planner (pure):** `payment_sync_builder.py` (`build_desired_items`,
  `consolidate_by_price`, `build_subscription_bucket`, `map_add_ids_to_intervals`,
  `plan_line_discounts` → `_plan_one_line` / `_aggregate_values` /
  `_is_past_end_date` / `_is_consumed_once`).
- **Read/write queries:** `payment_sync_queries.py` (`PaymentSyncQueries` —
  `resolve_parent`, `get_family_ids`, `get_active_memberships`,
  `get_applied_discounts`, `get_price_intervals`, `set_snapshot_coupon_id`,
  `stamp_snapshot_consumed`, `update_profile_sub_id`).
- **Coupons:** `payment_sync_coupons.py` (`PaymentSyncCoupons` — `coupon_id`,
  `find_or_create`, `_retrieve`, `_build_create_params`).
- **Stripe dispatch + freeze:** `payment_sync_stripe.py` (`PaymentSyncStripe` —
  `execute_sync`, `preview_execute_sync`, `sync_freeze_state`, `_sync_bucket`).
- **Price writeback:** `price_writeback.py` (`PriceWriteback.sync_prices_from_stripe`).
- **Intermediate models:** `member_memberships/schema/payment_sync_schema.py`
  (`ParentProfile`, `ActiveMembershipRow`, `AppliedDiscountSnapshot`, `SyncItem`,
  `IntervalDesiredItem`, `IntervalBucket`, `LineDiscountValue`, `LineDiscountPlan`).
- **SQL (`member_memberships/sql/payment_sync/`):** `resolve_parent.sql`,
  `get_family_ids.sql`, `get_active_recurring.sql`, `get_price_intervals.sql`,
  `sync_prices_by_plan.sql`, `sync_profile_monthly_total.sql`,
  `update_profile_sub_ids.sql`, `update_stripe_item_id.sql`. **SQL
  (`…/sql/applied_discounts/`):** the snapshot read
  `get_applied_discounts_by_member.sql`, the writebacks `set_snapshot_coupon_id.sql`
  and `stamp_snapshot_end_date.sql` (the apply/remove snapshot SQL in this folder
  is owned by `discounts-guide`).
- **Stripe primitive it leans on for the read:**
  `payments/service/subscription/payments_subscription_retrieve.py`
  (`get_subscription` — documented as a `payments-guide` primitive; returns
  `PaymentsSubscriptionResponse` with `discounts` + `items[*].discounts`).
- **Design rationale (prose):** `FastApiBackend/PaymentRefactor.md` §1–§4, §6
  (the engine, the source-of-truth split, the reconciler, what collapsed).
- **Orchestration flow diagram:** `FastApiBackend/payment_sync.mermaid` — the
  step-by-step flow of `update_payments_recurring` (the §3 sequence), plus the
  `preview` / `bulk` / deferred-reconciler branches. The sync steps are grouped in
  one box with Stripe + Supabase as outside actors and box-level edges (same
  convention as `FastApiBackend/architecture.mermaid`). Top-down, authored under
  the `mermaid-creation` rules (validated: render + `check_siblings.py` + Mermaid-9
  parse). Referenced from `FastApiBackend/README.md`.
- **Siblings:** discount semantics → `discounts-guide`; Stripe sub/coupon/invoice
  primitives → `payments-guide`; lifecycle callers → `memberships-guide`.

---

## This is a living document

This skill is the single source of truth for the payment sync engine. Whenever
the engine genuinely changes — a new orchestration step, a changed coupon-id
format, the reconciler getting built, a new trigger, a renamed service or SQL
file, a changed read/writeback — **update this skill in the same change** so it
never goes stale. When the change touches the orchestration sequence, a trigger,
or a step's external calls, **also update the flow diagram
`FastApiBackend/payment_sync.mermaid`** in the same change (re-validate it with
the `mermaid-creation` skill) so the picture and the prose stay in sync.
