---
name: sync-guide
description: >-
  The single source of truth for the CombatDen payment sync ENGINE —
  the code in src/member_memberships/service/payment_sync/ that re-derives the
  full desired Stripe subscription state from the CRM on every membership
  mutation and converges Stripe onto it (reconciliation toward desired state).
  Covers PaymentSyncService (update_payments_recurring,
  preview_update_payments_recurring, bulk_payment_sync), the shared
  BillingParentResolver, the builder service PaymentSyncBuilder (build_sync_params
  — read memberships-with-discounts, group by price, assemble the bucket), the
  read path (family ids / active recurring memberships each carrying their
  applied discounts in payment_sync_queries.py), the discount service
  PaymentSyncDiscounts (the per-membership-sequential discount math + the
  deterministic coupon find-or-create with validate-or-replace), the standalone
  PaymentSyncFreeze (pause_collection from the DB freeze window), the pre-sync
  PaymentSyncOnceDiscounts settle (once-consumption finalize + the
  read-before-write live-coupon read), the coupon-link / once-consumption
  writebacks (set_applied_discount_coupon_id / mark_once_consumed), execute_sync
  (create/update/cancel, explicit proration_behavior) in payment_sync_stripe.py,
  and the post-discount price writeback (price_writeback.py). Load this whenever
  you touch the sync orchestration, the parent/family resolution, the builder,
  the discount math, the once-consumption settle, the deterministic coupon
  find-or-create, the price writeback, the preview dry-run, or the deferred
  scheduled reconciler. Trigger on "payment sync",
  "update_payments_recurring", "re-derive desired state", "converge Stripe",
  "group by price", "resolve_parent", "family ids", "discounts ride the
  membership", "aggregate_line_values", "once discounts", "read before write",
  "execute_sync", "price writeback", "preview sync", "bulk sync", "reconciler",
  "why did this re-sync", or any change to the payment_sync engine.
---

# Payment Sync — the re-derive-and-converge engine

> ⚠️ **Critical billing infrastructure — human in the loop.** This engine
> controls how real members are billed. **Never edit it in a big sweep.** Every
> change is proposed, reviewed, and approved **one piece at a time** before the
> next — propose → wait → write, for each part as you go. Do not batch connected
> edits and present them together. A mistake here mis-bills real customers.

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

- **What discounts mean** — the three-table identity / versioned-value /
  applied-discount model, the once-vs-ongoing lifetime spec, the `end_date`
  semantics, and the rationale for the percent×quantity fix are owned by
  `discounts-guide` (its §4–§5 is the seam). This skill describes how the engine
  *consumes* applied discounts, not what they mean.
- **The low-level Stripe subscription/coupon primitives** (`get_subscription`,
  create / update / cancel subscription, coupon find/create/delete,
  upcoming-invoice preview) → `payments-guide`. The engine *calls* them; it does
  not redocument their internals. **Hard rule: nothing under `payment_sync/` ever
  touches the Stripe SDK directly** — coupon I/O is delegated to
  `PaymentsStripeDiscountService`, subscription/invoice I/O to the subscription
  service. A direct `stripe.*` / `.v1.*` call anywhere in the engine is a bug
  (the anti-pattern `PaymentSyncCoupons` used to have).
- **The membership lifecycle callers** (start / cancel / freeze / price-change /
  discount-change / link) → `memberships-guide`. They *trigger* the engine.

---

## 1. What the engine is — re-derive, converge, self-heal

`PaymentSyncService` is a **declarative reconciler** (the same pattern
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

`PaymentSyncService` exposes exactly three public entry points (callers that need
parent resolution inject the shared `BillingParentResolver` directly — not via
`PaymentSyncService` — e.g. `member_memberships_start`):

| method | what it does | callers |
| --- | --- | --- |
| `update_payments_recurring(member_id, idempotency_key, pay_first_invoice_out_of_band=False, proration_behavior="none") -> None` | the real sync: resolve → maintenance freeze re-apply → settle once → build (re-derive bucket **and resolve coupons**) → execute → **`PaymentSyncWriteback`** persists the full sync-owned state (§3). Returns **None** — callers read the DB (the `applied` status) | every membership mutation |
| `preview_update_payments_recurring(member_id, proration_behavior="none")` | the dry run: resolve → **settle once-discounts** (same as real) → same DB-derived build **incl. discount resolution** (so the preview reflects discounts) → Stripe invoice *preview*. Skips the freeze re-apply + the convergence writeback (§9) | the CRM "what will this charge?" preview |
| `bulk_payment_sync(member_ids)` | loop members, fresh `uuid4()` idempotency key each, call `update_payments_recurring` | reprice fan-out; the future reconciler (§10) |

**There are no imperative `add_ids` / `cancel_ids` inputs.** The desired state is
derived purely from the DB on every call — `update_payments_recurring` takes only
a `member_id` (any family member), an idempotency key, the out-of-band-first-
invoice flag, and an explicit `proration_behavior` (`"none"` / `"always_invoice"`,
default `"none"` — proration is a first-class param now, no longer inferred from a
per-item `prorate`). What to bill is whatever the DB says is active *right now*,
never a caller-supplied delta. (This is the load-bearing shape: a caller writes
its mutation to the DB **first**, then calls the sync, which reads that DB and
converges Stripe to it.)

**What triggers a real sync** — each lifecycle caller (owned by
`memberships-guide`) writes its change to the DB then calls
`update_payments_recurring`:

| caller | trigger |
| --- | --- |
| `member_memberships_start.py` | new membership |
| `member_memberships_cancel.py` | cancel a membership |
| `member_memberships_update_price.py` | mid-cycle price swap |
| `member_memberships_update_discounts.py` | apply / remove a discount (then re-sync resolves the coupon) |
| `members_management_linked.py` | link / unlink a family account |

The first callers live in `src/member_memberships/service/memberships/`;
`members_management_linked.py` lives in `src/members/service/management/`
(linking is a member-management action, not a membership-lifecycle one).

**Freeze / unfreeze no longer flows through the main sync.** The explicit freeze
action writes the freeze window to the DB, then calls the standalone
**`PaymentSyncFreeze`** service directly (§8); the main sync only does a
*maintenance re-apply* of the parent's already-resolved freeze window (step 2 of
§3). The freeze caller (`member_memberships_freeze.py`) injects
`BillingParentResolver` + `PaymentSyncFreeze`, writes the freeze window first,
re-resolves the parent (so it carries the window), then converges Stripe.

