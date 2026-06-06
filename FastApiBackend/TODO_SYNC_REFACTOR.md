# Payment-Sync Refactor — Handoff / TODO

> **Read this whole file before touching `src/member_memberships/service/payment_sync/`.**
> This is a slow, **human-in-the-loop** refactor of the **most billing-critical code in
> the backend** — it decides how real members are charged. Every change is proposed,
> reviewed, and approved **one piece at a time**. Never a big sweep. Propose → wait →
> write. A mistake here mis-bills real customers. (This rule is also in
> `.claude/skills/sync-guide/SKILL.md` and `FastApiBackend/CLAUDE.md`.)

---

## 0. Orientation — where everything is

- **Worktree:** you are in `/.../codebase/.claude/worktrees/membership-refactor-step1`
  (branch `worktree-membership-refactor-step1`, branched from local `restore_crm` HEAD).
  All edits happen here, isolated from the main checkout.
- **The engine:** `FastApiBackend/src/member_memberships/service/payment_sync/`.
- **The running plan (READ IT):** `~/.claude/plans/partitioned-plotting-whale.md` — has the
  Step 2 plan and the **Part E** spec. This TODO is the more detailed companion.
- **The audit that started this:** `MANUAL_REVIEW.md` (repo root). Items #12–#22 drive this
  refactor. Mapping at the bottom of this doc.
- **Living docs to keep in sync:** `.claude/skills/sync-guide/SKILL.md` (engine source of
  truth), `.claude/skills/discounts-guide/SKILL.md` (discount model), `payment_sync.mermaid`
  (flow diagram). **They are STALE again after Step 2 — update when the engine stabilizes.**

### How to verify (do this after every change)
The worktree has **no `.venv`**. Use the MAIN checkout's venv. From `FastApiBackend/`:
```bash
# syntax + lint (system python is fine for these)
python -m py_compile <files>
python -m ruff check <files>          # ruff 0.15; `--fix` auto-removes unused imports
# DI build / import smoke test (needs deps + settings):
MAIN=/var/home/jm/Documents/CombatDen/codebase/FastApiBackend
"$MAIN/.venv/bin/python" -c "
import os; from dotenv import dotenv_values
os.environ.update({k:v for k,v in dotenv_values('$MAIN/.env').items() if v is not None})
import sys; sys.path.insert(0,'src')
import src.shared.db_schema_path            # MUST import first (registers schema.* path)
import src.core.dependencies as d
s = d.DependencyInjector().payment_sync_service()
print(type(s).__name__)
"
```
Notes: the `.env` has one unquoted comma value (a CORS line) that breaks `source` — load it
with `dotenv_values`. `import src.shared.db_schema_path` before anything that imports
`schema.*`. **NEVER run migrations or seeds** — the user runs `supabase` migrations and
`python_data/main.py` seeding manually (per `Database/CLAUDE.md`). When you change a
`Database/supabase/schemas/*.sql` enum/column, tell the user to re-run the migration.

### Tooling gotcha (from memory)
`.venv` console scripts (`pytest`, `ruff`) have stale shebangs after a repo move — invoke via
`"$MAIN/.venv/bin/python" -m pytest|ruff`, not the bare script.

---

## 1. The big picture — what the engine is

