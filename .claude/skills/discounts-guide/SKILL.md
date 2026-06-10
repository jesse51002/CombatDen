---
name: discounts-guide
description: >-
  The single source of truth for how CombatDen membership discounts work — the
  three-table model (discount IDENTITY + versioned immutable VALUE rows + slim
  applied-discount rows that pin a membership to a value version), item-scoped
  (per-membership) discounts, linked/family discounts as real version-backed
  discount entries a plan references by id, and coupons computed at build then
  written back to Stripe. Load this whenever you touch
  anything discount-shaped: gym_discounts / gym_discount_values, the
  member_membership_applied_discounts rows, the apply/remove path
  (MemberMembershipsDiscounts), the build-time coupon computation
  (PaymentSyncDiscounts / PaymentSyncCoupons), the once/ongoing lifetime +
  end_date, the per-membership-sequential percent math, or the CRM discount UI.
  Trigger on "discount", "coupon", "discount version", "apply a discount",
  "once vs ongoing", "end_date", "percent off / dollar off", "why did this
  member's bill change", or any change to the discount data model, endpoints, or
  sync logic.
---

# Discounts — the versioned, immutable model

This is the deep domain knowledge for CombatDen's membership discounts. It is the
**source of truth** for how the system behaves; CLAUDE.md holds only the "how to
work here" rules. This skill *is* the discount design rationale — there is no
separate prose doc for it (`FastApiBackend/PaymentRefactor.md` is only the
engine's remaining-work roadmap). When the discount model changes, **update this
skill in the same change** (it is a living document — see the bottom).

The **#1 goal is predictability:** a member's billing changes **only** via an
explicit add/remove on *that* member's specific membership, and everything
discounted is visibly tied to one membership / Stripe item. You can look at a
member and see exactly what is and isn't discounted, with no cross-member spooky
action and no preset edit silently re-billing dozens of people.

---

## 1. Three tables: identity, versioned values, applied discounts

The discount system mirrors the **plans / prices** pattern
(`membership_plans` + `membership_plan_prices`, documented in `memberships-guide`):

1. **`gym_discounts`** — the **IDENTITY**: `discount_id`, `gym_id`,
   `discount_name` (editable), `discount_type` ∈ `preset | custom | linked`, `is_deleted`.
   No values. Plain gym config (NOT Stripe-gated).
2. **`gym_discount_values`** — **versioned, truly immutable VALUE rows**, exactly
   like `membership_plan_prices`: `value_id` (PK / the version tag),
   `discount_id`, `gym_id`, `percentage_off` *or* `dollar_off` (exactly one),
   `discount_mode` (`once`/`ongoing`), the lifetime spec (`duration_amount` +
   `duration_unit` XOR `end_date`), `is_active`, `created_at`. A value row is
   **never updated or touched** — the table is **service_role-write-only**
   (clients get SELECT only). To change a discount's value the backend **inserts
   a NEW active version and flips the prior one's `is_active`** (a partial unique
   index enforces ≤1 active per discount). The value columns are never mutated
   and versions are never deleted — a permanent paper trail referenced by applied
   discounts.
3. **`member_membership_applied_discounts`** — the **slim applied-discount row**:
   one row = one membership (`item_id`) pinned to one immutable value version
   (`value_id`). The Stripe-gated half (holds the written-back
   `stripe_coupon_id` + the `stripe_sync_status` confirmation).

**Apply = INSERT** an applied-discount row referencing the discount's **active**
`value_id`. **Remove = DELETE** that row. **Never edit.** A preset already applied
is left **pinned** (never re-resolved). To change a member's discount you remove
the row and add another.

**Why this is the predictability guarantee:** editing a discount mints a NEW
version; existing applied-discount rows still point at their OLD `value_id`, so
they are untouched — an edit affects only *future* applications. "What discount
does this member have, and which exact version" is a local, history-accurate fact
you can prove from `value_id`. (The thing we never want: an edit fanning out to
silently re-bill every holder.)

### Applied-discount columns (`member_membership_applied_discounts`)

`Database/supabase/schemas/member_membership_applied_discounts.sql`:

| column | meaning |
| --- | --- |
| `applied_discount_id` | PK |
| `item_id` | FK → the membership (`member_memberships_unfiltered`, the Stripe item) |
| `member_id`, `gym_id` | scope |
| `value_id` | FK → `gym_discount_values_unfiltered` — **the version tag / provenance** (reach name/type/value via value → discount) |
| `end_date` | resolved absolute end (sync writeback; see §5) |
| `stripe_coupon_id` | the coupon the sync resolved (sync writeback; the `once` tracking handle) |
| `stripe_sync_status` | Stripe-sync confirmation (`not_added` default → `applied` once live on Stripe / `deleted` when removed / `preview_*` staging). `NOT NULL`. |
| `created_at` | |