Plus **plan reprice**: `membership_plans/service/plans/membership_plans_price.py`
fans out via `bulk_payment_sync` — the one *deliberate* bulk price migration that
survives (the two discount cascades were removed; see `PaymentRefactor.md` §6).

### The caller contract: DB-first, then verified, then revert-on-failure

Every lifecycle caller follows the same shape — the `sync_or_revert` helper in
`src/shared/db_first_helpers.py` encapsulates steps 2–3:

0. **Pre-sync to a clean baseline** — call the sync once FIRST
   (`_pre_sync_payments` on `MemberMembershipsBase`, or an inline
   `update_payments_recurring` for link/unlink), with a **fresh** idempotency key
   and default (no) proration, to converge the family's DB↔Stripe state **before
   mutating**. This stops the op from building new desired state on top of a
   drifted DB (e.g. a half-finished prior op left a pending/unsettled row). If it
   raises, the op aborts before any DB change. **Previews skip this** — they're
   read-only dry-runs and must not push real changes.
1. **Write the desired state to the DB** — insert the pending membership
   (`not_added`), set `cancel_date`, write the new `price_id`, write the freeze
   window, or set `account_linked_to_id`.
2. **Call the param-less sync** (`update_payments_recurring`, or
   `PaymentSyncFreeze.sync_freeze_state` for freeze) — it re-derives the desired
   state from that DB write and converges Stripe, then writes back
   `stripe_sync_status`. (Note: this means a mutating op runs **two** syncs —
   the pre-sync converge, then this post-change converge.)
3. **Verify the writeback landed, and revert the DB write if it did not** — so the
   DB never drifts out of sync with Stripe.
   `sync_or_revert(sync_fn, revert_fn, *, entity_name, crm_pk, verify_fn=None)`
   runs the sync; on exception it reverts and re-raises; if `verify_fn` returns
   `False` it reverts and raises `SyncNotConfirmedError`. The verify reads the
   `stripe_sync_status` the writeback stamps (via `_get_sync_status` on
   `MemberMembershipsBase`, reading the **unfiltered** base — the view hides
   `not_added` / `deleted`):

   | caller | DB write | verify | revert |
   | --- | --- | --- | --- |
   | start (recurring) | insert pending row (`not_added`) | row flips `not_added → applied` | delete the pending row |
   | cancel | set `cancel_date` (status stays `applied`) | row flips `applied → deleted` | clear `cancel_date` |
   | update_price | write new `price_id` + stage `migrating` | row flips `migrating → applied` | restore old `price_id`/`total_price`, reset `applied` |
   | freeze / unfreeze | write / clear the freeze window | — (no membership-row status) | restore / re-clear the freeze window |
   | link / unlink | set / clear `account_linked_to_id` | — (child has no recurring) | unlink / re-link |

   Callers whose DB change does not map to a single membership-row status
   transition (freeze, link) pass `verify_fn=None` and get the achievable
   guarantee: **revert-on-exception**.

**Immutability is keyed on the real Stripe state, not a transient flag** — and the
two columns differ on purpose:
- **`cancel_date` (foreground, verified)** locks only once the membership is
  actually **removed from Stripe** (`stripe_sync_status = 'deleted'`,
  `trg_prevent_cancel_date_overwrite`). While the cancel is unconfirmed the column
  stays clearable, so the revert just clears `cancel_date` — **no status to stage
  or un-stage** (cancel never uses `migrating`).
- **`stripe_item_id`** is immutable **except while `stripe_sync_status = 'migrating'`**
  (`trg_prevent_stripe_item_id_overwrite`). `migrating` is reserved for the **price
  migration** (`update_price`): mutating the line id is safe then because a price
  migration is a background-style converge, not a paying↔cancel transition. The
  caller stages `migrating`, the writeback moves the line + stamps `applied`, after
  which the id is immutable again. **`migrating` is ONLY for price migrations** —
  add/cancel are foreground verified ops and never use it. (Engine half of the
  rule the `migrating` enum value exists for — keep it in sync with the schema
  triggers if either changes.)

> **Known residual:** if Stripe converged but the writeback failed to stamp the
> column (rare — it is the last step), the revert undoes the DB change while Stripe
> holds it. The idempotent re-sync / reconciler (§10) reconciles that on the next
> run — the DB stays in sync with Stripe "as much as possible" without a full saga.
> **`stripe_item_id` is never nulled on a delete/cancel** — it is the historical
> invoice-line record (a `deleted` row keeps its line id so you can trace which
> Stripe item / invoice it billed).

