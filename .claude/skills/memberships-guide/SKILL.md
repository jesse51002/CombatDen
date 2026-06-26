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
  freeze, update_price, mark_paid_cash, charge_card, add/remove discounts) — each
  of which recomputes payment state through the sync. Also covers the on-demand
  post-op invoice fetch (MemberMembershipsInvoiceFetch + MembershipsInvoiceFetchRunner
  — fire-and-forget asyncio fast path that applies new invoices via webhook record()
  seams after each invoice-creating op, with retry/early-stop on created >= op_start;
  webhooks + reconciler are backstops). Trigger on "membership plan", "plan price",
  "set price", "active price", "price pinning", "upgrade a member", "migrate members",
  "start a membership", "cancel membership", "freeze", "mark paid cash", "charge card",
  "member_memberships", "membership status", "ended vs cancelled vs frozen",
  "post-op invoice fetch", "invoice fetch runner", "fetch_for_payer", "sweep_account",
  "invoice_fetch_on_demand_enabled", or any change to the plan / membership data
  model, services, SQL, or endpoints.
---

# Memberships — plans (templates) and member memberships (instances)

This is the deep domain knowledge for CombatDen's membership **plans** and
member **memberships**. It is the **source of truth** for how these two layers
behave; CLAUDE.md holds only the "how to work here" rules. The prose design
rationale for the engine these ops call (the config-vs-outcomes split, the
reconciliation-toward-desired-state pattern) lives in the **`sync-guide`** skill;
`FastApiBackend/PaymentRefactor.md` is the remaining-work roadmap, not rationale.
When the model changes, **update this skill in the same change** (it is a living
document — see the bottom).

Three sibling knowledge skills own the seams this doc only points at:
`discounts-guide` owns the applied-discount model and linked/family
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
| cardinality | one per offering, shared by many members | **recurring:** one active per (member, gym, plan), `quantity = 1`; **one_time/trial:** may STACK via `quantity` — buying N of a pack at once is ONE row with `quantity = N` (not N rows), billed as one Stripe line of N units and granting a `class_count × N` bucket; buying ANOTHER pack later is a SEPARATE row with its own `quantity` |
| mutability | name/duration editable; price is **versioned** | append-only; cancel/end via date columns |
| Stripe-gated | yes (`stripe_product_id` / `stripe_price_id`) | yes (`stripe_item_id`) |

The load-bearing seam between them is **price-version pinning** (§3, §7): a
membership stores a concrete `price_id`, and a plan re-pricing does **not** move
existing members — they stay on their pinned price until an explicit opt-in
upgrade (`update_price`) or the per-plan reprice batch. This is the same
"editing a template never silently re-bills holders" predictability guarantee
`discounts-guide` describes for discount versions.