The percent/dollar + mode + lifetime are **not** copied onto the applied-discount
row — they live on the referenced `gym_discount_values` row, reached by
`value_id → gym_discount_values → gym_discounts`. That join *is* the provenance:
you can always prove which version a member is on, and the full version history
per discount is queryable (`WHERE discount_id = … ORDER BY created_at`).

### Immutability is user-only, not system-only

Every applied-discount column is user-immutable via the column guard
(`MEMBER_MEMBERSHIP_APPLIED_DISCOUNTS` in
`Database/python_data/schema/immutable_columns.py`). The **system**, at
service-role, legitimately writes back the **outcome** fields during sync:
`stripe_coupon_id` (the resolved coupon), `end_date` (stamped when a `once`
discount is consumed), and `stripe_sync_status` (`applied` once the row is live on
Stripe, `deleted` when removed). That is why the applied table is the
**Stripe-gated half**: an unfiltered base
(`member_membership_applied_discounts_unfiltered`, what the sync reads) + a
`security_invoker` filtered view that exposes only rows the sync has confirmed
live — `WHERE stripe_sync_status NOT IN ('not_added', 'preview_add',
'preview_remove')` — so pending (`not_added`) and preview-staging rows never reach
the CRM; INSERT/UPDATE are revoked for `authenticated`. The value rows, by
contrast, are immutable *by version* (REVOKE the value columns; only `is_active`
flips).

---

## 2. Item-scoped — every discount is tied to one membership

There are **no person-level / floating discounts.** Every applied discount sits
on a specific membership (`item_id` / Stripe item). The CRM renders applied
discounts **grouped under each membership line** so it is exact what's discounted
and what isn't. When in doubt: a discount belongs to a membership, never to a
member-in-the-abstract.

---

## 3. Linked (family) discounts are real discount entries a plan references

A linked/family discount is a **real discount entry like any other** — a
`gym_discounts` identity tagged `discount_type = linked` with a versioned value
on `gym_discount_values`. So it gets **versioning + a stable id to point to**,
exactly like a regular discount.

A **membership plan references its family discounts by id**:
`membership_plans.linked_discount_ids` stores a discount **id per family tier**
(2nd, 3rd, 4th, 5th linked member, in order — capped at 5 members) pointing at
real linked discount entries. The linked-discount **value is entered on the
membership creation/edit screen**, owned by the membership/plan UI — exactly
like a regular discount, each tier is a **$ off or % off value** (not a
"member price"). The CRM sends per-tier `linked_discount_values` (each a
`{percentage_off | dollar_off}`, exactly one set), and the **backend mints a real
`linked` discount entry per value on plan create/update** (reusing
`DiscountsService`) and stores their ids in `linked_discount_ids`. Plan **reads
resolve the ids back to values** (a subquery on `gym_discount_values` building a
`{percentage_off, dollar_off}` object per tier) so the CRM can display/edit them
without ever seeing the linked discounts in the regular preset list. Editing a
value mints a new active version on the same discount, so the stored id stays
stable.

**Applying** a linked discount is the same as any discount: the membership/family
flow passes its id to `add_discounts` (`preset_ids`), which pins an applied-discount
row to the discount's **active** value version. Editing the linked discount mints a new
version, so future family applications get it — like a regular discount. The
`linked` tag keeps it out of the regular per-membership discount picker (which
lists only `preset`); family billing via `members.account_linked_to_id` is
unchanged.

**The thing we never want here:** a cross-member recalculation of discounts.
Recomputing a family-wide assignment on every membership change is what produced
"random-seeming" cross-member price moves and broke predictability. Each
membership's billing is determined from that member's own memberships only.

---

## 4. Coupons are computed at build, then written back (real path only)

*This section is the discount-side summary. The full sync engine — the
`update_payments_recurring` orchestration sequence, the build-time resolution, the
deterministic coupon-id scheme, line consolidation, and the writeback — is
documented in `sync-guide`; the Stripe coupon/subscription primitives it calls are
in `payments-guide`.*