The `#23` callers that only *validate* the parent (`member_memberships_charge_card.py`,
`member_memberships_mark_paid_cash.py`) inject `BillingParentResolver` and call
`resolve_parent` directly; they run no sync, so no verify/revert. The engine and
every caller derive desired state **purely from the DB** — there are no imperative
item lists threaded through any call.

---

## 3. The orchestration sequence (`update_payments_recurring`)

The real path runs these steps in order. Read the method for the exact code; the
sequence is:

1. **Resolve parent + gym Stripe account** (`BillingParentResolver.resolve`, §4) —
   one call returns `(ParentProfile, stripe_account_id)`: follow
   `account_linked_to_id` once to the paying parent, then look up the gym's
   Connect account. Everything below operates on this resolved parent.
2. **Maintenance freeze re-apply** (`PaymentSyncFreeze.sync_freeze_state` with the
   resolved parent, §8) — converge `pause_collection` to the parent's DB freeze
   window (`parent.is_frozen`) **before any item change**, so a membership change
   on a frozen account keeps the pause in the correct billing order. This is a
   *re-apply*, not the freeze action itself — the explicit freeze/unfreeze wrote
   the DB and called `PaymentSyncFreeze` directly.
3. **Finalize once discounts** (`PaymentSyncOnceDiscounts.sync_once_discounts`,
   §6) — a **pre-sync DB settle**: detect any `once` discount Stripe has already
   invoiced and stamp its `end_date`, so the build below reads an
   already-settled DB and the **applied-discount read excludes** the consumed
   ones by their stamped `end_date` (no live-Stripe read in the convergence).
4. **Build the desired bucket + resolve coupons**
   (`PaymentSyncBuilder.build_sync_params`, §4–§5) — read family ids + active
   memberships (each carrying its applied discounts), **group by `price_id`**,
   hand the groups to `PaymentSyncDiscounts` (the math + find-or-create, §7) which
   returns a `ResolvedDiscounts` (per-price coupons + the `applied_discount_id →
   coupon_id` links), and assemble the `IntervalBucket` with the coupons attached
   to each line. Returns `SyncParams` (bucket + parent + account + `coupon_links`).
   **DB-derived, no add/cancel inputs, no DB writes** (find-or-create is an
   idempotent gym-wide Stripe op).
5. **Execute the sync** (`PaymentSyncStripe.execute_sync`, §8) — create / update /
   cancel the monthly subscription to match the bucket, with the explicit
   `proration_behavior`.
6. **Write back** (`PaymentSyncWriteback.write`, §8) — persists the **full
   sync-owned state** in one place: per-membership Stripe line id + next_due_date
   + `stripe_sync_status = 'applied'` (mapping the live items → rows by price),
   the coupon links (+ `applied` on the applied-discount rows), `deleted` on
   cancelled rows confirmed gone from the live sub, the parent's sub id, and the
   post-discount price totals (it composes `PriceWriteback` for the last).

Returns **`None`** — the sync writes everything it owns back to the DB; callers
read the DB (the `applied` status) to confirm it landed, and use
`preview_update_payments_recurring` for the invoice figures.

---

## 4. The read path — parent / family / memberships / snapshots

### Parent resolution is a shared service (`BillingParentResolver`)

The paying-parent + gym-account lookup lives in **`BillingParentResolver`**
(`src/shared/billing_parent_resolver.py`), a DI-registered shared service — the
one place that lookup lives, so every billing-touching service depends on it
rather than re-running the query. The `ParentProfile` model lives in
`src/shared/billing_parent.py` and `resolve_parent.sql` in `src/shared/sql/`.

| method | returns | what it does |
| --- | --- | --- |
| `resolve_parent(member_id)` | `ParentProfile` | follow `account_linked_to_id` **once** (single-level hierarchy) to the paying parent; raise if no profile or no `stripe_customer_id` (`resolve_parent.sql`) |
| `resolve(member_id)` | `(ParentProfile, stripe_account_id)` | `resolve_parent` **then** `GymStripeService.get_stripe_account_id(gym_id)` — the one call the sync's step 1 makes |

`PaymentSyncService` injects this resolver as `_parent`. The old
`PaymentSyncService.resolve_parent` delegate is **removed** — callers that need
parent resolution (e.g. `member_memberships_start`) inject `BillingParentResolver`
directly. (`PaymentSyncQueries.resolve_parent` also no longer exists.)

`resolve_parent.sql` reads **`member_billing_profile`** (a `security_invoker` view
over `members` exposing the billing columns incl. `account_linked_to_id`) and
self-joins it via `COALESCE(account_linked_to_id, member_id)` so a parent resolves
to itself and a child resolves up one level.

### `PaymentSyncBuilder.build_sync_params` — the pure read + build half

`build_sync_params(parent, stripe_account_id)` lives on the **`PaymentSyncBuilder`**
sub-service (`payment_sync_builder.py`) — the **pure desired-state derivation** (no
CRM or Stripe writes) shared by the real and preview paths. The parent + gym
account are **resolved upstream and passed in** — the builder does not resolve
them. It reads via `PaymentSyncQueries`, groups by price, delegates discount
resolution, and assembles the bucket:

| step | how | SQL |
| --- | --- | --- |
| **family ids** | parent + every child whose `account_linked_to_id = parent` in that gym | `get_family_ids.sql` |
| **active memberships, each with its discounts** | `get_active_memberships(family_ids, today)` makes **one call**: `plan_type = 'recurring' AND cancel_date IS NULL` on **`member_memberships_unfiltered`** — the engine reads the **unfiltered** base so **pending rows (`stripe_item_id IS NULL`, the just-inserted adds) are visible**; excludes `deleted` / `preview_*` sync statuses — joined to plan + price; then reads the family's **active** applied discounts and **attaches each membership's discounts onto its `ActiveMembershipRow.discounts`**. | `get_active_recurring.sql` + `get_applied_discounts_by_member.sql` |

`get_family_ids.sql` reads the same `member_billing_profile` view. The
applied-discount read joins the **unfiltered** base tables
(`member_membership_applied_discounts_unfiltered`, `gym_discount_values_unfiltered`)
at service-role — half-synced rows with no `stripe_coupon_id` yet must still be
visible to the sync that resolves them (the filtered client view hides those). It
also binds `:today` (the gym-timezone date) and keeps only discounts with
`end_date IS NULL OR end_date > today` — **the date-lifetime cutoff lives in the
query, not in code**: an ongoing discount past its end date, or a consumed `once`
(whose `end_date` the pre-sync settle stamped), is simply absent from the read, so
the math downstream sees only active discounts.

The builder then **groups the memberships by `price_id`** into
`dict[price_id, list[ActiveMembershipRow]]` (`_group_by_price`), hands that to
`PaymentSyncDiscounts.resolve` (§7 — returns a `ResolvedDiscounts`), and
**assembles the bucket** (`_build_bucket`): one desired item per price group,
quantity = number of memberships on the line, discounts = that price's resolved
coupons. There is no separate flat "snapshots" list threaded alongside the
bucket — discounts ride the membership rows and the coupons ride the bucket items.

### Desired state is the DB — no cancel filter, no add resolution

The desired memberships are **exactly the active rows the read returns** — there
is nothing to filter or resolve. `get_active_recurring.sql` already excludes
cancelled rows (`cancel_date IS NULL`), so what we want to bill is whatever is
active in the DB *right now*. Because a cancel caller writes `cancel_date` to the
DB **before** calling the sync, the cancelled membership is simply absent from
this read — there is no in-memory cancel filter to key on `(member_id, plan_id)`,
and no `add_ids` to map to intervals (a new membership row already carries its own
interval/price). The thing we deliberately **don't** want here is an imperative
delta layered on top of the DB read: the DB is the single source of desired
state, full stop.

---

## 5. The builder service (`PaymentSyncBuilder`) — group by price + assemble the bucket

`payment_sync_builder.py` is the **`PaymentSyncBuilder`** sub-service (DI:
`db_pool` + `PaymentSyncDiscounts`). Its public `build_sync_params` (§4) does the
read + orchestration; the rest is two pure private helpers — no loose module
functions:

- **`_group_by_price(memberships)`** — group the active `ActiveMembershipRow`s
  into `dict[price_id, list[ActiveMembershipRow]]`. All recurring plans are
  monthly (DB `recurring_must_be_monthly` constraint), so the price is the only
  consolidation axis: each `price_id` is one subscription line whose quantity is
  the number of memberships on it. Grouping happens **on the membership rows**
  (each carrying its own discounts), *before* desired items exist — so the
  discount service sees the raw per-member discounts of each consolidated line.
- **`_build_bucket(groups, coupons_by_price, existing_sub_id)`** — one
  `PaymentsSubscriptionDesiredItem` per price group: `stripe_price_id` +
  `stripe_item_id` from the group's first row, `quantity = len(group)`,
  `discounts =` that price's resolved coupons
  (`coupons_by_price.get(price_id, [])`). Wrap into one monthly `IntervalBucket`.

Between those two, `build_sync_params` calls `PaymentSyncDiscounts.resolve(groups,
account, today)` — **all** the discount math + coupon find-or-create lives there
(§7), not in the builder. The builder only groups and assembles.

> **The percent÷quantity split is the consumer side of the
> `discounts-guide` percent×quantity fix.** *Why* a 10%-off-1-of-2 must become
> 5%-on-the-quantity-2-line is owned by `discounts-guide` §4. The engine applies
> it in `PaymentSyncDiscounts._aggregate_line_values` (§7), averaging the
> per-membership effective fractions across the consolidated quantity.

---

## 6. The pre-sync once-discount settle (`PaymentSyncOnceDiscounts`)

`once`-consumption finalization is a **standalone DI service**,
`PaymentSyncOnceDiscounts` (`payment_sync_once_discounts.py`), that runs as a
**pre-sync phase** (step 3 of §3) — before the bucket is built. Its job: settle
the DB so the convergence reads a DB already in the state it should be in and
the planner needs no live-Stripe read. It also *is* the scheduled reconciler's
once-finalization duty, which is why it stands alone for reuse (§10).

`sync_once_discounts(parent, stripe_account_id)` does:

1. **Query the candidates** — `get_unconsumed_once_discounts(family_ids)` (SQL
   `get_unconsumed_once_discounts.sql`) returns the family's `once` discounts that
   are **unconsumed** (`end_date IS NULL`) **and attached** (`stripe_coupon_id IS
   NOT NULL`), joined to the value version for the mode → a list of
   `OnceDiscount(applied_discount_id, stripe_coupon_id)`. A `once` with no coupon
   yet is excluded (never attached ⇒ can't be consumed). No candidates → no-op.
2. **Read the live coupon set** — `_current_coupon_ids` (moved here from the
   service) reads the live subscription and unions `sub.discounts` + every
   `item.discounts` (both `list[str]` of coupon ids on
   `PaymentsSubscriptionResponse`). Empty when there is no existing sub — a
   brand-new sub has invoiced nothing, so every `once` is still pending.
3. **Set math to find consumed coupons** — `{d.stripe_coupon_id for d in
   once_discounts} - current_coupon_ids`: a candidate coupon **missing** from the
   live set means Stripe already invoiced it (a `once` coupon vanishes after its
   one use) ⇒ consumed. No consumed coupons → no-op.
4. **Map consumed coupons back to ids** — `[d.applied_discount_id for d in
   once_discounts if d.stripe_coupon_id in consumed_coupons]`. A coupon can be
   shared by several same-value `once` discounts, so one consumed coupon can stamp
   several rows.
5. **Batch-stamp** — `mark_once_consumed(applied_discount_ids, today)` stamps
   every consumed row's `end_date` in **one** statement (`mark_once_consumed.sql`,
   `WHERE applied_discount_id = ANY(:applied_discount_ids) AND end_date IS NULL` —
   idempotent on re-run).

**Why the live read exists at all:** "has Stripe already invoiced this `once`
coupon?" can only be answered by Stripe (Stripe owns outcomes). Doing it as a
pre-sync settle — set math over the whole candidate set, one batch write — is the
thing we want, rather than the per-row predicate the convergence used to run
inline: the convergence stays a pure date-driven function and the once-truth is
established once, up front. This is the read half `PaymentRefactor.md` §4 calls
out as the gap the old push-only `execute_sync` left open. (The
lifecycle/status-absorption half — Stripe-cancelled-by-dunning — is still future
work in the reconciler, §10.)

---

## 7. The discount service (`PaymentSyncDiscounts`) — math + coupons + links

`PaymentSyncDiscounts` (`payment_sync_discounts.py`) owns **all** the discount
math and the coupon resolution. `resolve(groups, stripe_account_id, today)` takes
the price-grouped memberships (from the builder, §5) and returns a
**`ResolvedDiscounts`** (`coupons_by_price` + `links`). For each price line:

1. **Aggregate the line's values** (`_aggregate_line_values`, the math below) → at
   most one `once` value and one `ongoing` value, each a percent **or** a dollar.
2. **Order dollar before percent**, then **find-or-create one coupon per value**
   (`PaymentSyncCoupons.find_or_create`) on the gym's Connect account. The ordered
   coupons become `coupons_by_price[price_id]` —
   `[SubscriptionItemDiscount(coupon=cid) …]` — and Stripe applies them in attach
   order (dollar→percent).
3. **Record the links** — every `applied_discount_id` in the value's
   `contributing_ids` maps to that value's coupon in `links`. Per-value: a `once`
   value's coupon lands on the `once` rows, an `ongoing` value's on the `ongoing`
   rows — so the `once` presence handle the next pre-sync settle reads stays
   exact. The **real** path writes these links back via
   `set_applied_discount_coupon_id` (→ `set_applied_discount_coupon_id.sql`,
   service-role, unfiltered base table); preview skips this link writeback.

The builder attaches `coupons_by_price` onto the bucket items; the orchestrator
writes `links` back after `execute_sync`. `resolve` does **no DB writes** (so
preview is discount-aware safely) and **no live-Stripe read** — consumption was
already settled upstream (§6) and dropped here by `end_date`.

### The discount math (`_aggregate_line_values`)

The discounts reaching the math are **already date-filtered by the read** (§4):
the applied-discount query excludes any whose `end_date <= today` (the
gym-timezone today) — that is how the engine enforces the arbitrary end dates
Stripe can't express **and** how a consumed `once` (the pre-sync settle, §6,
stamped its `end_date`) drops out. So the math is **pure aggregation, no date
logic** (`_is_past_end_date` no longer exists — the filter lives in SQL). For one
consolidated line (a price group of memberships), per discount mode (`once` /
`ongoing`, kept separate — different Stripe durations):

1. **Per-membership-sequential percent, averaged across the line.** Within one
   membership, percents compound **multiplicatively**: `eff = 1 − Π(1 − pⱼ/100)`
   (30% then 20% → 0.44, not 0.50). The per-membership effective fractions are
   **summed across the line** then divided by the line quantity:
   `line_percent = (Σ effᵢ / qty) × 100`. A membership with no discount contributes
   0, so a partly-discounted line averages correctly.
2. **Dollars summed.** A mode's fixed-dollar offs are summed across the line's
   memberships (a fixed-dollar coupon applies to the whole quantity-N line).

Dollar vs percent are **never** combined into one value — they become separate
coupons (Stripe sequences them dollar→percent via attach order); the math is only
the percentage-level compounding/averaging + the dollar sum. Each value carries the
`applied_discount_id`s of the same-mode discounts that fed it (`contributing_ids`)
— its writeback set. **No DB or Stripe calls** in the math.

### `PaymentSyncCoupons` — deterministic ids, validate-or-replace, no registry table