**Creating memberships is a single list-based op.** One `start` call takes a
payer + a **list** of memberships and creates them all for the payer's family at
once (a single membership = a one-item list — there is no separate "single
start"); see §6. The membership *instance* below is still one row each.

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
(`_check_plan_constraints` in `schema.py`, called by the
create request's `model_validator` and by update's `_validate_merged_state`), so
a bad merge is rejected before it reaches the DB.

**Filtered view + immutability.** `membership_plans` is a `security_invoker`
view exposing only `stripe_product_id IS NOT NULL` rows; the base table is
`membership_plans_unfiltered`. It is **Stripe-gated and service_role-write-only**:
`INSERT` and `UPDATE` are **fully revoked** from `authenticated` on both the base
table and the view (`access_rules/membership_plans.sql`), so every write goes
through `service_role`. On top of that DB grant, `MEMBERSHIP_PLANS` in
`immutable_columns.py` adds a Python-layer guard that rejects any client payload
carrying `plan_id`, `gym_id`, `created_at`, `plan_type`, or `stripe_product_id`.
Reads (`hide_incomplete_stripe_records` restrictive policy) never surface a
half-synced plan.

**`plan_type` is immutable after creation.** A plan's billing model
(trial / recurring / one_time) is fixed at create time — changing it would break
how existing members on the plan are billed. It is enforced at three layers:
the `trg_prevent_plan_type_overwrite` DB trigger (the real enforcement, since the
table is service_role-write-only), its membership in the `MEMBERSHIP_PLANS`
immutable set, and its **absence** from `MembershipPlanUpdateData` (the update
model carries only mutable fields). The CRM edit screen only *displays* the type.

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

`src/plans/service/`. The facade
(`service.py`, `MembershipPlansService`) delegates to focused
sub-services that all extend `MembershipPlansBase`. Endpoints live on
`router.py`.

**Create — DB-first, Stripe-second, cleanup-on-failure**
(`create.py`, `MembershipPlansCreate.create_plan`):
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
CRM edits family tiers as per-tier **$ off / % off values** — a list of
`LinkedDiscountValue` (`{percentage_off | dollar_off}`, exactly one set), capped
at `MAX_LINKED_TIERS` (4 → max 5 members), sent as `linked_discount_values`. The
plan service mints one real `linked` discount entry per value via
`DiscountsService` (tiers numbered from 2 = 2nd family member up) and stores
their ids in `linked_discount_ids`. **The discount model itself is owned by
`discounts-guide`** — this doc only notes the mint-and-store seam. Plan **reads
resolve those ids back to values** with a subquery joining
`gym_discount_values WHERE is_active` that builds a `{percentage_off, dollar_off}`
object per tier (`membership_plans_get.sql`, `membership_plans_list.sql`) so the
CRM can display/edit them without ever seeing the linked discounts in the regular
preset picker.

**Update** (`update.py`): collect non-None changes, re-mint
linked discounts if `linked_discount_prices` changed (swapping it for
`linked_discount_ids`), run `validate_mutable_columns(MEMBERSHIP_PLANS, ...)`,
validate the merged state against the CHECKs, push the rename/metadata to Stripe
**first**, then UPDATE the CRM row (`membership_plans_update.sql` with a dynamic
`{set_clause}`; jsonb columns bound as text and cast). Update does **not** change
price — that is `set_price` only.

**Set price** (`price.py`, `MembershipPlansPrice.set_price`):
deactivate the old active price + insert the new active price in one txn, create
the new Stripe Price, stamp its id, then point the Stripe Product's
`default_price` at the new price. **The old Stripe price is NOT archived** — the
code never archives a Stripe price; the CRM's `membership_plan_prices.is_active`
flag is the single gate for which price is current, so every Stripe price stays
active on Stripe forever (a member pinned to an older version keeps billing on it).
**Existing members keep their old price** — migration is separate and opt-in.

**Soft delete** (`delete.py`): deactivate the Stripe Product
(tolerating an already-gone product), then `is_deleted = true`
(`membership_plans_delete.sql`). Never hard-deletes; existing memberships keep
referencing the plan.

**Read** (`read.py`): list / get a plan joined to its active
price (`_extract_active_price`) and to resolved linked-discount amounts; the list
SQL also computes `enrolled_count` from `member_memberships_status` where
`status = 'active'`. `list_prices` returns **all** price versions of one plan
(`membership_plans_list_prices.sql`, active first), each with a per-price
`member_count` over the same active-membership set the per-plan reprice upgrades —
so the CRM edit form can show the active price plus any older version that still
has members to upgrade forward.

**Moving members to the active price is the per-plan reprice batch** —
`POST /api/v1/member_memberships/reprice-plan` → `MembershipRepriceTaskHandler.create_batch`
(`src/tasks/`) auto-discovers every live recurring membership on the plan not on
its active price (`src/tasks/sql/membership_reprice_targets.sql`) and runs ONE
tracked task that reprices each (cancel old row + insert successor at the active
price — see the reprice op in §6). This is the **one** place a plan-template
change fans out to many members — explicit and tracked, never silent drift.

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
| `stripe_item_id` | the Stripe subscription item / invoice id (immutable once set, **no exceptions, even at service-role** — moving to a different line is a NEW row); never nulled on delete/cancel (historical invoice-line record) |
| `stripe_one_time_invoice_id` | **one-time only:** the consolidated invoice id (`in_…`) a one-time membership is billed on; `NULL` for recurring. Immutable once set (trigger). |
| `stripe_sync_status` | Stripe-sync confirmation enum (`not_added` default → `applied` / `deleted` / `preview_*`); `NOT NULL`. Drives the client view + the DB-first verify |
| `total_price` | cents, `CHECK total_price >= 0` — this row's post-discount **line** total (unit price × `quantity`, minus its discounts; sync writeback) |
| `quantity` | `INT NOT NULL DEFAULT 1 CHECK (> 0)` — how many units this row bills as. one_time/trial stack via `quantity > 1` (one row → one Stripe line of N units, `class_count × N` classes); recurring forced to 1 (trigger). Set at create, immutable |
| `created_at` | |

**Triggers (exact names from the schema — what each enforces):**

| trigger | enforces |
| --- | --- |
| `trg_prevent_plan_id_overwrite` | `plan_id` immutable after creation |
| `trg_prevent_price_id_overwrite` | `price_id` immutable, **even at service-role** — a reprice is a NEW row (the `membership_reprice` task cancels the old row + inserts a successor) |
| `trg_prevent_cancel_date_overwrite` | `cancel_date` locks only once `stripe_sync_status = 'deleted'` (membership removed from Stripe); clearable while unconfirmed, so a failed cancel reverts |
| `trg_prevent_stripe_item_id_overwrite` | `stripe_item_id` immutable once set, **no exceptions, even at service-role** — a line never moves; it belongs to exactly one row forever |
| `trg_prevent_stripe_one_time_invoice_id_overwrite` | `stripe_one_time_invoice_id` immutable once set (a one-time invoice is a terminal charge, not a line that moves) |
| `trg_recurring_no_end_date` | a `recurring` plan's membership cannot have an `end_date` |
| `trg_recurring_quantity_must_be_one` | a `recurring` plan's membership must have `quantity = 1` (one subscription item per plan); only one_time/trial stack via `quantity > 1`. A pure per-row invariant (fires on previews too) |
| `trg_recurring_no_active_memberships` | inserting a recurring membership requires no other active/uncancelled membership on the same `(member, gym, plan)`; cancelled-effective-today counts as inactive (the reprice's same-day successor passes); `preview_add` rows skip the gate and never block a real insert |
| `trg_recurring_no_overlapping_daterange` | recurring memberships on the same plan cannot have overlapping `[start, cancel)` date ranges (`preview_add` skipped/ignored) |
| `trg_recurring_chronological_start_date` | a new recurring membership's `start_date` must be on or after every prior one for the same `(member, gym, plan)` — equality passes so a same-day reprice successor is legal; two live same-day rows stay impossible via no-active + overlap (`preview_add` skipped/ignored) |

**Views.** `member_memberships` is the `security_invoker` view over
`member_memberships_unfiltered` filtered to
`stripe_sync_status NOT IN ('not_added','preview_add','preview_remove')` (so
pending + preview-staging rows stay hidden; `applied` / `deleted`
show); it is Stripe-gated and service_role-write-only (INSERT/UPDATE revoked for
`authenticated`). Mid-reprice the successor row is `not_added`, so the CRM
briefly sees only the cancelled old row — the task polling/badge covers that
window.
`MEMBER_MEMBERSHIPS` in `immutable_columns.py` freezes `item_id`, `member_id`,
`gym_id`, `plan_id`, `created_at`, `stripe_item_id`, `stripe_one_time_invoice_id`,
`price_id`, `quantity` for clients.

**Status derivation (`member_memberships_status` view).** Status is **not**
stored — it is derived from date columns + the account freeze window, in priority
order:

1. `cancelled` — `cancel_date <= gym-today`
2. `ended` — `end_date <= gym-today`
3. `frozen` — the **paying account's** freeze window (`freeze_start_date`/`freeze_end_date`)
   covers today. Freeze lives on `members`, resolved through the membership's
   `paid_by_member_id` (the paying account), so a membership inherits its payer's
   freeze. This is why **freeze is account-level, not membership-level**.
4. `active` — otherwise.

All "today" comparisons use the gym's timezone (`now() AT TIME ZONE g.timezone`).
The Python `MembershipDbStatus` enum (`member_membership.py`) mirrors the four
values; the seed's computed `status` is only an approximation (it cannot see
account freeze) — the view is authoritative.

---

## 6. Membership lifecycle services

`src/memberships/service/`. The facade
(`service.py`, `MemberMembershipsService`) delegates to
sub-services extending `MemberMembershipsBase`. **The two row-replacement ops —
`reprice` (same-plan) and `upgrade` (cross-plan) — extend an intermediate
`MemberMembershipsTransitionBase` (`memberships_transition_base.py`)** that owns
their shared cancel-old + insert-successor + copy-discounts + converge +
verify-or-revert machinery (so neither swells `MemberMembershipsBase` nor
duplicates the other); both take their OWN family lock, so the facade delegates
them bare. **The facade wraps every other op (and its
`preview_*`) in `PayingMemberLock.lock([payer_id])`** (`src/shared/paying_member_lock.py`),
keyed on the PAYER — item-scoped ops (cancel / discounts /
mark_paid_cash) lock the affected row's `paid_by_member_id` (read up-front; it's
immutable); start + charge_card lock the request's payer. The lock no longer
resolves anything — the passed ids ARE the keys. Held across the whole op so no
two ops converge the same payer's subscription at once — a busy payer yields
`LockBusyError` → HTTP 409. The sub-services don't lock; the facade is the single
guard point. **Every mutating op is DB-first and pre-synced: it first converges
the payer to a clean DB↔Stripe baseline
(`_pre_sync_payments`, so it never builds on a drifted DB), then writes the desired
state to the DB, calls the param-less sync (`update_payments_recurring`, or
`PaymentSyncFreeze` for freeze), then verifies the `stripe_sync_status` writeback
landed and reverts the DB change if it did not** (via `sync_or_revert`). The full caller contract — what each op writes, verifies, and
reverts — is owned by `sync-guide` (§2 "The caller contract"); the sync engine
itself is owned by `sync-guide` too. **The memberships domain imports nothing
from `src/tasks/`** — the standalone, task-agnostic `MemberMembershipsReprice`
op is called directly for the single (member-detail) reprice and per-item by the
batch task, and the standalone `MemberMembershipsUpgrade` op is called directly
for a cross-plan upgrade (never batched);
tasks live ONLY for the batch reprice. The batch discovery→task orchestration and the
**in-task guard** (`TasksService.assert_memberships_not_in_task` — a
membership referenced by a pending/running task item rejects with
`MembershipInTaskError` → HTTP 409, wired into every item-targeted endpoint:
cancel, mark_paid_cash, add/remove discounts, the single reprice, the upgrade) live ABOVE
the facade, in the router (the composition layer). Most ops also expose a
preview (a `preview_*` method or a
`preview=True` flag) that runs the same validation and returns a Stripe invoice
preview without writing rows. **Link (authorize) is the exception to this whole
paragraph** — it is a pure DB change (no sync, no `_pre_sync_payments`/verify, no
preview) and locks **two** families inside the op, so the facade delegates it bare
(see the table). **Removing** an authorization is NOT pure-DB: it cascades through
`cancel` (the funded memberships are cancelled first, then the row is deleted),
because a bare delete would strand billing — so it runs the normal sync+verify path.

