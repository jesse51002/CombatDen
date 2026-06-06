---
name: memberships-guide
description: >-
  The single source of truth for CombatDen membership PLANS (the catalog /
  templates) and member MEMBERSHIPS (the per-member instances). Plans are the
  identity-plus-versioned-immutable-price pattern (membership_plans +
  membership_plan_prices, ≤1 active price, edit = deactivate + insert a new
  version, price-version PINNING) mirroring the discounts model; memberships are
  the append-only per-member instance (member_memberships) — one Stripe
  subscription item — with date-driven status, immutability triggers, and a
  filtered view. Load this whenever you touch plan CRUD (DB-first/Stripe-second
  create-with-cleanup, set_price versioning, soft delete, linked-discount
  re-mint, bulk member migration) or a membership lifecycle op (start, cancel,
  freeze, update_price, mark_paid_cash, charge_card, apply discounts) — each of
  which recomputes payment state through the sync. Trigger on "membership plan",
  "plan price", "set price", "active price", "price pinning", "upgrade a member",
  "migrate members", "start a membership", "cancel membership", "freeze",
  "mark paid cash", "charge card", "member_memberships", "membership status",
  "ended vs cancelled vs frozen", or any change to the plan / membership data
  model, services, SQL, or endpoints.
---

# Memberships — plans (templates) and member memberships (instances)

This is the deep domain knowledge for CombatDen's membership **plans** and
member **memberships**. It is the **source of truth** for how these two layers
behave; CLAUDE.md holds only the "how to work here" rules, and
`FastApiBackend/PaymentRefactor.md` §1–§3 holds the prose design rationale
(config-vs-outcomes split, the reconciliation-toward-desired-state engine). When
the model changes, **update this skill in the same change** (it is a living
document — see the bottom).

Three sibling knowledge skills own the seams this doc only points at:
`discounts-guide` owns the applied-discount snapshot model and linked/family
discount semantics; `sync-guide` owns the payment sync engine every lifecycle op
calls; `payments-guide` owns the Stripe primitives (Product/Price/invoice/
customer/card). This doc stays inside plans + memberships and defers the rest.

---

## 1. Two layers: plans are templates, memberships are instances

A **plan** is a gym's catalog template — "Adult Unlimited, $150/mo, recurring."
A **membership** is one member's enrollment on that template — a single row, one
Stripe subscription item (recurring) or one one-time invoice. The two layers are
deliberately decoupled:

| | Plan (`membership_plans` + `membership_plan_prices`) | Membership (`member_memberships`) |
| --- | --- | --- |
| what it is | the template / catalog entry | the per-member instance |
| Stripe object | a Product + a default Price | a subscription item or one-time invoice |
| cardinality | one per offering, shared by many members | one per (member, gym, plan) enrollment |
| mutability | name/duration editable; price is **versioned** | append-only; cancel/end via date columns |
| Stripe-gated | yes (`stripe_product_id` / `stripe_price_id`) | yes (`stripe_item_id`) |

The load-bearing seam between them is **price-version pinning** (§3, §7): a
membership stores a concrete `price_id`, and a plan re-pricing does **not** move
existing members — they stay on their pinned price until an explicit opt-in
upgrade (`update_price`) or a bulk plan migration. This is the same
"editing a template never silently re-bills holders" predictability guarantee
`discounts-guide` describes for discount versions.

---

## 2. `membership_plans` — the identity table

`Database/supabase/schemas/membership_plans.sql`. The plan row is the catalog
identity; the **price lives on a separate versioned table** (§3), so the plan
itself carries no amount.