Discounts store **intent**; **no Stripe coupon is pre-baked**. Coupons are
resolved at **build time** by `PaymentSyncDiscounts.resolve`
(`payment_sync/payment_sync_discounts.py`), which the builder calls while
assembling the desired subscription bucket — for **both** the real sync and
preview, so preview reflects discounts. The build reads each family's active
memberships **each carrying its applied discounts**
(`get_active_memberships` → `get_applied_discounts_by_item.sql`, joined to
`gym_discount_values` for the percent/dollar + mode), grouped into consolidated
lines by price. The read is already **date- and status-filtered in SQL** (below),
so the math has no date logic of its own. For each consolidated line (price `P`,
quantity `N`):

1. **Aggregate per line, grouped by `discount_mode`** so `once` and `ongoing`
   never mix (`PaymentSyncDiscounts._aggregate_line_values`): percents compound
   **sequentially within a membership** then average across the line (÷ `N`);
   dollars sum. (Math detail below.)
2. **Find-or-create the coupon** on the gym's Connect account using a
   **deterministic per-account coupon ID** from the value signature
   (`PaymentSyncCoupons.coupon_id`): `pct_<bps>_<mode>` (bps = basis points =
   `round(percentage_off * 100)`) or `amt_<cents>_<mode>`. `PaymentSyncCoupons`
   owns the id scheme + a **validate-or-replace** check (delete + recreate if the
   live Stripe coupon's value/duration drifts from the computed value — Stripe
   coupons are immutable), and **delegates all Stripe coupon I/O** (find / create
   / delete) to `PaymentsStripeDiscountService` — the engine holds **no direct
   Stripe SDK**. Creation passes the id, so a repeat/race collides and is treated
   as "already exists" — idempotent, one coupon per distinct value reused, **no
   coupon registry table.** `once` → a Stripe `once` coupon; `ongoing` → a Stripe
   `forever` coupon (the `end_date` cutoff is enforced by *us*, never by Stripe).
3. **Order percent before dollar** on the line so Stripe sequences percent→dollar
   (the `DISCOUNT_APPLICATION_ORDER` constant — percent-first lets each member's own
   discounted price reconcile to the consolidated line total without rescaling).

`resolve` returns a `ResolvedDiscounts` — the per-price coupon lists the builder
attaches onto the bucket items, plus the `applied_discount_id → coupon_id` links.
The build itself does **no DB writes**.

### The date + status filter lives in SQL (not code)

The applied-discount read excludes anything that must not bill **in the query**,
not in Python:

- **Past its `end_date`** — `end_date IS NULL OR end_date > :today` (`:today` =
  the gym-timezone today). This is how an arbitrary end date — and a consumed
  `once` whose `end_date` the pre-sync settle stamped to today — drops out, by one
  inclusive cutoff (`end_date <= today` ⇒ expired).
- **Wrong `stripe_sync_status`** — `stripe_sync_status::text <> ALL(:excluded_statuses)`;
  the real path excludes all `preview_*`, the preview path keeps `preview_add` and
  drops `preview_remove`.

### The percent math (per-membership-sequential, then ÷ quantity)

Stripe consolidates same-price memberships onto **one line with a quantity `N`**,
and a coupon on that line discounts **all `N` units**. So a discount meant for
some-but-not-all units is scaled to the line:

- **Within one membership**, multiple percents **compound sequentially** — 30%
  then 20% is `1 − (1−0.30)(1−0.20) = 0.44`, not 0.50
  (`eff = 1 − Π(1 − pⱼ/100)`).
- **Across the line**, the per-membership effective fractions **sum**, then divide
  by the quantity: `line_percent = (Σ effᵢ / N) × 100`. A membership with no
  discount contributes 0, so a partly-discounted line averages correctly — e.g.
  one 10%-off membership on a quantity-2 line → `0.10 / 2 = 5%` on the line.
- **Fixed dollars are summed** across the line's memberships (a fixed-dollar
  coupon applies to the whole quantity-`N` line).

Computed from the member's **own** memberships only — deterministic, no
cross-member reshuffle.

### Where the DB writeback happens — real sync only, never preview

After Stripe converges, the **real path** writeback (`PaymentSyncWriteback`)
writes the resolved `stripe_coupon_id` back onto each contributing applied-discount
row and stamps it `applied` (`set_applied_discount_coupon_id.sql`, service-role),
from the links `resolve` returned. The writeback is **per-value** (a value's coupon
is written only onto the same-mode rows that contributed it). **Preview resolves
the coupons** (idempotent, gym-wide find-or-create, so the preview total reflects
discounts) but writes **nothing** back to the DB. So the coupon *resolution* is
shared by both paths; the coupon-id *writeback* is real-sync-only. Intentional.