`PaymentSyncService` is a **declarative reconciler**: on every membership mutation it throws
away whatever Stripe has and **re-derives the full desired subscription state from the DB**,
then converges Stripe onto it. The CRM owns intent (who's enrolled, prices, discounts);
Stripe owns billing outcomes (did the invoice clear). It is a **thin orchestrator** over
focused sub-services.

**`update_payments_recurring(member_id, idempotency_key, pay_first_invoice_out_of_band=False,
proration_behavior="none")` runs these phases (real path):**
1. **resolve** parent + gym Stripe account — `BillingParentResolver.resolve(member_id)`.
2. **maintenance freeze re-apply** — `PaymentSyncFreeze.sync_freeze_state(parent, account)`
   converges `pause_collection` to the parent's DB freeze window (`parent.is_frozen`).
3. **finalize once discounts (pre-sync settle)** — `PaymentSyncOnceDiscounts.sync_once_discounts`
   stamps `end_date` on any `once` discount Stripe already invoiced (so the build drops it).
4. **build** — `_build_sync_params(parent, account)` reads the DB, builds the desired
   `IntervalBucket`, and **resolves discount coupons onto the bucket** (via `PaymentSyncDiscounts`,
   for **both** real and preview, so preview reflects discounts). Returns `SyncParams`.
5. **execute** — `PaymentSyncStripe.execute_sync(bucket, parent, account, idempotency_key,
   pay_first_invoice_out_of_band, proration_behavior)` create/update/cancel.
6. **write back** — (interim, in the orchestrator today) persist the `coupon_links`
   (`set_snapshot_coupon_id`), then `update_profile_sub_id`, then `PriceWriteback`.

**`preview_update_payments_recurring(member_id, proration_behavior="none")`** runs resolve →
build (incl. discount resolution → coupons attached) → `preview_execute_sync`. **No DB writes,
no freeze, no settle** — but it DOES find-or-create coupons (idempotent, gym-wide), so the
preview total now reflects discounts.

---

## 2. STATUS — what is DONE (and verified) vs LEFT

| Area | Status |
| --- | --- |
| Step 1 — thin the engine (freeze/once/parent extracted, drop add/cancel, rename, docs) | ✅ DONE, verified |
| Step 2 — schema `stripe_sync_status` (+`migrating`) | ✅ DONE (user ran migration; **re-run still needed for `migrating`**) |
| Step 2 — per-membership discount math | ✅ DONE, **review-verified correct** |
| Step 2 — explicit proration `proration_behavior` (#22) | ✅ DONE (incl. create-path `item.prorate` removal) |
| **Part E — discounts ride the membership** | ✅ DONE — `AppliedDiscount` rides `ActiveMembershipRow.discounts`; `get_active_memberships` one-call read; group-by-price → `PaymentSyncDiscounts.resolve` → `ResolvedDiscounts`; `SyncParams` dropped `snapshots`; payments-side `subscription_discounts` removed; "snapshot" dropped from engine |
| Builder → `PaymentSyncBuilder` service; math → `PaymentSyncDiscounts` (private) | ✅ DONE |
| `ResolvedDiscounts` model (no tuple); `LineDiscountValue` validators (≤100, >0, XOR) | ✅ DONE |
| Coupon **validate-or-replace** (delete+recreate on value mismatch) | ✅ DONE |
| Date-lifetime filter moved **into SQL** (`:today`); `_is_past_end_date` deleted | ✅ DONE |
| Dead `IntervalBucket.total_price` removed | ✅ DONE |
| **`PaymentSyncCoupons` delegates all Stripe coupon I/O to `PaymentsStripeDiscountService`** (no direct SDK in engine); dead `crm_discount_id`/`StripeCouponMetadata`/`update_discount` removed | ✅ DONE |
| `sync-guide` + `payments-guide` skills | ✅ UPDATED to current engine |
| **Part D — unified `PaymentSyncWriteback`** (links + sync-status `applied`/`deleted` + sub-id + prices, via `PaymentSyncQueries`) | ❌ LEFT — writeback is still interim inline in the orchestrator |
| **Preview correctness** (#19 — due-now vs recurring split; the consumed-but-unstamped `once` over-state) | ❌ LEFT — needs scoping |
| **Lifecycle callers** (start/cancel/update_price/freeze/link) — DB-first rewiring (#16/#17) | ❌ LEFT — the big *functional* work; engine non-functional at caller layer until done |
| **Concurrency / global member lock** (NEW — serialize concurrent edits/sync on the same parent family) | ❌ LEFT — design below (§11) |
| `update_payments_recurring -> None` (#21) | ❌ LEFT (still returns the sub response) |
| `ActiveMembershipRow.price` orphaned by `total_price` removal | 🟡 pending decision (remove field + parse + `mpp.price` SELECT?) |
| Tests | ❌ STALE/RED by design — see §6 |
| `discounts-guide` ("snapshot"→"applied discount" rename) + `payment_sync.mermaid` | ❌ LEFT |
| #23 migrate other `resolve_parent` callers to `BillingParentResolver` | ❌ LEFT |
| `gyms_stripe_connect_service.py` calls Stripe directly (Connect onboarding) | 🟡 separate domain, no payments-layer service — decide if it should route too |

Everything ✅ above passes `py_compile` + `ruff` + a DI-container build (+ math traces 44/27/20/2000).

---

## 3. What was DONE — in detail (so you don't redo it)

### 3.1 Step 1 — the engine became a thin orchestrator
- **Rename:** `MembershipPaymentSyncService` → **`PaymentSyncService`**; file
  `membership_payment_sync_service.py` → **`payment_sync_service.py`**. All ~14 references
  (DI, callers, tests) updated.
- **Parent resolution → shared service.** New `src/shared/billing_parent_resolver.py`
  (`BillingParentResolver`: `resolve_parent(member_id) -> ParentProfile`,
  `resolve(member_id) -> (ParentProfile, account_id)`). The `ParentProfile` model moved to
  `src/shared/billing_parent.py`; `resolve_parent.sql` moved to `src/shared/sql/`. Registered
  in DI (`billing_parent_resolver`). `PaymentSyncQueries.resolve_parent` deleted.
  **Deferred (MANUAL_REVIEW #23):** the other `resolve_parent` callers (charge_card,
  mark_paid_cash, freeze, start) still go through `PaymentSyncService.resolve_parent` (a thin
  delegate) — migrate them to inject `BillingParentResolver` directly later.
- **Freeze → standalone DI service.** `payment_sync_freeze.py` (`PaymentSyncFreeze`).
  `sync_freeze_state(parent, account, *, idempotency_key) -> bool` — pure function of
  `parent.is_frozen` (the DB freeze window), **no DB writes** (the freeze-date write happens
  in the request handler), no explicit flags. `_validate_freeze_params` deleted. Freeze ops
  moved OUT of `PaymentSyncStripe` (now create/update/cancel only).
- **Once-consumption settle → DI service.** `payment_sync_once_discounts.py`
  (`PaymentSyncOnceDiscounts`). `sync_once_discounts(parent, account)`: queries
  `get_unconsumed_once_discounts(family_ids)` (new SQL — `once` + `end_date IS NULL` +
  `stripe_coupon_id IS NOT NULL`), reads live sub coupons (`_current_coupon_ids`), **set
  math** `{coupons} - current` to find consumed, **one batch** `mark_once_consumed(list, today)`.
  The old per-row `_is_consumed_once` predicate and `LineDiscountPlan.consumed_ids` are gone.
- **Dropped `add_ids`/`cancel_ids`.** `update_payments_recurring`/`preview`/`_build_sync_params`
  derive desired state purely from the DB read. Deleted `_resolve_add_intervals`,
  builder `map_add_ids_to_intervals`, queries `get_price_intervals` (+ its SQL), the cancel
  filter. `SyncItem` model still defined (callers import it) but the engine no longer uses it.
- **Docs:** `sync-guide` + `payment_sync.mermaid` were rewritten for Step 1 (now stale again).
  Guardrail callouts added to `sync-guide/SKILL.md` + `FastApiBackend/CLAUDE.md`.

### 3.2 Step 2 — schema, discount math, discount sub-service, proration

**(a) Schema — `stripe_sync_status` (the ONLY schema change; the user ran the migration).**
A real Postgres enum on **both** `member_memberships_unfiltered` and
`member_membership_applied_discounts_unfiltered`, **nullable**:
- `Database/supabase/schemas/member_memberships.sql` — `CREATE TYPE stripe_sync_status AS ENUM
  ('applied','deleted','preview_add','preview_remove','migrating');` (declared here, the
  earliest-loaded consumer) + the column.
- `member_membership_applied_discounts.sql` — the column (type already created).
- **Semantics:** `NULL` = **pending** (row is asking the sync to add it); `applied`/`deleted`
  stamped by the sync (writeback) once Stripe converges; `preview_add`/`preview_remove`
  reserved for preview-staging (not wired); **`migrating` (memberships only)** = migration
  requested, not completed. Kept **orthogonal** to the lifecycle `member_memberships_status`
  view (active/cancelled/ended/frozen) — different axis, distinct name.
- Mirrors: `Database/python_data/schema/member_membership.py` (`StripeSyncStatus` StrEnum +
  nullable field on `MemberMembershipCreate`), `member_membership_applied_discount.py` (field),
  `immutable_columns.py` (added to both frozensets), `schema_db_diagram.io` (both tables).
- ⚠️ **`migrating` was added AFTER the user's last migration run** — tell them to re-run.
- No coupon schema change — `stripe_coupon_id` already stores one coupon per applied-discount
  row; "one coupon per discount" is purely a coupon-id *scheme* (NOT being done — see §4 note).

**(b) Discount math — `_aggregate_values` in `payment_sync_builder.py` (REVIEW-VERIFIED).**
The intended math, now implemented and adversarially verified:
- Within ONE membership (`item_id`), percents compound **sequentially/multiplicatively**:
  `eff = 1 − Π(1 − pⱼ/100)` (30% then 20% → 0.44, NOT 0.50).
- Across memberships consolidated onto one line (same price, qty N), the per-membership
  effective fractions are **additive**, then `÷ quantity`: `line_percent = (Σ eff_i / qty)*100`.
  (A=30%+20%→.44, B=10%→.10, qty 2 → (0.44+0.10)/2*100 = **27%**.)
- Dollars are **summed** per mode (NOT compounded), kept as a **separate** coupon.
- `once` vs `ongoing` kept separate (different Stripe durations: `once` vs `forever`).
- **Dollar↔percent sequencing is NOT computed by us** — they are separate coupons and
  **Stripe applies them in attach order**. Coupons attach **dollar (`amount_off`) BEFORE
  percent (`percent_off`)** (done in `PaymentSyncDiscounts._resolve_line` via
  `sorted(plan.values, key=lambda v: v.percentage_off is not None)`). So Stripe does
  dollar→percent. (Decision history: we verified Stripe stacks discounts *sequentially*, not
  additively, so we keep the **4-bucket sum model** — 2 modes × 2 kinds — and only do the
  percentage-level math; per-discount coupons were considered and **rejected**.)
- Verified examples: 30+20 one member → 44; A=30+20,B=10 qty2 → 27; 100% → 100; percent+dollar
  on one member → two separate values (not compounded); dollars summed not divided.

**(c) `PaymentSyncDiscounts` (`payment_sync_discounts.py`, DI service).**
The discount resolution moved OUT of the orchestrator (`_attach_computed_coupons`/
`_apply_line_plan` deleted) into this sub-service, called from **inside `_build_sync_params`**:
- `resolve(bucket, snapshots, stripe_account_id, today) -> dict[applied_discount_id, coupon_id]`
  — `plan_line_discounts` → for each line, find-or-create coupons (`PaymentSyncCoupons`),
  attach to the bucket item **dollar→percent**, and **collect** the links. **No DB writes**
  (so preview is safe). `__init__(stripe_client)` only — structurally cannot touch the DB.
- `SyncParams` gained `coupon_links: dict[UUID, str]`. The **real** path writes the links
  (`set_snapshot_coupon_id`) — currently an **interim inline loop** in
  `update_payments_recurring`; this moves into the unified writeback (Part D).
- Preview now reflects discounts (it runs the same build/resolve). DI provider
  `payment_sync_discounts = Factory(PaymentSyncDiscounts, stripe_client=stripe_client)`.

**(d) Removed `subscription_discounts` (no member-level discounts, #13 Part A).**
Removed the field from `IntervalBucket` and the 4 `subscription_discounts=bucket...`
pass-throughs in `payment_sync_stripe.py`. **LEFTOVER (finish in Part E #4):** the payments
domain still has `subscription_discounts` on `payments_members_schema.py` (the request schema,
default `[]`), `_build_subscription_discounts` in `payments_subscription_base.py:182`, its
calls in `payments_subscription_create.py`/`payments_subscription_update.py`, and the
sub-level line in the coupon-validation collector (`payments_subscription_base.py:310`). They
now just receive `[]` (harmless) — remove them for completeness.

**(e) Explicit proration (#22).** `proration_behavior: Literal["none","always_invoice"] =
"none"` is now an explicit param on `update_payments_recurring`, `preview_update_payments_recurring`,
`PaymentSyncStripe.execute_sync`/`_sync_bucket`/`preview_execute_sync`. The old
`any(item.prorate ...)` inference and `_resolve_prorate` (builder) are **deleted**. Default
`"none"` matches today's always-none behavior. **Open detail:** `prorate` on
`PaymentsSubscriptionDesiredItem`/`SyncItem` is now **vestigial** — decide whether to drop it.

---

## 4. ✅ DONE — Part E: "discounts ride the membership" (the big restructure)

**This is COMPLETE.** `AppliedDiscount` (renamed from `AppliedDiscountSnapshot`) now rides
`ActiveMembershipRow.discounts`; `get_active_memberships(family_ids, today)` reads memberships +
their **active** discounts in one call (the end_date filter is in SQL now, not `_is_past_end_date`);
the builder groups by `price_id` → `dict[price_id, list[ActiveMembershipRow]]` →
`PaymentSyncDiscounts.resolve(...)` returns a **`ResolvedDiscounts`** (per-price coupons +
`applied_id→coupon` links); `SyncParams` dropped `snapshots`; the payments-side
`subscription_discounts` is gone; "snapshot" is dropped from the engine. The original target spec
is preserved below for reference.

### 4.1 The TARGET architecture (build to THIS — the user's exact vision)
1. **One read.** Query the DB for memberships **and their discounts in one function call**
   (`get_active_memberships(family_ids)` — two queries inside is fine, but one call). Each
   `ActiveMembershipRow` **carries its active discounts**.
2. **Group by price BEFORE building desired items.** Consolidate/group the memberships into a
   `dict[price_id, list[ActiveMembershipRow]]`.
3. **Hand that dict to the discount service.** A `sync_discount_service` (rename of / evolve
   `PaymentSyncDiscounts`) does **all the math** and returns:
   - `dict[price_id, list[coupon]]` — the coupons to attach to each consolidated line, and
   - `dict[applied_discount_id, coupon_id]` — the links to write back.
   - It **checks whether the current (live Stripe) coupons already match**; if they do, it
     **reuses the existing coupon** instead of creating a new one (avoid needless Stripe
     coupon churn / find-or-create when nothing changed).
4. **Then, outside the discount concern,** convert the grouped memberships → desired items →
   bucket → execute → writeback. The discount service's output (per-price coupon lists)
   gets attached to the matching bucket items.
5. **`SyncParams` drops `snapshots` AND `coupon_links`** — they fall out of the items / the
   discount service's return. Ideally `SyncParams = bucket + parent + account`.

### 4.2 Concrete changes Part E implies
- `ActiveMembershipRow` (`payment_sync_schema.py`) gains a `discounts: list[AppliedDiscount]`
  (see rename below). `get_active_memberships` joins the applied discounts (+ their value
  version for percent/dollar/mode) — read the **unfiltered** base tables at service-role
  (half-synced rows with no coupon yet must be visible to the sync), aggregated per membership
  (e.g. one jsonb array per membership, or a second query keyed by `item_id`). **Delete the
  separate `get_applied_discounts` call from `_build_sync_params`.**
- Group memberships by `price_id` → `dict[price_id, list[ActiveMembershipRow]]` before
  `build_desired_items`. (`consolidate_by_price` currently groups *desired items*; this moves
  grouping earlier, onto the membership rows, so the discount service sees the raw per-member
  discounts of each consolidated line.)
- The discount service signature becomes something like
  `resolve(groups: dict[price_id, list[ActiveMembershipRow]], account, today) ->
   (dict[price_id, list[SubscriptionItemDiscount]], dict[applied_id, coupon_id])`. It reuses
  the verified per-membership-sequential math (`_aggregate_values`) — but now reads its inputs
  off the membership rows, not a flat `snapshots` list grouped by `stripe_item_id`. **This
  also fixes the "new line skipped" gotcha** (today `plan_line_discounts` skips items with no
  `stripe_item_id`; matching by `member_id`/`price_id` at build time removes that join-key
  dependency — MANUAL_REVIEW #18).
- **"Reuse current coupon if it matches"** — read the live sub's current coupons (the
  `_current_coupon_ids` read that lives in `PaymentSyncOnceDiscounts` today) and, when the
  computed value maps to a coupon already on the line, reuse it instead of find-or-create.
  (PaymentSyncCoupons' ids are already deterministic by value+mode, so "matches" = same id.)
- Finish removing the **payments-side `subscription_discounts`** (§3.2d leftover).
- **Rename — drop "snapshot":** `AppliedDiscountSnapshot` → **`AppliedDiscount`**;
  `_parse_snapshot_row` → `_parse_applied_discount_row`; `set_snapshot_coupon_id`(+ `.sql`) →
  applied-discount-coupon names; the `get_applied_discounts_by_member.sql` comment + every
  "snapshot" in payment_sync comments/docstrings → "applied discount". (Refs:
  `payment_sync_schema.py`, `payment_sync_queries.py`, `payment_sync_builder.py`,
  `payment_sync_discounts.py`, and `tests/.../test_payment_sync_builder.py`.) Note
  `discounts-guide` uses "snapshot" as a defined term — decide whether to rename there too.

### 4.3 Execution order (keep the engine compiling at every step)
read-returns-discounts (ActiveMembershipRow.discounts) → group-by-price → discount-service-
takes-the-dict-and-returns-coupons+links → attach to items / drop `SyncParams.snapshots` →
remove payments-side sub-discounts → rename `AppliedDiscountSnapshot`→`AppliedDiscount`.
**The verified math (§3.2b) does not change — only where it reads its inputs.**

---

## 5. WHAT'S LEFT — Part D: unified `PaymentSyncWriteback`

Merge `price_writeback.py` (`PriceWriteback`) into one `payment_sync_writeback.py`
(`PaymentSyncWriteback`) that, in the **real path only**, does all writebacks **via
`PaymentSyncQueries`** (today `PriceWriteback` runs its own `db_pool` SQL and re-resolves
family ids itself):
1. **Coupon links** — the `applied_discount_id → coupon_id` map (batched
   `set_snapshot_coupon_id`). Currently an interim inline loop in `update_payments_recurring`.
2. **Sync status** — stamp `member_memberships`/`member_membership_applied_discounts`
   `stripe_sync_status` = `applied` on synced rows, `deleted` on rows removed from the live
   sub, after Stripe succeeds (#16/#17). This is NEW wiring — the column exists (Step 2a) but
   nothing stamps it yet. Decide the exact "what becomes `deleted`" rule (#17: should-be-gone
   ∧ confirmed-absent-from-live-sub).
3. **Sub id** — `update_profile_sub_id` (move out of the orchestrator).
4. **Price totals** — the existing post-discount fan-out + parent monthly total from the
   upcoming invoice (the current `PriceWriteback` body).
Move `sync_prices_by_plan.sql` / `sync_profile_monthly_total.sql` / `get_family_ids` loads into
`PaymentSyncQueries` methods. Take the already-resolved parent/family from the sync.

---

## 6. Tests + callers (the "restore function" work — deferred from Step 1/2)

**The engine is intentionally NON-FUNCTIONAL at the caller layer.** Step 1 was engine-only;
the 6 lifecycle callers were knowingly left broken and tests left red. Per `FastApiBackend/
CLAUDE.md` **never reshape a test to pass against a broken path** — fix the caller/engine.

- **Broken callers** (pass removed kwargs `add_ids`/`cancel_ids`/freeze params): `member_
  memberships_start.py`, `member_memberships_cancel.py`, `member_memberships_update_price.py`,
  `member_memberships_freeze.py`, `members/service/management/members_management_linked.py`.
  These need the **DB-first rewiring (#16/#17)** to restore function: write the desired DB
  state first (new row pending = `stripe_sync_status NULL`; cancel via `cancel_date` +
  `deleted`; freeze writes the freeze window then calls `PaymentSyncFreeze`), then call the
  param-less sync which derives everything from the DB. This is the work that makes the engine
  functional again.
- **Stale tests** (refactor drift, not bugs — update, don't camouflage):
  - `tests/member_memberships/service/payment_sync/test_payment_sync_builder.py` — all fail:
    `plan_line_discounts` lost its `current_coupon_ids` arg; `LineDiscountPlan.consumed_ids`
    removed. **The 4 once-consumption tests belong on `PaymentSyncOnceDiscounts` now**, not the
    builder. **Add a same-`item_id` test** locking the new sequential math (30+20 one member → 44).
  - `tests/helpers/service_factory.py` — builds `PaymentSyncService` with the OLD constructor;
    new args are `(db_pool, subscription_service, parent_resolver, freeze, once_discounts,
    discounts)`. This breaks `test_price_writeback.py` + `test_discount_semantics.py` at setup.
  - **No tests yet** for `PaymentSyncDiscounts` or `PaymentSyncOnceDiscounts` — add them.
  - `test_payment_sync_coupons.py` — still passes (coupon-id format unchanged).
- **Don't add tests for retired routes/behaviors**; delete tests for removed paths.

---

## 7. Known issues / gotchas (don't get surprised)

- **`member_memberships` view filters `WHERE stripe_item_id IS NOT NULL`** — a just-inserted
  pending row is invisible to the sync's read. This is why callers can't just "insert then
  sync" yet; the DB-first rewiring (#16) handles new rows via `stripe_sync_status NULL`.
- **Latent once-handle fragility (pre-existing, NOT introduced):** when a single consolidated
  line carries BOTH a percent AND a dollar `once`, both `LineDiscountValue`s share the same
  `contributing_ids` (`mode_ids`), so the dollar-only `once` ends up storing the *percent*
  coupon as its handle (last-write-wins, dollar attaches first). Consumption still works
  because same-mode coupons are invoiced/dropped together. Fix later: give percent vs dollar
  values **disjoint** `contributing_ids`.
- **Preview over-states a consumed-but-unstamped `once`** on an idle member (preview skips the
  settle, which is a write). No write occurs; the preview number is optimistic until the next
  real sync stamps it.
- **Consolidated fixed-dollar discount applies to the whole qty-N line**, not one member
  (percents are split ÷qty; dollars are summed). Inherent to Stripe coupon semantics on a
  quantity line — flag in product terms if family + fixed-dollar combos are common.
- **`prorate` field is vestigial** now (proration is an explicit call param). Decide: keep as
  a record or drop.
- **Idempotency keys are suffixed** per Stripe sub-op (`:sub_create/:sub_update/:sub_cancel/
  :freeze/:unfreeze`); `bulk_payment_sync` mints a fresh `uuid4()` per member.

---

## 8. Sub-service map (current files under `payment_sync/`)

- `payment_sync_service.py` — `PaymentSyncService` orchestrator (update/preview/bulk/resolve_parent).
  Injects: `_parent` (BillingParentResolver), `_freeze`, `_once_discounts`, **`_builder`**; builds
  `_queries`, `_stripe`, `_price_writeback` internally. (`_build_sync_params` moved OUT to the builder.)
- `payment_sync_builder.py` — **`PaymentSyncBuilder` service** (DI: `db_pool` + `discounts`):
  `build_sync_params` (the read + orchestration) → `_group_by_price` / `_build_bucket`. No loose
  module functions; the discount math is NOT here anymore.
- `payment_sync_discounts.py` — `PaymentSyncDiscounts` (DI: **`discount_service`**). Owns ALL
  discount math (`_aggregate_line_values`; no `_is_past_end_date` — the end_date filter is in SQL)
  + `resolve(groups, account) -> ResolvedDiscounts`; builds `PaymentSyncCoupons` internally.
- `payment_sync_coupons.py` — `PaymentSyncCoupons` — id scheme + validate-or-replace **policy only**;
  **delegates all coupon I/O to `PaymentsStripeDiscountService`** (no Stripe SDK import). ids
  `pct_<bps>_<mode>` / `amt_<cents>_<mode>`, gym-wide reuse, no registry table.
- `payment_sync_freeze.py` — `PaymentSyncFreeze` (DB-first pause_collection).
- `payment_sync_once_discounts.py` — `PaymentSyncOnceDiscounts` (pre-sync once-consumption settle).
- `payment_sync_queries.py` — `PaymentSyncQueries` (get_family_ids; `get_active_memberships(ids,
  today)` + private `_get_discounts_by_item`; get_unconsumed_once_discounts;
  `set_applied_discount_coupon_id`; mark_once_consumed; update_profile_sub_id; + price-writeback SQL
  not yet routed here).
- `payment_sync_stripe.py` — `PaymentSyncStripe` (execute_sync/preview/_sync_bucket; create/
  update/cancel only — freeze removed; explicit `proration_behavior` on create + update).
- `price_writeback.py` — `PriceWriteback` (to be merged into `PaymentSyncWriteback`, Part D).
- shared: `src/shared/billing_parent.py` (`ParentProfile`), `billing_parent_resolver.py`
  (`BillingParentResolver`), `src/shared/sql/resolve_parent.sql`.
- payments layer: **`PaymentsStripeDiscountService`** now owns all low-level coupon I/O
  (`find_discount` / `create_discount`-with-`coupon_id` / `delete_discount` / `retrieve_discount`);
  `StripeCouponMetadata` + dead `update_discount` removed.
- DI: `src/core/dependencies.py` — providers `billing_parent_resolver`, `payment_sync_freeze`,
  `payment_sync_once_discounts`, `payment_sync_discounts`, **`payment_sync_builder`**,
  `payment_sync_service`.

---

## 9. MANUAL_REVIEW item mapping

- #13 Part A remove subscription_discounts → ✅ DONE (both payment_sync + payments side). Part C
  per-discount coupons → **REJECTED** (kept the 4-bucket sum model — see §3.2b). Part B preview-aware
  discounts → ✅ (preview resolves coupons); the `preview_*` staging statuses → ❌ not wired.
- #14 freeze split → ✅ `PaymentSyncFreeze`.
- #15 `_SyncParams` → schema → ✅ `SyncParams`.
- #16/#17 DB-first + sync-status + full writeback → 🟡 schema column DONE; the stamping (Part D) +
  caller rewiring (§6) + read-filters NOT done.
- #18 attach discounts to the desired item (not a separate list) → ✅ DONE (Part E).
- #19 preview due-now + recurring split → ❌ not done (preview now shows discounts, a prerequisite).
- #20 extract once-consumption/end_date settle → ✅ `PaymentSyncOnceDiscounts`.
- #21 `update_payments_recurring -> None` → ❌ not done (still returns the sub response).
- #22 explicit proration → ✅ DONE (incl. create-path `item.prorate` removal).
- #23 shared `BillingParentResolver` → 🟡 resolver DONE; caller migration deferred.
- #24 (new) coupon I/O → `PaymentsStripeDiscountService`; `crm_discount_id` / `StripeCouponMetadata`
  removed → ✅ DONE.
- #25 (new) concurrency / global member lock → ❌ to design (§11).

---

## 10. The cardinal rules (repeat)
1. **One approved piece at a time. Never a big sweep.** Propose → wait → write.
2. **Never run migrations or seeds** — the user does. Tell them when a schema change needs a
   re-run (e.g. `migrating`).
3. **Update the living docs** (`sync-guide`, `discounts-guide`, `payment_sync.mermaid`) in the
   **same change** that stabilizes the engine.
4. **Never reshape a test to pass against a broken path** — fix the engine/caller.
5. **Verify every change**: `py_compile` + `ruff` + DI build. The math is billing — when in
   doubt, trace a concrete dollar example.

---

## 11. Concurrency / global member lock (NEW — to design + build)

**The need:** while one admin is editing/syncing a member, no one else (admin, bulk job, or a
second tab) may run a conflicting edit/sync on the **same paying-parent family**. Today there is
**zero** concurrency guard: two concurrent `update_payments_recurring` on the same family both
read DB state, both call Stripe, and both write back last-write-wins (the sync is a
multi-transaction cascade with Stripe calls in the middle — `payment_sync_service.py`). On
billing-critical code this can mis-bill or desync Stripe↔CRM.

**Does Postgres/Supabase support this? — YES, two native mechanisms** (Supabase *is* Postgres):
- **`SELECT … FOR UPDATE`** (pessimistic row lock) — locks the row for the life of ONE
  transaction. **Not sufficient alone here:** our `DirectDatabasePool.session()` is one
  transaction per call, and the sync spans many transactions across Stripe HTTP calls; holding a
  row lock across network I/O would pin a pooled connection for the whole sync. Only one prior use
  in the repo: `rewards/sql/redeem_reward.sql` (a single-transaction CTE).
- **Advisory locks** — `pg_advisory_lock(key)` (session-scoped, held until unlocked/disconnect)
  / `pg_advisory_xact_lock(key)` (auto-released at txn end) / `pg_try_advisory_lock(key)`
  (non-blocking, returns false if held). A named lock on an arbitrary `bigint` key, e.g.
  `hashtext(parent_member_id::text)`. **This is the right tool** — acquire once at the start of
  the operation, do the whole DB+Stripe sequence, release at the end; a second operation on the
  same key blocks (or fails fast). No new columns.

**Recommended design (to confirm):** a **per-parent advisory lock** keyed on the resolved
paying-parent `member_id`. Resolve parent (already step 1 of the sync, via `BillingParentResolver`),
then `pg_try_advisory_lock(hashtext(parent_member_id))` — on failure return a **409 "this member
is being updated, try again"** (fail fast, don't queue). Hold it across the mutate-DB-then-sync
sequence, release in a `finally`. Per-parent (NOT one global lock for all members — that would
serialize the whole gym). Lock key is the parent so a child edit and a parent edit can't race the
shared family subscription.

**Two flavors — pick which (or both):**
- **(a) Backend operation serialization** (the billing-correctness need): advisory lock around the
  mutate+sync operation. Requires holding the lock on a dedicated connection for the operation's
  duration (acquire → run → release), OR a short lock-row with a transaction.
- **(b) UI edit-session lock** ("Bob is editing this member; you see read-only"): a `member_locks`
  table (`member_id PK, locked_by, locked_at, expires_at`) with a TTL + heartbeat, since a human
  may walk away. Postgres handles this trivially (just rows).

**Open questions:** (a) vs (b) vs both; lock granularity (parent `member_id` confirmed); fail-fast
409 vs block-with-timeout; where the lock attaches (a shared decorator/context manager around the
lifecycle callers + the sync entry points). This interacts with the **#16 caller rewiring** — the
natural place to add the lock is the same DB-first rewiring of the lifecycle callers.