| column | meaning |
| --- | --- |
| `plan_id` | PK |
| `gym_id` | scope (composite `UNIQUE (plan_id, gym_id)` for downstream composite FKs) |
| `plan_name` | editable; `CHECK (plan_name <> '')` |
| `plan_type` | `trial` / `recurring` / `one_time` (`CHECK plan_type IN (...)`; mirrors `PlanType`) |
| `class_count` | optional, `CHECK class_count > 0` |
| `duration_amount` / `duration_unit` | optional span; `duration_unit IN ('week','month','year')` (the `DurationUnit` enum — week/month/year, distinct from the discount duration unit's day/week/month) |
| `is_public` | shown to members |
| `is_deleted` | soft-delete flag (archive, never hard-delete) |
| `stripe_product_id` | the Stripe Product (the gate column) |
| `waiver_ids` | jsonb array of waiver_id strings (`CHECK chk_plan_waiver_ids_array`: must be a jsonb array) |
| `linked_discount_enabled` | family-discount flag |
| `linked_discount_ids` | jsonb uuid array of real `linked` discount entries (`CHECK chk_plan_linked_ids_array`) — see §4 / `discounts-guide` |
| `created_at` | |

**Named CHECK constraints (verify against the schema, do not invent):**

| constraint | enforces |
| --- | --- |
| `recurring_must_be_monthly` | `plan_type <> 'recurring' OR (duration_unit = 'month' AND duration_amount = 1)` |
| `duration_both_or_neither` | `(duration_amount IS NULL) = (duration_unit IS NULL)` |
| `duration_required_unless_class_count` | a recurring plan needs a duration; otherwise needs duration **or** `class_count` |

These same three are re-checked in Python before any write
(`_check_plan_constraints` in `membership_plans_schemas.py`, called by the
create request's `model_validator` and by update's `_validate_merged_state`), so
a bad merge is rejected before it reaches the DB.

**Filtered view + immutability.** `membership_plans` is a `security_invoker`
view exposing only `stripe_product_id IS NOT NULL` rows; the base table is
`membership_plans_unfiltered`. It is **Stripe-gated and service_role-write-only**:
`INSERT` and `UPDATE` are **fully revoked** from `authenticated` on both the base
table and the view (`access_rules/membership_plans.sql`), so every write goes
through `service_role`. On top of that DB grant, `MEMBERSHIP_PLANS` in
`immutable_columns.py` adds a Python-layer guard that rejects any client payload
carrying `plan_id`, `gym_id`, `created_at`, or `stripe_product_id`. Reads
(`hide_incomplete_stripe_records` restrictive policy) never surface a half-synced
plan.

---

## 3. `membership_plan_prices` — versioned, immutable price rows

`Database/supabase/schemas/membership_plan_prices.sql`. Exactly the
identity/versioned-values split `discounts-guide` describes for
`gym_discounts` / `gym_discount_values`: the plan is the identity, the **price is
a versioned row**, and a re-price **never mutates** an existing price.

| column | meaning |
| --- | --- |
| `price_id` | PK / the version tag a membership pins to |
| `plan_id`, `gym_id` | scope (composite FKs back to the plan) |
| `stripe_price_id` | the Stripe Price (the gate column) |
| `price` | cents, `CHECK price >= 0` |
| `is_active` | the single mutable flag |
| `created_at` | |

- **≤1 active price per plan.** Partial unique index
  `idx_max_one_active_price_per_plan ON (plan_id) WHERE is_active = TRUE` — 0 is
  allowed (no active price), 2+ is rejected.
- **Edit = deactivate + insert.** Re-pricing is `set_price`: deactivate the
  current active row (`membership_plans_price_deactivate_all.sql`, `RETURNING *`)
  and INSERT a fresh `is_active = true` row (`membership_plans_price_insert.sql`).
  The old row is left frozen — a permanent price-version paper trail.
- **Pinning.** A membership references its `price_id` directly. Re-pricing mints
  a new version; existing memberships keep pointing at their old `price_id`, so
  their bill is untouched until they are explicitly upgraded (§7).
- **Filtered view + immutability.** `membership_plan_prices` is the
  `stripe_price_id IS NOT NULL` `security_invoker` view; the base is
  `..._unfiltered`. It is **service_role-write-only** — `authenticated` gets
  SELECT only (INSERT/UPDATE revoked on both table and view). `MEMBERSHIP_PLAN_PRICES`
  in `immutable_columns.py` freezes `price_id`, `plan_id`, `gym_id`, `created_at`,
  `stripe_price_id`.

---

## 4. The plan service

`src/membership_plans/service/plans/`. The facade
(`membership_plans_service.py`, `MembershipPlansService`) delegates to focused
sub-services that all extend `MembershipPlansBase`. Endpoints live on
`membership_plans_router.py`.

**Create — DB-first, Stripe-second, cleanup-on-failure**
(`membership_plans_create.py`, `MembershipPlansCreate.create_plan`):
1. Mint linked discount entries (below), then INSERT the plan row with a NULL
   `stripe_product_id` (`membership_plans_insert.sql`) and the first price row
   with a NULL `stripe_price_id` (`membership_plans_price_insert.sql`).
2. Create the Stripe Product + Price (via `payments-guide`'s membership/price
   services). On any Stripe exception, `_cleanup_pending` hard-deletes both
   pending rows (`membership_plans_delete_pending.sql`,
   `membership_plans_price_delete_pending.sql`, both gated on the Stripe id
   being NULL) and re-raises.
3. Stamp the real ids back with retry (`membership_plans_set_stripe_product_id.sql`,
   `membership_plans_price_set_stripe_price_id.sql`); a DB failure after Stripe
   succeeded raises `StripeOrphanError`. The NULL-id rows are invisible to
   clients (filtered views) until step 3 completes — that is what makes the
   half-built state safe.

**Linked-discount re-mint** (`MembershipPlansBase._mint_linked_discounts`): the
CRM edits family tiers as per-tier *amounts* (`linked_discount_prices`). The plan
service mints one real `linked` discount entry per amount via `DiscountsService`
(tiers numbered from 2 = 2nd family member up) and stores their ids in
`linked_discount_ids`. **The discount model itself is owned by `discounts-guide`**
— this doc only notes the mint-and-store seam. Plan **reads resolve those ids
back to amounts** with a subquery joining `gym_discount_values WHERE is_active`
(`membership_plans_get.sql`, `membership_plans_list.sql`) so the CRM can
display/edit the dollar amounts without ever seeing the linked discounts in the
regular preset picker.

**Update** (`membership_plans_update.py`): collect non-None changes, re-mint
linked discounts if `linked_discount_prices` changed (swapping it for
`linked_discount_ids`), run `validate_mutable_columns(MEMBERSHIP_PLANS, ...)`,
validate the merged state against the CHECKs, push the rename/metadata to Stripe
**first**, then UPDATE the CRM row (`membership_plans_update.sql` with a dynamic
`{set_clause}`; jsonb columns bound as text and cast). Update does **not** change
price — that is `set_price` only.

**Set price** (`membership_plans_price.py`, `MembershipPlansPrice.set_price`):
deactivate the old active price + insert the new active price in one txn, create
the new Stripe Price, stamp its id, then point the Stripe Product's
`default_price` at the new price and archive the old Stripe price (Stripe refuses
to archive a price that is still a product's default). **Existing members keep
their old price** — migration is separate and opt-in.

**Soft delete** (`membership_plans_delete.py`): deactivate the Stripe Product
(tolerating an already-gone product), then `is_deleted = true`
(`membership_plans_delete.sql`). Never hard-deletes; existing memberships keep
referencing the plan.

**Read** (`membership_plans_read.py`): list / get a plan joined to its active
price (`_extract_active_price`) and to resolved linked-discount amounts; the list
SQL also computes `enrolled_count` from `member_memberships_status` where
`status = 'active'`.

**Member migration via bulk sync** (`MembershipPlansPrice.migrate_all_members` /
`migrate_members`): the deliberate, opt-in way to move members onto the current
price. It collects affected `member_id`s (`migrate_all` uses
`membership_plans_get_affected_members.sql` for active members on the plan;
`migrate_members` takes an explicit list) and queues a background
`bulk_payment_sync` through the sync engine. This is the **one** place a
template change fans out to many members — and it is intentional and explicit,
never silent drift (see `PaymentRefactor.md` §6).

---

## 5. `member_memberships` — the per-member instance table

`Database/supabase/schemas/member_memberships.sql`. **Append-only:** once
created, a membership is only ever cancelled/ended via its date columns — never
flipped back to active. Starting again means INSERTing a new row.

| column | meaning |
| --- | --- |
| `item_id` | PK (the Stripe-item identity) |
| `member_id`, `gym_id` | scope (composite FKs to `members`) |
| `plan_id` | the plan (composite FK; immutable, see triggers) |
| `price_id` | the **pinned** price version (FK to `membership_plan_prices_unfiltered`; composite FK `(price_id, plan_id)`) |
| `start_date` | always today at create (future starts unsupported) |
| `end_date` | non-recurring expiry (recurring plans cannot have one — trigger) |
| `cancel_date` | set on cancel; **locks only once the membership is removed from Stripe (`stripe_sync_status = 'deleted'`)** — while the cancel is unconfirmed it stays clearable, which is how a failed cancel reverts (trigger) |
| `last_paid_date` / `next_due_date` | mirrored from Stripe (gym-local dates) |
| `stripe_item_id` | the Stripe subscription item / invoice id (immutable once set — **except while `migrating`**, so a price migration can move the line); never nulled on delete/cancel (historical invoice-line record) |
| `stripe_sync_status` | Stripe-sync confirmation enum (`not_added` default → `applied` / `deleted` / `migrating` / `preview_*`); `NOT NULL`. Drives the client view + the DB-first verify/revert |
| `prorate` | whether the first/changed charge prorates |
| `total_price` | cents, `CHECK total_price >= 0` |
| `created_at` | |

**Triggers (exact names from the schema — what each enforces):**

| trigger | enforces |
| --- | --- |
| `trg_prevent_plan_id_overwrite` | `plan_id` immutable after creation |
| `trg_prevent_cancel_date_overwrite` | `cancel_date` locks only once `stripe_sync_status = 'deleted'` (membership removed from Stripe); clearable while unconfirmed, so a failed cancel reverts. Cancel never uses `migrating`. |
| `trg_prevent_stripe_item_id_overwrite` | `stripe_item_id` immutable once set, **unless `stripe_sync_status = 'migrating'`** — reserved for the **price migration** (`update_price` moves the line then). `migrating` is price-migration-only. |
| `trg_recurring_no_end_date` | a `recurring` plan's membership cannot have an `end_date` |
| `trg_recurring_no_active_memberships` | inserting a recurring membership requires no other active/uncancelled membership on the same `(member, gym, plan)` |
| `trg_recurring_no_overlapping_daterange` | recurring memberships on the same plan cannot have overlapping `[start, cancel)` date ranges |
| `trg_recurring_chronological_start_date` | a new recurring membership's `start_date` must be strictly after every prior one for the same `(member, gym, plan)` |

**Views.** `member_memberships` is the `security_invoker` view over
`member_memberships_unfiltered` filtered to
`stripe_sync_status NOT IN ('not_added','preview_add','preview_remove')` (so
pending + preview-staging rows stay hidden; `applied` / `deleted` / `migrating`
show); it is Stripe-gated and service_role-write-only (INSERT/UPDATE revoked for
`authenticated`).
`MEMBER_MEMBERSHIPS` in `immutable_columns.py` freezes `item_id`, `member_id`,
`gym_id`, `plan_id`, `created_at`, `stripe_item_id`, `price_id` for clients.

**Status derivation (`member_memberships_status` view).** Status is **not**
stored — it is derived from date columns + the account freeze window, in priority
order:

1. `cancelled` — `cancel_date <= gym-today`
2. `ended` — `end_date <= gym-today`
3. `frozen` — the **account's** freeze window (`freeze_start_date`/`freeze_end_date`)
   covers today. Freeze lives on `members` (the paying account), resolved through
   `COALESCE(account_linked_to_id, member_id)`, so a child account inherits its
   parent's freeze. This is why **freeze is account-level, not membership-level**.
4. `active` — otherwise.

All "today" comparisons use the gym's timezone (`now() AT TIME ZONE g.timezone`).
The Python `MembershipDbStatus` enum (`member_membership.py`) mirrors the four
values; the seed's computed `status` is only an approximation (it cannot see
account freeze) — the view is authoritative.

---

## 6. Membership lifecycle services

`src/member_memberships/service/memberships/`. The facade
(`member_memberships_service.py`, `MemberMembershipsService`) delegates to
sub-services extending `MemberMembershipsBase`. **Every mutating op is DB-first:
write the desired state to the DB, call the param-less sync
(`update_payments_recurring`, or `PaymentSyncFreeze` for freeze), then verify the
`stripe_sync_status` writeback landed and revert the DB change if it did not** (via
`sync_or_revert`). The full caller contract — what each op writes, verifies, and
reverts, and how the `migrating` status unlocks the immutable-column revert — is
owned by `sync-guide` (§2 "The caller contract"); the sync engine itself is owned
by `sync-guide` too. Each op has a parallel `preview_*` that runs the same
validation and returns a Stripe invoice preview without writing rows.

| op (file) | what it does |
| --- | --- |
| **start** (`member_memberships_start.py`) | validate plan+price usable + no existing active/frozen membership on the plan + account not frozen, DB-first insert (NULL `stripe_item_id`), Stripe sync (recurring → `update_payments_recurring`; non-recurring → one-time invoice), stamp `stripe_item_id`, write `next_due_date`. Cleanup-on-failure deletes the pending row. Created **discount-free** — discounts are applied afterward. |
| **cancel** (`member_memberships_cancel.py`) | recurring-only; idempotent if already cancelled. **DB-first:** set `cancel_date = GREATEST(next_due_date, gym-today)` (status stays `applied`, `member_memberships_cancel.sql`) — the membership stays active through the paid period — then sync (drops the line, stamps `deleted`); verify it flipped to `deleted`, else revert by clearing `cancel_date` (`member_memberships_uncancel.sql`, allowed because the membership isn't `deleted` yet). `stripe_item_id` kept intact. Returns the resolved `cancel_date`. |
| **update_price** (`member_memberships_update_price.py`) | the **opt-in price upgrade** — moves the membership onto the plan's single `is_active` price (`member_memberships_get_active_price.sql`); caller never picks the target. **DB-first:** write the new `price_id`/`total_price` + stage `migrating` (`member_memberships_update_price.sql`), then sync (the writeback moves the line to the new price's item — allowed because `migrating`), verify it flipped to `applied`, else revert to the old price. If already on the active price the CRM row is left alone but Stripe is re-synced defensively. Applied discounts stay pinned on the same `item_id` across the swap. |
| **freeze / unfreeze** (`member_memberships_freeze.py`) | **account-level** (not per-membership). `freeze` pauses Stripe billing and sets `freeze_start_date`/`freeze_end_date` on the parent `members` row (`member_memberships_freeze_profile.sql`); `unfreeze` resumes and clears them (`member_memberships_unfreeze_profile.sql`). Operates on the resolved parent account, so it covers all the account's memberships at once. |
| **mark_paid_cash** (`member_memberships_mark_paid_cash.py`) | recurring-only; finds the subscription's open Stripe invoice and pays it **out of band** (no card charge). Stripe's `invoice.paid` webhook then writes the CRM invoice/charge rows as cash. Cash is a backup — future cycles still auto-charge the card. |
| **charge_card** (`member_memberships_charge_card.py`) | ad-hoc, **outside any subscription**: create a one-off Stripe invoice for `amount_cents` + `reason`; `paid_cash=true` routes it out of band instead of charging the card. The webhook persists the CRM rows. |
| **apply discounts** (`member_memberships_update_discounts.py`) | add/remove applied-discount snapshots on the membership, then re-sync so the sync resolves coupons. **The discount snapshot model is owned by `discounts-guide`** — this op only writes/deletes snapshot rows and re-syncs; defer the once/ongoing, value-version, and coupon details there. |

---

## 7. Conceptual model + invariants

- **Plans are templates, memberships are instances.** Editing a template (rename,
  re-price) never silently re-bills holders. The only fan-out to existing members
  is the explicit `migrate_*` bulk sync (§4).
- **Price-version pinning.** A membership is frozen to its `price_id`. A plan
  re-price mints a new active price version (§3); existing memberships stay on
  their old version until `update_price` (per-member opt-in) or a bulk migration
  moves them. This is the membership analogue of the discount-version pinning
  `discounts-guide` documents, and the same predictability guarantee:
  "what is this member paying, and on which exact price/discount version" is a
  local, provable fact, never the side effect of someone editing a template.
- **Freeze (account-level) vs. cancel (membership-level) vs. end (non-recurring).**
  Three distinct stops: **freeze** pauses billing for the whole account (lives on
  `members`, inherited by linked children); **cancel** sets `cancel_date` on one
  recurring membership (stays active through the paid period); **end** is the
  natural `end_date` expiry of a non-recurring membership (recurring plans cannot
  have one — trigger). The status view resolves all three in priority order (§5).
- **DB-first / Stripe-second with cleanup.** Both `create_plan` and `start` write
  the CRM row with a NULL Stripe id (invisible behind the filtered view), call
  Stripe, then stamp the id back; a Stripe failure hard-deletes the pending row,
  a post-Stripe DB failure raises `StripeOrphanError`. This is the pattern that
  keeps a half-built plan/membership from ever being visible to a client.
- **Append-only memberships.** Re-enrolling is a new row, never a user-facing
  un-cancel; the chronological/overlap/no-active triggers keep the recurring
  history clean. (The only thing that clears `cancel_date` is the cancel's own
  *failure rollback* while the row is `migrating` — an internal compensating
  action, not a re-enroll path.)

---

## 8. Endpoints

**Plans** — `membership_plans_router.py`, prefix `/api/v1/membership_plans`:

| method + path | does |
| --- | --- |
| `POST /` | create a plan + initial price (201) |
| `PUT /` | update plan metadata (200) |
| `DELETE /` | soft-delete a plan (204; `plan_id` + `gym_id` query params) |
| `GET /` | list a gym's non-deleted plans with active price + `enrolled_count` |
| `GET /{plan_id}` | get one plan with its active price |
| `POST /price` | set a new active price (201) |
| `POST /migrate` | bulk-sync specific members to the active price (202, background) |
| `POST /migrate-all` | bulk-sync all active members on a plan (202, background) |

**Memberships** — `member_memberships_router.py`, prefix
`/api/v1/member_memberships`:

| method + path | does |
| --- | --- |
| `DELETE /` | cancel a membership |
| `POST /` | start a membership (201) |
| `POST /freeze` | freeze the account (204) |
| `POST /unfreeze` | unfreeze the account (204) |
| `PUT /price` | upgrade to the plan's active price (204) |
| `POST /preview` | preview a start |
| `POST /cancel/preview` | preview a cancel |
| `POST /price/preview` | preview a price update |
| `PUT /discounts` | add/remove discount snapshots (204) |
| `POST /discounts/preview` | preview the discounted subscription |
| `POST /mark-paid-cash` | pay the open invoice out of band (204) |
| `POST /charge-card` | ad-hoc card/cash charge |

Plan endpoints (`membership_plans_router.py`) call `verify_gym_employee` before
acting; membership endpoints (`member_memberships_router.py`) call
`verify_can_view_member` (the membership routes are all member-scoped, so they
gate on access to that member rather than on gym-employee status).

---

## Key files (where the model actually lives)

- **Schema:** `Database/supabase/schemas/membership_plans.sql` (identity +
  CHECKs + filtered view), `membership_plan_prices.sql` (versioned prices + the
  ≤1-active partial index + filtered view), `member_memberships.sql` (instance
  table + all seven triggers + `member_memberships` and
  `member_memberships_status` views). Access rules in the parallel
  `access_rules/` files (Stripe-gated, `hide_incomplete_stripe_records`).
- **Models/enums:** `Database/python_data/schema/membership_plan.py`
  (`PlanType`, `DurationUnit`), `membership_plan_price.py`,
  `member_membership.py` (`MembershipDbStatus`), `immutable_columns.py`
  (`MEMBERSHIP_PLANS`, `MEMBERSHIP_PLAN_PRICES`, `MEMBER_MEMBERSHIPS`).
- **Plan service:** `FastApiBackend/src/membership_plans/service/plans/`
  (`membership_plans_service.py` facade + `_base`, `_create`, `_update`,
  `_price`, `_read`, `_delete`); schemas in `membership_plans_schemas.py`
  (`_check_plan_constraints`); router `membership_plans_router.py`; SQL in
  `membership_plans/sql/` (`..._insert`, `..._get`, `..._list`, `..._update`,
  `..._delete`, `..._set_stripe_product_id`, `..._price_insert`,
  `..._price_deactivate_all`, `..._price_set_stripe_price_id`,
  `..._get_affected_members`, the `..._delete_pending` pair).
- **Membership service:**
  `FastApiBackend/src/member_memberships/service/memberships/`
  (`member_memberships_service.py` facade + `_base`, `_start`, `_cancel`,
  `_update_price`, `_freeze`, `_mark_paid_cash`, `_charge_card`,
  `_update_discounts`); schemas in
  `member_memberships/schema/member_memberships_schema.py`; router
  `member_memberships_router.py`; SQL in `member_memberships/sql/`
  (`..._insert`, `..._get`, `..._get_plan_price`, `..._get_active_price`,
  `..._check_existing`, `..._cancel`, `..._update_price`, the freeze/unfreeze
  profile pair, `..._delete_pending`).
- **Seams (do NOT duplicate):** the `member_memberships/sql/payment_sync/`
  folder + the sync engine are owned by `sync-guide`; the
  `member_memberships/sql/applied_discounts/` folder + the discount snapshot
  model are owned by `discounts-guide`; Stripe Product/Price/invoice/customer
  primitives are owned by `payments-guide`.
- **Design rationale (prose):** `FastApiBackend/PaymentRefactor.md` §1–§3 and §6.

---

## This is a living document

This skill is the single source of truth for how membership plans and member
memberships work. Whenever the model genuinely changes — a new column, a changed
CHECK or trigger, a new lifecycle op, a renamed service or SQL file, a changed
endpoint, or a shift in the pinning/migration rules — **update this skill in the
same change** so it never goes stale.