`PaymentSyncCoupons` owns only the **id scheme + validate-or-replace policy**. It
**never touches the Stripe SDK** — every coupon find / create / delete is
delegated to **`PaymentsStripeDiscountService`** (the single payments-layer owner
of Stripe coupon I/O). This is a hard rule for the whole engine: *no service under
`payment_sync/` calls the Stripe SDK directly* — coupon I/O goes through the
discount service, subscription/invoice I/O through the subscription service (§1).

Coupons are **computed at sync, never pre-baked**. Each line value maps to one
Stripe coupon by a **deterministic id** that is a pure function of the value:

| value | coupon id (`PaymentSyncCoupons.coupon_id`) |
| --- | --- |
| percent | `pct_<bps>_<mode>` where `bps = round(percentage_off * 100)` (basis points) |
| dollar | `amt_<cents>_<mode>` where `cents = int(dollar_off or 0)` |

`<mode>` is the `DiscountMode` value (`once` / `ongoing`). **We set this id
ourselves** — Stripe lets you supply your own coupon `id` on create (an arbitrary
string up to 200 chars; if you omit it Stripe generates a random one). It is
**not a UUID** and not Stripe-generated: it *is* the value signature, mirrored
into `name` too. Because the id is a pure function of the value, **the same value
always resolves to the same coupon** — that is what makes find-or-create
**idempotent**: `find_or_create` calls `PaymentsStripeDiscountService.find_discount`
(retrieve-by-id, returns `None` if absent) first; `create_discount` passes the
deterministic id and is **itself idempotent** — a concurrent create of the same
value collides on Stripe's side and the service catches it and returns the
existing coupon. One coupon per distinct value+mode is **reused across every
member** on the gym's Connect account — **no coupon registry table** is needed.

**Validate-or-replace (the id alone is not trusted).** A coupon's value is
**immutable** on Stripe, and the id only *names* the intended value — the coupon
object under that id could have drifted (hand-edited in the dashboard, or written
by older math). So when `find_discount` returns an existing coupon,
`find_or_create` **validates** its stored `percentage_off` / `amount_off` **and**
`duration` against the value (`_matches_value`): a match is reused; a mismatch is
**deleted** (`PaymentsStripeDiscountService.delete_discount`) and recreated with
the correct value under the same id. This self-heals a corrupted coupon gym-wide —
every member on that value picks up the corrected coupon on their next sync.
(Deleting a coupon does not retroactively strip it from subscriptions that already
applied it; those correct themselves on their own next sync, when the recreated
coupon is re-attached.)

Mode → Stripe duration (`_MODE_TO_STRIPE_DURATION`): `once` → Stripe **`once`**
coupon; `ongoing` → Stripe **`forever`** coupon. Stripe has no native arbitrary
end date, so an ongoing coupon is always `forever` on Stripe and the `end_date`
cutoff is enforced by **the read** — the applied-discount query (§4) excludes a
discount once its `end_date` passes. Percent coupons round to 2 decimals (Stripe's
`percent_off` limit); dollar coupons set `amount_off` (integer cents) +
`currency = "usd"`. No `crm_discount_id` / metadata back-reference: a value-coupon
is shared across every discount at that value, made on the spot — so there is
nothing to back-reference.

> **Discount *semantics* live in `discounts-guide`.** The meaning of `once` vs
> `ongoing`, the lifetime spec (duration-span XOR explicit `end_date`), and the
> applied-discount model are owned there. This section documents only how the
> engine *resolves* an applied discount into a coupon and writes the result back.
> The low-level Stripe coupon create/find/delete primitives live in
> `PaymentsStripeDiscountService` (`payments-guide`).

---

## 8. `execute_sync` + freeze + price writeback

### `execute_sync` (`payment_sync_stripe.py`)

`PaymentSyncStripe` is now **create / update / cancel only** — the freeze ops moved
out to `PaymentSyncFreeze` (below), so its class and module docstrings describe it
as the subscription-lifecycle dispatcher, not a freeze handler.
`PaymentSyncStripe.execute_sync` dispatches off the bucket:

- **bucket has items** → `_sync_bucket`: **update** if `existing_sub_id` is set,
  else **create**. The `proration_behavior` is an **explicit param** threaded from
  `update_payments_recurring` (`"none"` / `"always_invoice"`, default `"none"`) —
  passed straight to both the create and update Stripe requests — the caller
  chooses `proration_behavior` **explicitly**, never inferred from a per-item
  flag. Every subscription carries `StripeSubscriptionMetadata(member_id,
  gym_id)`. `pay_first_invoice_out_of_band` only applies on **create**, and the
  out-of-band first-invoice path triggers only when `proration_behavior ==
  "always_invoice"`.
- **empty bucket + existing sub** → **cancel** the subscription.
- **empty bucket + no sub** → `None` (nothing to do).

Sub-operation **idempotency keys are suffixed** off the base key:
`:sub_create`, `:sub_update`, `:sub_cancel`. The `:freeze` / `:unfreeze` suffixes
now live in `PaymentSyncFreeze`, off the same base key. The create/update/cancel
calls themselves are `payments-guide` primitives.

### Freeze — the standalone `PaymentSyncFreeze` service