| op (file) | what it does |
| --- | --- |
| **start** (`memberships_start.py`, `MemberMembershipsStart.start(request)`) | **ONE list-based op:** a payer + a list of N membership items (each `member_id` + `price_id` + its `discount_ids` + inline `custom_discounts`); a single membership is just a one-item list. The op **never links** — every non-payer item member must have ALREADY authorized the payer (validation rejects otherwise with an "authorize them first" error), which is what lets the whole request run under the payer's single family lock (the facade locks payer + all item members). **ONE payer per request** (`payer_member_id`) — its `paid_by_member_id` is stamped on every inserted row; the payer may be a top-level account OR a **self-paying linked member** (no longer top-level-only). **Phase A** validates everything up-front in the shared `MemberMembershipsStartValidation` (payer is in-gym/unfrozen → links: every non-payer item member must have authorized the payer, i.e. the payer is each item's own member or one of that member's authorized payers → plan/price rows → intra-request duplicate checks (the request validator structurally rejects two items with the same (member, `price_id`) — multiplicity is `quantity`, not repeated items; `_check_no_recurring_duplicates` additionally rejects two recurring items on the same (member, plan) at DIFFERENT prices, which the (member, price) dedup can't see; `_check_recurring_quantity` rejects `quantity > 1` on a recurring item — only one_time/trial may carry `quantity > 1`) → per-member existing-**recurring** check (`_check_no_existing` is recurring-only via `member_memberships_check_existing.sql`'s `plan_type = 'recurring'` filter — an active/frozen recurring blocks a second recurring; one_time/trial stack) → discounts live & not `custom`); any failure rejects with nothing written or billed. **Phase B (pure DB):** one multi-row pending insert (NULL `stripe_item_id`, `not_added`) + per-item minted customs + applied discounts — **discounts at creation**, so the first (one-time: the only) invoice is discounted; the start is the one flow allowed to apply a custom (`allow_custom=True`, single-use DB-enforced — `discounts-guide`); any failure undoes everything (nothing billed). **At most two charges:** **Phase C** = ONE consolidated one-time invoice for the `one_time`/`trial` group via `PaymentSyncOneTime.charge_one_time` (one line per membership, item-level coupons; a **trial is a $0 line** on the same invoice; writeback stamps `stripe_item_id` = invoice LINE id + `stripe_one_time_invoice_id` + post-discount `total_price` + `applied`); an optional **card entered at checkout** (`payment` = `MemberMembershipsStartPayment{payment_method_id, set_default}` — card-only, so rejected together with `paid_with_cash`) is handled by `set_default`: when **`set_default`** the card is promoted to the payer's saved default **FIRST** — before any pre-sync, insert, or charge, via `MembersManagementService.update_card` — so it bills BOTH this one-time invoice AND the recurring converge below; when **not** `set_default` it is a **one-off** for THIS invoice only (attach → pay → detach, saved default untouched — `payments-guide`/`sync-guide`). Recurring can only bill the saved default, so a request with any recurring membership MUST set `set_default` (rejected otherwise). The default-save is **not best-effort**: if it fails the whole start ABORTS (raises) with nothing written or charged — never a membership left billing the old card. A *later* charge failure (after the default already changed) is the accepted case — staff re-edit, never reverted; **Phase D** = ONE recurring converge for the recurring group via `update_payments_recurring` (writeback stamps `stripe_item_id` + next_due_date + `applied`). The recurring first charge is **verified synchronously now**: the engine sends the create/add card path `error_if_incomplete` (cash → `pay_first_invoice_out_of_band`, paid out of band), so a **declining card fails the recurring group** — the create 402s leaving no subscription (or an add 402s + Stripe rolls the item change back, leaving the existing sub untouched), the group's pending rows are cleaned, and the failure surfaces as `failed` in the breakdown rather than a `created` row hiding an `incomplete` sub. Only the monthly RENEWALS after the first charge stay async (Stripe dunning → the `invoice.payment_failed` webhook). Idempotency sub-keys are `uuid5(request_key, PlanType.<group>.value)`, so a client retry dedups BOTH charges at Stripe. **Failure granularity is the charge group** (same-group items share fate); a charge failure is **data, not an exception** — it surfaces in the per-membership breakdown `MemberMembershipsStartResponse` (`results[]` with per-item `status`/`item_id`/`error`, `charge_count`, `multiple_charges`), and a **successfully billed one-time row is NEVER un-billed** (kept + flagged for reconciliation if its writeback was unconfirmed). |
| **cancel** (`memberships_cancel.py`) | **recurring-only**; idempotent if already cancelled. **DB-first:** set `cancel_date = GREATEST(next_due_date, gym-today)` (status stays `applied`, `member_memberships_cancel.sql`) — the membership stays active through the paid period — then sync (drops the line, stamps `deleted`); verify it flipped to `deleted`, else revert by clearing `cancel_date` (`member_memberships_uncancel.sql`, allowed because the membership isn't `deleted` yet). `stripe_item_id` kept intact. Returns the resolved `cancel_date`. |
| **end_one_time** (`memberships_cancel.py`, same service) | end a **ONE-TIME / TRIAL** membership early — the non-recurring counterpart of cancel. `end_one_time(item_id, member_id) -> end_date`: validates non-recurring (rejects a recurring — that's cancel) + not already ended/cancelled, then sets `end_date = today` (`member_memberships_end.sql`) → status `ended`. A one-time pack is a **terminal invoice with no subscription line**, so this is a **PURE DB date write — NO Stripe converge and NO payer lock** (the facade delegates it bare, like refund). Money-back is the SEPARATE `/refund` flow (`memberships_refund.py`). |
| **reprice** (`memberships_reprice.py` — `MemberMembershipsReprice`) | the **same-plan** price-version bump (move a membership to a newer price of its **SAME** plan; a cross-plan tier change is `upgrade` above). Extends `MemberMembershipsTransitionBase`. **Two entry points; tasks are ONLY for the batch.** The op `reprice(member_id, old_item_id, proration_behavior, target_price_id=None) -> successor item_id` is **fully TASK-AGNOSTIC and standalone** (imports nothing from `src/tasks`) and handles its own failure like every other DB-first op: under the family lock it validates → resolves the target (`target_price_id=None` → the plan's `is_active` price via `member_memberships_get_active_price.sql`; **given** → that exact price **as-is**, fetched by id via `member_memberships_get_price.sql`, **NOT re-checked against the plan's *current* active price** — the batch pins active-at-discovery; a newer price created before the item runs must NOT divert/fail the upgrade, and a deactivated CRM price keeps a usable Stripe price since `plans_price.py` never archives one) → `_pre_sync_payments` → ONE txn (cancel old row **effective today** via `member_memberships_cancel_immediate.sql` + insert successor (`not_added`) + COPY live applied discounts via `applied_discounts/copy_applied_discounts.sql`) → convergent sync → **verify successor `applied` AND old row `deleted`, else REVERT** (delete the copies via `applied_discounts/delete_copied_discounts.sql` → delete the pending successor → clear the old row's `cancel_date`; skipped if the successor's line already stamped — known-residual doctrine) and raise. **A membership already on the target is a no-op** — returns the row's own id, touches nothing, bills nothing (no defensive re-sync; the reconciler converges any drift). • **SINGLE** (`PUT /price`, the member-detail upgrade): a DIRECT, synchronous call (`memberships_service.update_price` → `reprice` with no target → plan active); returns the successor id (== input on a no-op). NOT a task. • **BATCH** (`POST /reprice-plan`, "upgrade everyone on a plan"): the ONLY task workflow — `MembershipRepriceTaskHandler.create_batch` (`src/tasks/service/tasks_membership_reprice_handler.py`) **discovers the targets itself** (`src/tasks/sql/membership_reprice_targets.sql` — every live recurring membership on the plan not on its active price, excluding any already mid-task; the discovery lives in the **tasks layer**, NOT the reprice op) and makes ONE `membership_reprice` task with an item per membership (pinning the active price), and the router fires the background run; the CRM polls `GET /tasks/{id}`. `execute_item` runs `reprice` per item + records the successor onto `task_items.new_item_id`; a failed item retries (3×) then fails, the membership untouched (re-running the batch picks it up). **There is no reprice preview.** Old applied-discount rows stay pinned to the old row as records. |
| **upgrade** (`memberships_upgrade.py` — `MemberMembershipsUpgrade`) | the **cross-plan** upgrade: move a membership to a **DIFFERENT** plan's active price and charge the prorated **difference** now. Extends `MemberMembershipsTransitionBase` (shares reprice's cancel-old + insert-successor + converge + verify-or-revert), inserting the successor on the **target** `plan_id`. `upgrade(member_id, old_item_id, target_plan_id, proration_behavior, idempotency_key) -> successor item_id` — a DIRECT, synchronous op under the family lock, **no batch**. Validates → recurring & not cancelled/ended → target ≠ same plan (a same-plan move is a reprice) → target plan exists, not deleted, recurring, and **same recurring window** (`member_memberships_get_plan_recurring.sql` vs the old plan's window already on `member_memberships_get.sql`; today both monthly — a future-proof guard, the REAL safety check, not plan_id) → no existing active recurring on the **target** plan (`_check_no_existing`) → resolve the target plan's active price → **downgrade guard** (`_effective_proration`: `prorate_to_anchor` only when the caller asked AND new price > old; else `no_charge`, so a downgrade/equal switches the plan and bills/credits **nothing**) → `_pre_sync_payments` → ONE txn (cancel old **effective today** + insert successor on the **new** plan + carry-all applied discounts) → convergent sync with the effective proration → verify successor `applied` AND old `deleted`, else REVERT. **Mechanism = native Stripe proration, NO coupon trick:** the converge sends delete-old-line + add-new-line in ONE `Subscription.update` with `always_invoice`, so Stripe nets the old line's credit against the new line's charge = the prorated difference (independent of `plan_id` — only the interval must match, hence the window guard). **Discounts: carry ALL as-is** (reuses `copy_applied_discounts.sql`) — copying the OLD plan's linked/family discount onto the NEW plan is logically wrong but kept for v1 consistency (a later iteration should re-derive the new plan's linked discount). **`upgrade_preview(...) -> DueNowVsRecurringPreview \| None`** runs the same validation, stages the old row `preview_remove` + a `preview_add` successor on the target plan (+ copied discounts), runs `preview_update_payments_recurring(effective)`, and ALWAYS reverts via `_sweep_stale_preview_rows`; `due_now` = the prorated difference (`None` on a downgrade/equal, mirroring the start preview's no_charge suppression). |
| **freeze / unfreeze** (`freeze.py`) | **account-level** (not per-membership). `freeze` pauses Stripe billing and sets `freeze_start_date`/`freeze_end_date` on the parent `members` row (`member_memberships_freeze_profile.sql`); `unfreeze` resumes and clears them (`member_memberships_unfreeze_profile.sql`). Operates on the resolved parent account, so it covers all the account's memberships at once. |
| **mark_paid_cash** (`mark_paid_cash.py`) | recurring-only, and **rejects a canceled membership** (`cancel_date <= gym-today` — staff re-enroll instead of paying a dead membership); resolves the membership row's PAYER (`paid_by_member_id`) and pays **that payer's** subscription's open Stripe invoice **out of band** (no card charge). Stripe's `invoice.paid` webhook records the CRM invoice, and the `invoice_payment.paid` webhook records the cash charge (the InvoicePayment is `out_of_band`). Cash is a backup — future cycles still auto-charge the card. |
| **charge_card** (`charge_card.py`) | ad-hoc, **outside any subscription**: the request carries an explicit **`paid_by_member_id`** (validated self-or-linked-parent of the beneficiary `member_id`); creates a one-off Stripe invoice for `amount_cents` + `reason` **on the payer's customer** (metadata's `member_id` stays the beneficiary); `paid_cash=true` routes it out of band instead of charging the card. The `invoice.paid` + `invoice_payment.paid` webhooks persist the CRM invoice + charge rows. |
| **add / remove discounts** (`memberships_discounts.py`) | **two separate ops**, `add_discounts(item_id, member_id, discount_ids, idempotency_key, preview=False)` (rejects `custom` ids — customs are creation-only, single-use) and `remove_discounts(item_id, member_id, applied_ids, idempotency_key, preview=False)`. Each writes/deletes applied-discount rows, then re-syncs so the sync resolves coupons. With `preview=True` it **stages** instead of committing — add inserts `preview_add` rows then deletes them; remove flips the rows to `preview_remove` then reverts to `applied` — runs the read-only preview build (which keeps `preview_add` in / drops `preview_remove`), and always cleans up. **The applied-discount model is owned by `discounts-guide`** — defer the lifetime spec, value-version, coupon, and preview-staging details there. |
| **authorize payer** (`linked.py`) / **remove-authorization** (cascade, `memberships_service.py`) | **Many-to-many** (`member_authorized_payers`): a member may have MANY authorized payers AND be an authorized payer for others. `link_account(member_id, payer_member_id, *, signer_name, consent_acknowledged, …)` is **sign-gated** — in ONE transaction it records the payer's signature on the gym's **default authorized-payer waiver** (resolved via `WaiversService.get_default_waiver_for_member` → `record_signature`) and inserts the `member_authorized_payers(member_id, payer_member_id, gym_id, signature_id)` row (no orphan signatures). Authorizing is a **pure DB change** — no Stripe sync, no preview, no no-active-recurring guard (it never contributes a membership line). `check_link_account(member_id, payer_member_id)` is a read-only pre-flight (not-self / payer-in-gym / not-already-authorized). **De-authorization is the cascade `remove_authorization(member_id, payer_member_id, idempotency_key)` on the facade (`POST /link/remove`) — the ONLY unlink path:** it cancels the payer's funded recurring memberships for this member FIRST (the `cancel` op, full sync+verify), THEN deletes the `member_authorized_payers` row (`member_authorized_payers_delete.sql`); the signature persists as append-only audit. **There is no bare de-authorize** — deleting the authorization without cancelling would strand billing (the membership's `paid_by_member_id` keeps pointing at the de-authorized payer, so Stripe keeps charging), which is exactly why removal cascades. The authorization (who may pay for whom) is `member_authorized_payers`, never the billing key. `link_account` injects `WaiversService` and owns its **own** locking: locks the **two accounts** `[member_id, payer_member_id]` (delegated **bare**, since `PayingMemberLock` is non-reentrant); `remove_authorization` likewise locks the two accounts. `MemberMembershipsLinked` is self-contained — does **not** extend `MemberMembershipsBase`. |

**The start preview is its own three-way split** (`MemberMembershipsStartPreview`,
`memberships_start_preview.py`) — unlike the other ops' two-way
`DueNowVsRecurringPreview`. It runs the **identical** Phase-A validation as the
real start, **stages** every item exactly as the real start would — pending rows
as `preview_add` + their applied-discount rows (inline customs minted, then
archived again in cleanup) — runs the two engine previews against that staged,
**discounted** state, and **always** undoes the staging in a `finally` (the real
path excludes `preview_add`, and the held family lock keeps a concurrent real
sync from observing it). The response `MemberMembershipsStartPreviewResponse` is a
three-way split: **`one_time`** (the consolidated one-time invoice, from
`PaymentSyncOneTime.preview_one_time`), **`due_now`** (the recurring proration
charged now when `proration_behavior=prorate_to_anchor`) and **`recurring`** (the steady-state per-cycle
invoice) — the latter two unpacked from `preview_update_payments_recurring`'s
`DueNowVsRecurringPreview`. Each is `None` when the request has no membership in
that group. (The cancel and discount previews deliberately keep the two-way
`DueNowVsRecurringPreview`; reprice has no preview.) Two rules shape what it
returns:

- **`due_now` is absent (`None`) when `request.proration_behavior` is `no_charge`.** With no
  proration the engine's split reuses the steady-state recurring figure as
  `due_now`; that amount is **not** actually due now, so the start preview
  suppresses it. Scoped to the start preview only — the shared engine split
  and the cancel / discount previews keep the reuse.
- **The `one_time` half contains only the one-time lines.**
  `PaymentSyncOneTime.preview_one_time` previews at the customer level, so for
  a payer with a live subscription Stripe mixes the subscription's upcoming
  recurring lines in with the staged one-time items. That caller strips the
  subscription-derived lines (`stripe_subscription_item_id` set /
  `is_proration`) and recomputes the totals from the kept one-time lines
  (engine detail owned by `sync-guide` / `payments-guide`).

---

## 7. On-demand post-op invoice fetch

After any **invoice-creating** membership op — `charge_card`, `start` (charge groups),
`upgrade`, prorating reprice, `mark-paid-cash` — `MemberMembershipsService` fires a
**fire-and-forget invoice fetch** via `MembershipsInvoiceFetchRunner.start_for_payer`.
This pulls that payer's new invoices from Stripe immediately and applies them through
the **same idempotent webhook `record()` seams** used by the reconciler, without waiting
for the `invoice.paid` / `invoice_payment.paid` webhooks (which can arrive seconds to
minutes later). Webhooks + the twice-daily reconciler sweep remain backstops.

**Key design points:**

- **Fires AFTER the payer lock releases**, as an `asyncio.create_task` — it never extends
  the lock-hold window and never blocks the HTTP response.
- **Retry/early-stop on `created >= op_start`.** `fetch_for_payer` issues a bounded set
  of retries (config: `invoice_fetch_retry_delays_seconds`, default `[0, 3, 8, 15, 25]`)
  with a clock-skew buffer (`invoice_fetch_buffer_seconds`, default `120` s). It stops as
  soon as it applies a paid invoice whose Stripe `created` timestamp is at/after the op's
  start time — i.e. the bill THIS op cut, not a stale one already in the lookback window.
- **Same engine for both callers.** `MemberMembershipsInvoiceFetch.sweep_account` is the
  per-account loop the reconciler's `InvoiceFetchSweep` delegates to. The on-demand path
  calls `sweep_account` scoped to a single Stripe customer (`customer=<id>`); the
  reconciler calls it with `customer=None` (whole account sweep). There is **no
  `memberships → reconciler` import edge** — the reconciler calls in, never the reverse.
  `SweepResult` lives in `src/shared/sweep_result.py` to satisfy this constraint.
- **Best-effort.** A payer with no billing profile (cash-only / engagement member) is a
  no-op. A runner task lost to a process restart is covered by the webhook + cron backstop.
- **Idempotent at the DB layer** (invoice upsert on `stripe_invoice_id`, charge / refund /
  synthetic-failed-key UNIQUE), so the post-op fetch racing the webhook or the cron sweep
  is safe — whichever lands first wins, the rest are no-ops.

**`MembershipsInvoiceFetchRunner`** (`memberships_invoice_fetch_runner.py`):
- Singleton; a `ClassVar` set holds strong references to in-flight `asyncio.Task` objects
  so they aren't GC'd mid-flight.
- `start_for_payer(payer_member_id, op_start)` — no-op when
  `settings.invoice_fetch_on_demand_enabled` is False.
- `drain()` — cancels + awaits all in-flight fetches on app shutdown (called from lifespan).

**`MemberMembershipsInvoiceFetch`** (`memberships_invoice_fetch.py`):
- Injects `PaymentsStripeClient`, `PayerResolver`, and the 4 webhook record handlers
  (`InvoicePaidHandler`, `InvoicePaymentPaidHandler`, `InvoicePaymentFailedHandler`,
  `RefundHandler` — they **stay in `src/stripe_webhooks/`**; the engine only injects them).
- Full-account sweeps include refunds; customer-scoped on-demand fetches skip refunds
  (refunds have their own op + webhook + cron backstop).

**Config** (all `Settings` fields in `src/core/config.py`):

| setting | default | meaning |
| --- | --- | --- |
| `invoice_fetch_on_demand_enabled` | `True` | master on/off switch |
| `invoice_fetch_buffer_seconds` | `120` | clock-skew buffer subtracted from `op_start` to compute the Stripe `created` query cutoff |
| `invoice_fetch_retry_delays_seconds` | `[0, 3, 8, 15, 25]` | delays (seconds) between retry attempts; `0` = immediate first try |

---

## 8. Conceptual model + invariants

- **Plans are templates, memberships are instances.** Editing a template (rename,
  re-price) never silently re-bills holders. The only fan-out to existing members
  is the explicit per-plan reprice batch (§4).
- **Price-version pinning.** A membership is frozen to its `price_id`. A plan
  re-price mints a new active price version (§3); existing memberships stay on
  their old version until `update_price` (per-member opt-in) or the per-plan
  reprice batch moves them. This is the membership analogue of the discount-version pinning
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
  *failure rollback*, permitted while the membership has not yet been removed from
  Stripe (status is not `deleted`) — an internal compensating action, not a
  re-enroll path.)