### Previewing an add or remove — staged, then always cleaned up

Adding and removing are **two separate operations**, `add_discounts(item_id,
member_id, preset_ids, idempotency_key, preview=False)` and
`remove_discounts(item_id, member_id, applied_ids, idempotency_key, preview=False)`
(`MemberMembershipsDiscounts`). Each takes a **`preview` bool**. A preview
must reflect the *proposed* change (not the current bill) yet leave **no permanent
state**, so it **stages** through the `stripe_sync_status` enum:

- **`add_discounts(preview=True)`** inserts the applied-discount rows as **`preview_add`**,
  runs the read-only preview build, then **deletes** them.
- **`remove_discounts(preview=True)`** flips the target rows from `applied` to
  **`preview_remove`**, runs the preview build, then **reverts** them to `applied`.

The build's applied-discount read toggles its `:excluded_statuses` so the preview
sees the proposed world: it **keeps `preview_add` in** (the added discount shows in
the previewed total) and **drops `preview_remove`** (the removed one disappears).
The staging is always undone in a `finally` (a `staged_preview` helper), so a
preview never commits a discount. A real call (`preview=False`) skips all of this —
it inserts/deletes the rows for real and re-syncs.

> **The `preview_remove` race — now closed by the lock.** Flipping a live `applied`
> row to `preview_remove` is read-safe for the preview, but a **concurrent real sync
> also drops `preview_remove`**, so it would scrub the membership's live Stripe line
> (`preview_add` is safe — a real sync ignores it). This is **closed by the
> per-parent lock**: every lifecycle op, including the add/remove-discount preview,
> runs under `PayingMemberLock` (the membership facade wraps it), so no concurrent
> sync on the same family can run during the staged preview.

---

## 5. Lifetime = `once` / `ongoing`; once-consumption tracking

### The lifetime spec (duration span XOR explicit end_date)

On the **value version**, an `ongoing` discount's end is set by **either** a
`duration` span (`duration_amount` + `duration_unit` ∈ **day / week / month** —
the `discount_duration_unit` enum, distinct from `membership_plans`'
week/month/year) **or** an explicit `end_date` — **exactly one, never both**
(CHECK `chk_discount_value_lifetime_exclusive`); **neither = forever.** At
apply-time the applied-discount row's **absolute `end_date` is resolved**
(`_resolve_end_date`: `apply_date + duration` via `relativedelta`, or the explicit
`end_date` copied). `once` discounts leave `end_date` NULL until the sync stamps
it on consumption.

**Why an absolute `end_date`, not a relative month-count (coupon-swap
invariance):** the sync **swaps a percentage's coupon whenever the consolidated
quantity changes** (the `÷ quantity` split shifts). A relative "N months from
start" would **reset its clock on every swap** and overrun; an **absolute
`end_date` is invariant** under swaps. Stripe has no native arbitrary end date,
so **we enforce the cutoff ourselves** by dropping the discount on/after the date.

### `once` consumption tracking (the written-back coupon is the handle)

A `once` discount's whole lifecycle lives in the **sync**, finalized by a
dedicated pre-sync step — `PaymentSyncOnceDiscounts.sync_once_discounts` — that
runs **before** the build so the build reads a settled DB. A just-applied `once`
row has `stripe_coupon_id = NULL` and `end_date = NULL`. The settle reads the live
subscription's **current** Stripe coupons (via
`PaymentsStripeSubscriptionService.get_subscription` — the only thing that can tell
a consumed `once` from a pending one, since Stripe owns billing outcomes):

- **coupon still present on the sub (or NULL)** → still **pending** → the next
  build re-resolves it, and **if the consolidated count changed its computed
  value, the build swaps the coupon and the writeback records the new id.**
- **coupon absent from the sub** (Stripe already invoiced it) → **consumed → done**
  → the settle **stamps `end_date = today`** (`mark_once_consumed.sql`,
  idempotent) and never re-adds it; the `end_date` SQL exclusion handles it from
  then on, so we stop querying Stripe.

So a `once` discount lands on **exactly the next invoice** and is **not**
re-applied on later cycles; changing the count while pending re-divides correctly.

---

## 6. Deferred — open questions (recorded, NOT built)

- **Automatic propagation of a discount edit to existing holders.** Today an edit
  mints a new version and affects only *new* applications (the predictability
  guarantee); existing applied-discount rows stay pinned to their old `value_id`.
  The version linkage exists so a future "re-apply this discount's active version
  to its holders" bulk action *can* find them. Default until then: immutable after
  apply.