Freeze is `pause_collection`, and it is now its own DI service,
**`PaymentSyncFreeze`** (`payment_sync_freeze.py`) — extracted out of
`PaymentSyncStripe`. It is **DB-first and minimal**:
`sync_freeze_state(parent, stripe_account_id, *, idempotency_key) -> bool`
converges Stripe purely from **`parent.is_frozen`** (the DB freeze window on
`ParentProfile`): frozen in the DB → pause collection (with the parent's
`freeze_end_date` as the resume date), otherwise → resume. There are **no
explicit `freeze_end_date` / `unfreeze` flags** and **no DB writes** here — the
freeze-date DB write happens *elsewhere*, in the freeze/unfreeze request handler,
before this service is called. Freeze is a standalone subscription-level pause,
independent of the membership sync, so there is no freeze-vs-membership-change
conflict to validate.

Two callers:

- **The explicit freeze/unfreeze request** writes the freeze window to the DB,
  then calls `sync_freeze_state` **directly** with the resolved parent.
- **The main sync** calls it for a **maintenance re-apply** (step 2 of §3) with the
  parent it already resolved — no extra read — so a membership change on a frozen
  account keeps `pause_collection` in the correct billing order.

No-op (returns the DB state) when there's no `stripe_sub_id`. **Idempotent**
(re-freezing updates the resume date; unfreezing a non-paused sub is a Stripe
no-op) and it lets `PaymentsResourceNotFoundError` **propagate** — a missing sub
when the CRM expects billing is an out-of-sync state that must surface.

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

## 9. Preview = discount-aware + settles, but no convergence writeback

`preview_update_payments_recurring(member_id, proration_behavior="none")` resolves
the parent + gym account (`BillingParentResolver.resolve`) and runs the **exact
same** `PaymentSyncBuilder.build_sync_params` (family, memberships-with-discounts,
group by price, discount resolution, bucket — all DB-derived, no add/cancel
inputs) as the real path, then calls `PaymentSyncStripe.preview_execute_sync` —
Stripe's invoice **preview**, never a mutation.

- **Discounts ARE resolved.** The shared build runs `PaymentSyncDiscounts.resolve`,
  which find-or-creates the deterministic coupons (idempotent, gym-wide) and
  attaches them to the bucket, **so the preview total reflects discounts**.
- **The once-settle DOES run; the convergence writeback + freeze do NOT.** Preview
  runs the same `PaymentSyncOnceDiscounts.sync_once_discounts` as the real path — it
  stamps a consumed `once`'s `end_date`, a settled fact (Stripe already invoiced it),
  not a hypothetical, so the preview reflects it dropping off. What a dry run skips is
  the **freeze re-apply** (it pauses billing) and the **convergence writeback** (the
  per-row line id / sync status, the coupon-link writeback, the sub-id write, and the
  price writeback) — none of the sync's *desired-state* results are persisted and no
  subscription is created / updated / cancelled. So the real-vs-preview boundary is
  the **convergence writeback + freeze**, not the settle or the discounts.

`preview_execute_sync` mirrors `execute_sync`'s dispatch (`preview_update_…` for an
existing sub, `preview_create_…` for a new one), threads the explicit
`proration_behavior`, and returns `None` for a pure cancellation or no-op — there's
no upcoming invoice to preview. Freeze/unfreeze is intentionally unsupported in
preview (a `pause_collection` change produces no invoice). The idempotency key is a
throwaway `uuid4()` (preview writes nothing, so the key is unused downstream — it
only satisfies the shared request schema).

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
for it — **and step 1 already built the two pieces the reconciler's once-and-
resolve duties reuse**: `PaymentSyncOnceDiscounts` is the once-finalization duty
factored out so the sweep can call it directly (its docstring names this), and
`BillingParentResolver` is the shared resolution it leans on. The genuinely
**new** work that remains is the **Stripe→CRM outcome-absorption** half:
`execute_sync` only pushes CRM-derived state, so a naive sweep won't detect a
Stripe-dunning cancellation (it would just error and leave the CRM stuck on
"active"). The reconciler needs the conflict-resolution rule from
`PaymentRefactor.md` §4 — **config drift → CRM wins** (push), **lifecycle/outcome
drift → Stripe wins** (absorb, never re-bill) — plus a compare-and-skip-if-equal
guard so an hourly sweep isn't pointless Stripe writes.

---

## 11. Engine gotchas

- **Pending (just-inserted) rows ARE now visible — DB-first start works.** A new
  membership is inserted with `stripe_item_id IS NULL`; `get_active_recurring.sql`
  reads `member_memberships_unfiltered`, so that pending row is in the desired set,
  the sync creates its Stripe line, and `PaymentSyncWriteback` stamps the line id /
  next_due_date / `applied` status back. (The start caller no longer extracts the
  Stripe response — it inserts, calls the param-less sync, and the writeback
  persists everything.) The client-facing `member_memberships` view still filters
  `stripe_item_id IS NOT NULL` + hides `preview_*`, so pending/preview rows never
  surface to clients — only the engine's unfiltered read sees them.
- **Idempotency keys are suffixed per sub-operation** (`:sub_create`,
  `:sub_update`, `:sub_cancel` in `PaymentSyncStripe`; `:freeze` / `:unfreeze` in
  `PaymentSyncFreeze`) off one base key, so the several Stripe calls in one sync
  don't collide. `bulk_payment_sync` mints a fresh `uuid4()` per member (each
  member's sync is independent).
- **Desired state is the DB read, never a delta** (§4) — there is no cancel
  filter and no add list; a cancel caller writes `cancel_date` first, so the row
  is simply absent from `get_active_recurring.sql`. Don't reach for a
  `(member_id, plan_id)` filter that no longer exists.