---

## 9. Endpoints

**Plans** — `plans_router.py`, prefix `/api/v1/membership_plans`:

| method + path | does |
| --- | --- |
| `POST /` | create a plan + initial price (201) |
| `PUT /` | update plan metadata (200) |
| `DELETE /` | soft-delete a plan (204; `plan_id` + `gym_id` query params) |
| `GET /` | list a gym's non-deleted plans with active price + `enrolled_count` |
| `GET /{plan_id}` | get one plan with its active price |
| `GET /{plan_id}/prices` | list every price version with per-price `member_count` (active first) |
| `POST /price` | set a new active price (201) |

**Memberships** — `memberships_router.py`, prefix
`/api/v1/member_memberships`:

| method + path | does |
| --- | --- |
| `DELETE /` | cancel a membership |
| `POST /` | start the payer's family memberships in one call — list of items in, per-membership breakdown out (`MemberMembershipsStartResponse`); ≤2 charges (201) |
| `POST /freeze` | freeze the account (204) |
| `POST /unfreeze` | unfreeze the account (204) |
| `PUT /price` | reprice ONE membership to the **same** plan's active price — direct/synchronous; returns the successor `item_id` (200) |
| `POST /reprice-plan` | batch-reprice every member on a plan to its active price as a tracked task; returns `task_id` to poll (202) |
| `POST /upgrade` | **cross-plan** upgrade ONE membership to a DIFFERENT plan's active price, charging the prorated difference — direct/synchronous, task-guarded; returns the successor `item_id` (200) |
| `POST /upgrade/preview` | preview an upgrade — `due_now` (prorated difference, null on a downgrade) + `recurring` (new monthly) |
| `POST /preview` | preview a start — three-way `one_time / due_now / recurring` split (staged, discounted) |
| `POST /cancel/preview` | preview a cancel |
| `POST /discounts/add` | add applied-discount row(s) to the membership; `preview` bool in the body runs a dry-run instead of committing |
| `POST /discounts/remove` | remove applied discount(s); `preview` bool in the body runs a dry-run instead of committing |
| `POST /end` | end a ONE-TIME / TRIAL membership early — sets `end_date = today` → status `ended`; pure DB write, no Stripe, returns the `end_date` (recurring rejected — use `DELETE /`) |
| `POST /mark-paid-cash` | pay the open invoice out of band (204) |
| `POST /charge-card` | ad-hoc card/cash charge |