- **A possible "same membership type" constraint** to make that auto-update
  edge-case-free. Not decided.
- **Mixed-mode aggregation edge cases on a single consolidated line** — the common
  case (one value per mode) is exact.
- **The scheduled reconciler is a functional dependency, not just a drift
  backstop.** Precise **mid-cycle** `end_date` expiry and `once`-consumption
  finalization on an **idle** member depend on the daily reconciler running the
  sync on its own. Building it is out of scope (see `PaymentRefactor.md` §1).

---

## Key files (where the model actually lives)

- **Schema:** `Database/supabase/schemas/gym_discounts.sql` (identity),
  `gym_discount_values.sql` (versioned values + the `discount_mode` /
  `discount_duration_unit` enums), `member_membership_applied_discounts.sql`
  (slim applied-discount rows + the `stripe_sync_status` enum). Access rules in
  the parallel `access_rules/` files. Linked pricing lives on
  `membership_plans.sql`.
- **Models/enums:** `Database/python_data/schema/gym_discount.py`
  (`DiscountType`, `DiscountMode`, `DiscountDurationUnit`, `GymDiscountCreate`
  identity), `gym_discount_value.py` (`GymDiscountValueCreate`),
  `member_membership_applied_discount.py` (incl. `StripeSyncStatus`),
  `immutable_columns.py` (`GYM_DISCOUNT_VALUES`,
  `MEMBER_MEMBERSHIP_APPLIED_DISCOUNTS`).
- **Preset CRUD (versioned, coupon-free, no cascade):**
  `FastApiBackend/src/discounts/service/` — `discounts_create.py`, `discounts_update.py`, `discounts_delete.py`, `discounts_list.py` (create = identity + first
  active version; update = rename hits identity, value-edit mints a new active
  version; delete = archive `is_deleted`).
- **Apply/remove:**
  `FastApiBackend/src/memberships/service/memberships_discounts.py`
  + its SQL in `.../sql/applied_discounts/` (apply references the active
  `value_id`; regular discounts only).
- **Build-time coupons:** `payment_sync/payment_sync_discounts.py`
  (`PaymentSyncDiscounts` — the discount math `_aggregate_line_values` + `resolve`
  → `ResolvedDiscounts`), `payment_sync_coupons.py` (`PaymentSyncCoupons` — the
  deterministic-id scheme + validate-or-replace, delegating Stripe I/O to
  `PaymentsStripeDiscountService`). The `once` settle is
  `payment_sync_once_discounts.py` (`PaymentSyncOnceDiscounts`); the coupon-id +
  `applied`/`deleted` writeback is `payment_sync_writeback.py`
  (`PaymentSyncWriteback`). Orchestrated by `payment_sync_service.py`
  (`PaymentSyncService`).
- **CRM member billing-detail read:**
  `FastApiBackend/src/members/sql/member_details/member_details.sql` aggregates
  each membership's currently-active applied discounts (filtered
  `member_membership_applied_discounts` view, `end_date IS NULL OR >= CURRENT_DATE`,
  joined to its pinned `value_id` → owning discount) into per-row
  `applied_discounts` JSONB carrying the **full applied-discount shape**
  (`applied_discount_id`, `item_id`, `member_id`, `gym_id`, `value_id`,
  `discount_id`, name/type, percent/dollar, `discount_mode`, `end_date`).
  `member_details/members_billing_grouper.py` (`_collect_plan_discounts`) flattens
  them — **item-scoped, NOT de-duplicated** — onto `BillingMembershipInfo.discounts`,
  reusing the canonical `MemberMembershipsAppliedDiscount` model. The CRM groups
  them under each covered member by `item_id` and removes one by
  `applied_discount_id`, so both fields must be present.
- **Engine roadmap (prose):** `FastApiBackend/PaymentRefactor.md` (the deferred
  reconciler the mid-cycle `end_date` / once-finalization depend on, §1). The
  discount model rationale is **this skill**.
- **Sibling skills:** `memberships-guide` (the plans/prices + `member_memberships`
  that host these applied-discount rows), `sync-guide` (the engine that computes
  the coupons), `payments-guide` (the Stripe coupon/subscription/webhook
  primitives).

---

## This is a living document

This skill is the single source of truth for how discounts work. Whenever the
model genuinely changes — a new column, a changed lifetime rule, the reconciler
getting built, an auto-propagation feature landing, a renamed service or SQL
file — **update this skill in the same change** so it never goes stale.