- **Coupon swap when consolidated quantity changes.** Adding/removing a family
  member shifts the `÷ quantity` split, producing a different effective percent →
  a different deterministic coupon id → the line **swaps** to the new coupon. A
  pending `once` re-divides correctly on swap; an absolute `end_date` is invariant
  under swaps (the swap changes the coupon's value, never its end — the
  swap-invariance rationale is owned by `discounts-guide`).
- **`PaymentSyncOnceDiscounts._current_coupon_ids` returns empty for a brand-new
  sub** — so the pre-sync settle (§6) treats every `once` snapshot as pending on
  first sync (correct: nothing's been invoiced yet). This live-coupon read lives
  in the once-discount service now, not in the convergence.
- **`bulk_payment_sync` swallows per-member errors** —
  `PaymentsResourceNotFoundError` and any `Exception` are logged at ERROR and the
  loop continues, so one member's broken Stripe state doesn't abort the batch.
- **Price writeback never raises** — Stripe is authoritative; a failed mirror is
  re-corrected by the next mutation or the reconciler.

---

## Key files (where the engine actually lives)

- **Orchestrator:**
  `FastApiBackend/src/member_memberships/service/payment_sync/payment_sync_service.py`
  (`PaymentSyncService` — `update_payments_recurring` (**`-> None`**),
  `preview_update_payments_recurring`, `bulk_payment_sync`; injects `_parent` /
  `_freeze` / `_once_discounts` / `_builder`, builds `_stripe` / `_writeback`).
- **Writeback:** `payment_sync_writeback.py` (`PaymentSyncWriteback.write` →
  `_apply_membership_rows` / `_mark_removed_deleted`; per-row line id /
  next_due_date / `applied`, coupon links + status, `deleted` on removed rows, sub
  id, and prices — composes `PriceWriteback`). New writeback SQL:
  `apply_membership_sync.sql`, `get_cancelled_recurring.sql`,
  `mark_membership_deleted.sql`.
- **Shared parent resolver:** `src/shared/billing_parent_resolver.py`
  (`BillingParentResolver` — `resolve_parent`, `resolve`) + the `ParentProfile`
  model in `src/shared/billing_parent.py`. DI-registered; used by the sync, the
  freeze service, the once-discount service, and (to be migrated) every other
  resolve_parent caller.
- **Freeze service:** `payment_sync_freeze.py` (`PaymentSyncFreeze.sync_freeze_state`
  → `_freeze` / `_unfreeze`) — DB-first, converges `pause_collection` to
  `parent.is_frozen`.
- **Once-discount settle:** `payment_sync_once_discounts.py`
  (`PaymentSyncOnceDiscounts.sync_once_discounts` → `_current_coupon_ids`) — the
  pre-sync once-consumption finalize + the live-coupon read.
- **Builder service:** `payment_sync_builder.py` (`PaymentSyncBuilder` —
  `build_sync_params` → `_group_by_price` / `_build_bucket`; reads the DB, groups
  by price, delegates to the discount service, assembles the bucket).
- **Discount service:** `payment_sync_discounts.py` (`PaymentSyncDiscounts` —
  `resolve` → `_aggregate_line_values`; owns the discount math + coupon
  find-or-create, returns `ResolvedDiscounts`; the date-lifetime filter lives in
  the read, not here).
- **Read/write queries:** `payment_sync_queries.py` (`PaymentSyncQueries` —
  `get_family_ids`, `get_active_memberships` (+ private `_get_discounts_by_item`),
  `get_unconsumed_once_discounts`, `set_applied_discount_coupon_id`,
  `mark_once_consumed`, `update_profile_sub_id`).
- **Coupons (policy only):** `payment_sync_coupons.py` (`PaymentSyncCoupons` —
  `coupon_id`, `find_or_create`, `_matches_value`, `_delete`,
  `_build_create_request`; the deterministic-id + validate-or-replace policy,
  delegating all Stripe coupon I/O to `PaymentsStripeDiscountService` — no Stripe
  SDK import).
- **Stripe dispatch (create/update/cancel):** `payment_sync_stripe.py`
  (`PaymentSyncStripe` — `execute_sync`, `preview_execute_sync`, `_sync_bucket`).
- **Price writeback:** `price_writeback.py` (`PriceWriteback.sync_prices_from_stripe`).
- **Intermediate models:** `member_memberships/schema/payment_sync_schema.py`
  (`ActiveMembershipRow` (carries `discounts`), `AppliedDiscount`, `OnceDiscount`,
  `IntervalBucket`, `LineDiscountValue` (bounds + percent-XOR-dollar validators),
  `ResolvedDiscounts`, `SyncParams`). `ParentProfile` now lives in
  `src/shared/billing_parent.py`.
- **SQL (`src/shared/sql/`):** `resolve_parent.sql`. **SQL
  (`member_memberships/sql/payment_sync/`):** `get_family_ids.sql`,
  `get_active_recurring.sql`, `sync_prices_by_plan.sql`,
  `sync_profile_monthly_total.sql`, `update_profile_sub_ids.sql`,
  `update_stripe_item_id.sql`. **SQL (`…/sql/applied_discounts/`):** the
  applied-discount read `get_applied_discounts_by_member.sql`, the once-candidate
  read `get_unconsumed_once_discounts.sql`, and the writebacks
  `set_applied_discount_coupon_id.sql` + `mark_once_consumed.sql` (the
  apply/remove SQL in this folder is owned by `discounts-guide`).
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