Plan endpoints (`plans_router.py`) call `verify_gym_employee` before
acting; membership endpoints (`memberships_router.py`) call
`verify_can_view_member` (on the payer + every item member for start/preview; on
the member for member-scoped ops) — the membership routes are all member-scoped,
so they gate on access to those members rather than on gym-employee status).

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
- **Plan service:** `FastApiBackend/src/plans/service/`
  (`plans_service.py` facade + `plans_base`, `plans_create`, `plans_update`,
  `plans_price`, `plans_read`, `plans_delete`); schemas in `plans_schema.py`
  (`_check_plan_constraints`); router `plans_router.py`; SQL in
  `src/plans/sql/` (`..._insert`, `..._get`, `..._list`, `..._update`,
  `..._delete`, `..._set_stripe_product_id`, `..._price_insert`,
  `..._price_deactivate_all`, `..._price_set_stripe_price_id`,
  `..._get_affected_members`, `..._list_prices`, the `..._delete_pending` pair).
- **Membership service:**
  `FastApiBackend/src/memberships/service/`
  (`memberships_service.py` facade + `memberships_base`, `memberships_start`
  (`MemberMembershipsStart.start` — the list op), `memberships_start_validation`
  (the shared Phase-A `MemberMembershipsStartValidation`),
  `memberships_start_preview` (`MemberMembershipsStartPreview` — the staged 3-way
  preview), `memberships_cancel`, `memberships_transition_base`
  (`MemberMembershipsTransitionBase` — the shared cancel-old + insert-successor +
  converge + verify-or-revert machinery for reprice + upgrade), `memberships_reprice`
  (`MemberMembershipsReprice` — the task-agnostic **same-plan** reprice op; the
  `membership_reprice` task handler that drives it lives in `src/tasks/`, NOT here),
  `memberships_upgrade` (`MemberMembershipsUpgrade` — the **cross-plan** upgrade op +
  `upgrade_preview`; standalone, no batch), `memberships_freeze`,
  `memberships_mark_paid_cash`, `memberships_charge_card`,
  `memberships_discounts`, `memberships_linked`,
  **`memberships_invoice_fetch`** (`MemberMembershipsInvoiceFetch` — the fetch+apply
  engine; §7), **`memberships_invoice_fetch_runner`** (`MembershipsInvoiceFetchRunner`
  — the fire-and-forget asyncio runner; §7)); schemas in
  `src/memberships/memberships_schema.py` (`MemberMembershipsStartRequest` /
  `...StartItem` / `...StartResponse` / `...StartResultItem` /
  `...StartPreviewResponse` + the internal `...StartItemState`); router
  `src/memberships/memberships_router.py`; SQL in `src/memberships/sql/`
  (`..._insert`, `..._get`, `..._get_plan_prices`, `..._get_active_price`,
  `..._get_price` (a specific price by id — the reprice's pinned target),
  `..._get_plan_recurring` (the upgrade's target-plan window/`is_deleted` for the
  same-window guard), `..._plan_reprice_targets` (batch discovery),
  `..._check_existing`, `..._cancel`, `..._cancel_immediate` (the
  reprice/upgrade's effective-today cancel), `..._end` (the one-time/trial
  early-end `end_date` write),
  `..._start_account_links`, `..._start_discounts_check`, the freeze/unfreeze
  profile pair, `..._delete_pending`). The one-time charge engine the start calls
  (`PaymentSyncOneTime`) lives in `src/sync/` — owned by `sync-guide`.
- **Shared model:** `src/shared/sweep_result.py` (`SweepResult`) — imported by both
  the memberships fetch engine and the reconciler sweep; lives in `shared` so there
  is no `memberships → reconciler` import edge.
- **Seams (do NOT duplicate):** the `src/sync/sql/`
  folder + the sync engine are owned by `sync-guide`; the
  `src/memberships/sql/applied_discounts/` folder + the applied-discount
  model are owned by `discounts-guide`; Stripe Product/Price/invoice/customer
  primitives and the webhook `record()` handler internals are owned by
  `payments-guide`.
- **Engine design rationale (prose):** the **`sync-guide`** skill (the
  config-vs-outcomes split + the reconciler). `FastApiBackend/PaymentRefactor.md`
  is the remaining-work roadmap only.

---

## This is a living document

This skill is the single source of truth for how membership plans and member
memberships work. Whenever the model genuinely changes — a new column, a changed
CHECK or trigger, a new lifecycle op, a renamed service or SQL file, a changed
endpoint, or a shift in the pinning/migration rules — **update this skill in the
same change** so it never goes stale.
