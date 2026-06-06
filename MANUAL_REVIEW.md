# Manual Review

Running log of the request-by-request audit. Each entry is one request/item as it's reviewed.

---

## ⚙️ Membership-refactor worktree — payment-sync items, current status

The `membership-refactor-step1` worktree implemented a large chunk of the payment-sync items
below (#13–#23). Snapshot of where each stands — full handoff in
`FastApiBackend/TODO_SYNC_REFACTOR.md`:

| Item | Status |
| --- | --- |
| #13 Part A — remove subscription-level discounts | ✅ DONE (payment_sync + payments side) |
| #13 Part B — preview shows discounts | ✅ DONE (preview resolves coupons); `preview_*` staging statuses ❌ not wired |
| #13 Part C — per-discount coupons | ❌ **REJECTED** — kept the 4-bucket sum model (Stripe stacks sequentially, so we sum ourselves; per-membership-sequential percent math verified) |
| #14 — split explicit freeze into its own service | ✅ DONE (`PaymentSyncFreeze`) |
| #15 — `_SyncParams` → schema | ✅ DONE (`SyncParams`) |
| #16 — DB-first + `stripe_sync_status` enum | 🟡 schema column DONE; caller rewiring + status stamping ❌ not done |
| #17 — full writeback | ❌ not done (Part D — unified `PaymentSyncWriteback`) |
| #18 — discounts ride the membership/item (drop the parallel list) | ✅ DONE ("Part E") |
| #19 — preview due-now vs recurring split | ❌ not done |
| #20 — extract once-consumption/end_date settle | ✅ DONE (`PaymentSyncOnceDiscounts`) |
| #21 — `update_payments_recurring -> None` | ❌ not done |
| #22 — explicit `proration_behavior` | ✅ DONE (incl. create-path `item.prorate` removal) |
| #23 — shared `BillingParentResolver` | 🟡 resolver DONE; caller migration deferred |
| #24 (NEW) — coupon I/O via `PaymentsStripeDiscountService` | ✅ DONE |
| #25 (NEW) — concurrency / global member lock | ❌ to design |

Also done this session (not original audit items): the verified per-membership-sequential discount
math; `ResolvedDiscounts` model (no tuple); `LineDiscountValue` bounds + XOR validators; the
date-lifetime filter moved into SQL (`:today`); dead `IntervalBucket.total_price` removed;
`sync-guide` + `payments-guide` brought current. **The engine is non-functional at the caller layer**
until #16 (caller rewiring) lands.

---

## 1. `POST /api/v1/gyms/` — gym create asks for `owner_email` but ignores it

**Status:** ✅ Fixed — removed `owner_email` from `GymCreateRequest`, dropped it from the router test body, and surgically removed it from the OpenAPI dump (it was optional / not in `required`, so the edit matches a fresh regen). Recommend running `make update-openapi` (Database/) against a live backend at next opportunity to confirm. All 6 gyms router tests pass.

**Finding:** The create request body carries `owner_email` (`GymCreateRequest`, `FastApiBackend/src/gyms/schema/gyms_schema.py:22`), but it is never read. The router instead takes the email straight from the authenticated user's JWT (`user_payload.get("email")`, `gyms_router.py:81`) and passes that as `user_email` into the service. The JWT email is what's used for both the owner `gym_employees` row (`gyms_create_service.py:143`) and the Stripe Express account (`gyms_create_service.py:79`). `grep` confirms `request.owner_email` has zero readers. So the client is asked for an email the backend discards.

**Proposed fix:** Remove `owner_email` from `GymCreateRequest` — email already comes from the authenticated user (JWT). (Note: `owner_phone` *is* used, so it stays.)

**Files:** `FastApiBackend/src/gyms/schema/gyms_schema.py`, `FastApiBackend/src/gyms/gyms_router.py` (no change needed — already JWT-sourced)

## 2. `GymsService` — dead no-Stripe path (test scaffolding in prod)

**Status:** ✅ Fixed — `stripe_connect_service` is now required, `_create_service`/`_onboarding_service` always built, `_create_gym_no_stripe` deleted, `create_gym` branch flattened (kept the empty-`user_email` guard for zero behavior change), and the two `if ... is None: raise ValueError` onboarding guards removed. Class docstring updated. Compiles clean; all 6 gyms router tests pass.

**Finding:** `GymsService` (`FastApiBackend/src/gyms/service/gyms_service.py`) treats `stripe_connect_service` as optional (`| None = None`) and carries a "legacy non-Stripe" fallback: when it's `None`, `_create_service`/`_onboarding_service` are never built, `create_gym` falls through to `_create_gym_no_stripe` (which only `raise NotImplementedError`), and `get_onboarding_status`/`get_fresh_onboarding_link` raise `ValueError("Stripe Connect is not configured")`. None of this is reachable:
- DI always injects a real `GymsStripeConnectService` (`dependencies.py:237-241`) — never `None`.
- The router test overrides the whole service with a mock (`test_gyms_router.py:27`), so it never hits the `None` path.
- The fallback method is a pure `NotImplementedError` stub — it implements nothing.

It's leftover test/dev scaffolding living in the prod code path. A gym always has a Stripe account, so the branch is unnecessary.

**Proposed fix:** Remove the no-Stripe path entirely:
- `__init__`: make `stripe_connect_service: GymsStripeConnectService` required (drop `| None`), always build `_create_service` + `_onboarding_service`, drop the `| None` on those attrs.
- `create_gym`: drop the `if self._create_service is not None` branch and delete `_create_gym_no_stripe`. (Decide: make `user_email: str` required vs. keep the empty-string guard.)
- `get_onboarding_status` / `get_fresh_onboarding_link`: drop the `if ... is None: raise ValueError` guards.
- Update the class docstring that documents the optional/legacy behavior.

**Files:** `FastApiBackend/src/gyms/service/gyms_service.py`


## 4. `GymStripeAccountSnapshot` — should be Pydantic + live in schema, and is duplicated

**Status:** 🟡 Needs decision — deferred (entangled with the bug in #6)

**Finding:** `GymStripeAccountSnapshot` is a `@dataclass(frozen=True)` in `gyms_status_mapping.py:20`. Per project conventions it should be a Pydantic model and live in a schema file (e.g. `gyms_schema.py`), not in a service module. It's also **duplicated**: `account_updated_handler.py:33` defines a near-identical `_GymStripeAccountSnapshot` with its own `_map_account_to_snapshot`, even though `gyms_status_mapping.py` exists explicitly to be the single shared mapper ("Keeping this in one place prevents drift between paths"). The two have already drifted (see #6).

**Proposed fix (needs the #6 decision first):** Make it a Pydantic model in schema, delete the webhook's private copy, and have `AccountUpdatedHandler` import the one canonical snapshot + mapper from the gyms domain. Consolidating changes webhook behavior, so it can't land until the `disabled` question (#6) is decided.

**Files:** `FastApiBackend/src/gyms/service/gyms_status_mapping.py`, `FastApiBackend/src/gyms/schema/gyms_schema.py`, `FastApiBackend/src/stripe_webhooks/service/account_updated_handler.py`

## 5. Gym onboarding status constants should be an enum

**Status:** 🟡 Needs decision — deferred

**Finding:** `GYM_STATUS_NOT_STARTED/PENDING/COMPLETE` are bare module-level string constants (`gyms_status_mapping.py:15-17`), and the webhook redefines its own `GYM_STATUS_PENDING/COMPLETE/DISABLED` (`account_updated_handler.py:28-30`). Both repo conventions say this should be an enum: FastApiBackend ("ALWAYS use enums instead of raw strings … reuse enums from the Database package") and Database ("Always use real Postgres enums … mirror every Postgres enum with a `StrEnum` in `python_data/schema`").

**Canonical home — and it does NOT exist yet:** Per the Database convention the enum should live in the **Database shared schema** (`Database/python_data/schema/gym.py`) as a `StrEnum`, mirrored by a real Postgres `CREATE TYPE`, and the backend should import it (`from schema.gym import <Enum>`) — exactly how every other enum works. Checked: there is currently **no** such enum anywhere — `gyms.sql:12-14` is `TEXT` + `CHECK` (no `CREATE TYPE`), there's no `StrEnum` in `python_data/schema`, and `gym.py`'s `GymCreate` doesn't even carry `stripe_onboarding_status`. So this is "create the canonical enum in the shared schema and reuse it," not "wire up an existing one."

**Proposed fix (needs decision):** Add the canonical `StrEnum` in `Database/python_data/schema/gym.py`; have the backend import it instead of redefining string constants in `gyms_status_mapping.py` / `account_updated_handler.py`. **Decisions:** (a) convert the DB column to a Postgres enum (a schema migration — user runs migrations manually) or keep TEXT+CHECK and just add the Python `StrEnum`? (b) does the enum include `disabled` (depends on #6)?

**Files:** `Database/python_data/schema/gym.py`, `Database/supabase/schemas/gyms.sql`, `FastApiBackend/src/gyms/service/gyms_status_mapping.py`, `account_updated_handler.py`

## 7. `_get(obj, key, default)` helper — confusing, but load-bearing as written (don't naively replace with `.get()`)

**Status:** 🟡 Cleanup — fold into the #4 consolidation

**Finding:** `gyms_status_mapping.py:74` and `account_updated_handler.py:119` both define `_get(obj, key, default)` doing "attribute-or-key lookup so we work on objects and dicts alike." It reads oddly, but it exists for a real reason: the two callers feed **different input types**, and in stripe 15.2.0 they support *mutually exclusive* access:
- Status-refresh path passes a `stripe.Account` object (`retrieve_account`, `gyms_stripe_connect_service.py:131`). Verified: in stripe 15.2.0 `stripe.Account` is **not** a dict and has **no `.get()`** (`acct.get(...)` → `AttributeError`); only attribute access works.
- Webhook path passes `event["data"]["object"]`, a plain **dict** — only `.get()`/`[]` works, no attributes.

So `_get` bridges both. **Naively replacing it with `.get()` would crash the status-refresh path** — worth recording because that's the obvious "fix" and it's wrong here. (In the webhook handler, where the input is always a dict — it even asserts `isinstance(account, dict)` — the local `_get` *is* redundant and could be plain `.get()`.)

**Proposed fix (clean):** Normalize the Stripe object to a plain dict at the boundary — `stripe.Account.to_dict()` returns a fully plain nested dict (verified) — then the single canonical mapper uses plain `dict.get()` and `_get` is deleted. This rides along with the #4 consolidation (one Pydantic snapshot + one mapper): normalize to dict → `.get()` everywhere → no helper.

**Files:** `FastApiBackend/src/gyms/service/gyms_status_mapping.py`, `FastApiBackend/src/stripe_webhooks/service/account_updated_handler.py`

## 6. 🔴 BUG — `account.updated` webhook writes `"disabled"`, which violates the DB CHECK constraint

**Status:** 🔴 Live bug — needs decision on intended behavior

**Finding:** `AccountUpdatedHandler._map_account_to_snapshot` (`account_updated_handler.py:103-108`) maps an account with `requirements.disabled_reason` set to `status="disabled"` and writes it to `gyms.stripe_onboarding_status` via `gyms_set_onboarding_status.sql`. But the column's CHECK constraint (`gyms.sql:14`) only allows `'not_started','pending','complete'`. The handler is **wired and live** (`stripe_webhooks_service.py:177`). So when Stripe disables a connected account, the webhook's UPDATE raises a constraint violation → the event fails and Stripe keeps retrying. The canonical mapper in `gyms_status_mapping.py` does NOT have this bug (it never emits `disabled`; it surfaces `disabled_reason` in the API payload only).

**Two ways to fix — pick one (drives #4 and #5):**
1. **`disabled` is not a real status:** fix the webhook to map disabled→`pending` (matching the canonical mapper); surface `disabled_reason` only in API responses, not the DB column. No schema change. Smallest fix; consistent with the existing constraint + status-refresh endpoint.
2. **`disabled` becomes a real 4th status:** add `'disabled'` to the DB constraint/enum, the StrEnum, and the onboarding response model, and keep the webhook writing it. Requires a schema migration and product handling for the disabled state in the CRM.

**Files:** `FastApiBackend/src/stripe_webhooks/service/account_updated_handler.py`, `Database/supabase/schemas/gyms.sql` (option 2), `FastApiBackend/src/gyms/service/gyms_status_mapping.py`

## 8. `DiscountUpdateRequest` — split into `identity` + `values`; drop the frozensets

**Status:** 🟡 Logged for fix phase (discounts-only, per user) — shape confirmed, not implementing now

**Finding / proposal (user):** The discount update model should carry two sub-objects — `identity:` and `values:` — instead of a flat `data`. The request shape then *encodes* what to update, so the service derives behavior from structure rather than from frozensets.

**Why it fits discounts well:** A discount is a two-table model — a stable IDENTITY row (`gym_discounts`: name + type) and a chain of immutable VALUE versions (`gym_discount_values`). The current `update_discount` re-derives that split at runtime using **two** frozensets:
- `validate_mutable_columns(GYM_DISCOUNTS, …)` — the shared immutable-columns guard from `Database/python_data/schema/immutable_columns.py` (`discounts_update.py:75`).
- a **local** `VALUE_FIELDS` frozenset (`discounts_update.py:38-47`) partitioning changed fields into "rename identity" vs. "mint new version."

With an `identity` / `values` model:
- `identity` = `{ discount_name }` → update the `gym_discounts` row in place.
- `values` = `{ percentage_off, dollar_off, discount_mode, duration_amount, duration_unit, end_date }` → mint a new `gym_discount_values` version.
- PKs (`discount_id`, `gym_id`) stay as identity *keys* (top-level or in `identity`).
- The local `VALUE_FIELDS` frozenset disappears (the model shape *is* the partition), and `validate_mutable_columns` is unnecessary for this path (the model can only carry mutable fields, already split by destination).

**Note — the guard is already near-redundant for discounts:** `DiscountUpdateData` only contains mutable fields, and the update SQL is *static* (`discounts_update.sql` sets only `discount_name`; `discount_values_insert.sql` inserts a fresh row). So no immutable column can be written today regardless of the guard — making this low-risk *for discounts*. (Contrast: `gyms.update_gym` builds its `SET` clause dynamically, where the guard does real work.)

**Scope (confirmed by user): discounts only.** `immutable_columns.py` stays as-is for the other 5 update services (members, gyms, rewards, ranks, waivers, plans) — this change only drops the `GYM_DISCOUNTS` guard call + the local `VALUE_FIELDS` frozenset on the discount update path, not the shared convention. (Note: `GYM_DISCOUNTS` frozenset can stay defined in `immutable_columns.py`; we just stop using it here. Confirm whether to also remove the now-unused `GYM_DISCOUNTS` entry — only if nothing else references it.)

**Proposed model shape (to confirm):**
```python
class DiscountUpdateIdentity(BaseModel):   # → gym_discounts row (rename in place)
    discount_name: str | None = None

class DiscountUpdateValues(BaseModel):     # → new gym_discount_values version
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode | None = None
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None

class DiscountUpdateRequest(BaseModel):
    discount_id: UUID
    gym_id: UUID
    identity: DiscountUpdateIdentity | None = None
    values: DiscountUpdateValues | None = None
    # model_validator: at least one of identity/values must be present
```
Service then: `if request.identity` → rename; `if request.values` → mint new version. No `VALUE_FIELDS`, no `validate_mutable_columns`. The per-field validators (name non-empty, pct range, dollar > 0, duration > 0) move onto the two sub-models; the merged-state + lifetime validation stays in `_new_version`.

**Keys placement (decided): top-level** — `discount_id`/`gym_id` stay top-level on `DiscountUpdateRequest` (per user; keeps the auth `gym_id` check simplest).

**Blast radius (discounts-only):** `discounts_schema.py`, `discounts_update.py`, the CRM discount-update client call, `Database/openapi.json`, and the discount update tests. Loosely ties to #3 (this is the "reshape `data`" alternative, applied just here).

**Files:** `FastApiBackend/src/discounts/schema/discounts_schema.py`, `FastApiBackend/src/discounts/service/discounts/discounts_update.py`, CRM discount-update repository call, `Database/openapi.json`

## 9. `classes_checkin_service.py` (467 lines) — too big; split into subclasses under a `checkin/` subdir

**Status:** 🟡 Needs decision — deferred (refactor; partition choice + test moves)

**Finding:** `ClassesCheckinService` (`src/classes/service/classes_checkin_service.py`, 467 lines — 2nd-largest service file) does too much in one class: orchestration, several DB reads, the transactional write + auto-end, pure plan-selection logic, and response building. Per the FastApiBackend convention (*Service-Layer Organization*: "When a service grows past one file, its pieces live in a subfolder under `service/`" with the orchestrator `*_service.py` **inside** that subfolder), it should be split.

**Proposed partition (to confirm) — new `src/classes/service/checkin/`:**
- `classes_checkin_service.py` — orchestrator: `checkin()` composing the pieces below.
- `classes_checkin_repository.py` — the reads: `_resolve_class_id`, `_get_existing_attendance`, `_get_eligible_plans`, `_resolve_item_id`, `_active_memberships`.
- `classes_checkin_writer.py` — the write path: `_write_checkin`, `_end_membership` (+ `_FALLBACK_TIMEZONE`).
- `classes_checkin_plan_selector.py` — pure logic: `_select_best_plan`, `_sort_plans_by_priority`, `_should_end_membership` (+ `_PLAN_TYPE_PRIORITY`, `_UNLIMITED`).
- response builders (`_already_checked_in`, `_rejected`, `_build_breakdown`) — either a small `classes_checkin_responses.py` concern module or kept on the orchestrator.

**Blast radius:**
- Import path moves `src.classes.service.classes_checkin_service` → `src.classes.service.checkin.classes_checkin_service`: update `classes_router.py:16`, `dependencies.py:3` (+ DI wiring at `:116`, and `wiring_config.modules` if the module path is listed).
- **Tests:** `tests/test_classes_checkin_service.py` unit-tests the pure methods directly (`ClassesCheckinService._select_best_plan/_should_end_membership/_build_breakdown`). If those move to `classes_checkin_plan_selector` / a responses module, the tests must be repointed. The partition choice directly affects these tests.

**Decision needed:** confirm the partition (esp. where the pure logic + response builders land, since that drives the test rewrite) and whether the orchestrator composes the sub-pieces via DI providers or constructs them internally.

**Files:** `FastApiBackend/src/classes/service/checkin/*` (new), `src/classes/classes_router.py`, `src/core/dependencies.py`, `tests/test_classes_checkin_service.py`

## 10. `classes` domain routed `PlanType` through a local re-export instead of the global enum

**Status:** ✅ Fixed

**Finding:** Every other domain imports the canonical enum directly (`from schema.membership_plan import PlanType`), but the `classes` domain imported it from a local module `src/classes/schema/classes_plan_type.py` that just re-exported the global one. Four files used the indirection.

**Fix:** Redirected all 4 consumers (`classes_schema.py`, `classes_cycle_counts_schema.py`, `classes_checkin_service.py`, `classes_cycle_counts_service.py`) to `from schema.membership_plan import PlanType`. `classes_plan_type.py` stays (it still defines `PlanInfo`, which legitimately uses `PlanType`); it's now imported only for `PlanInfo`. Did **not** add per-file `import src.shared.db_schema_path` — registration is global at `src/main.py:7` (confirmed: peer `members_billing_schema.py` imports from `schema.*` with no local registration). 11 classes checkin tests pass.

**Optional follow-up (not done):** `classes_plan_type.py` now holds only `PlanInfo`, so the filename is slightly misleading — could rename to `classes_plan_info.py` (touches one import in `classes_checkin_service.py`).

**Files:** `FastApiBackend/src/classes/schema/classes_schema.py`, `classes_cycle_counts_schema.py`, `src/classes/service/classes_checkin_service.py`, `classes_cycle_counts_service.py`

## 11. Check-in breakdown should expose the renewal date (recurring only)

**Status:** 🟡 Logged — small feature (data already computed)

**Finding (user):** `CheckinMembershipBreakdown` should return the renewal date when one exists, and `None` for trial / one-time plans.

**Good news — the data is already there, just dropped:** the cycle-counts query `classes_all_memberships.sql:10` already SELECTs `ms.next_due_date` (the next-due / renewal date from the `member_memberships_status` view; the cycle window is `[last_paid_date | start_date, next_due_date)`). It's discarded because `MembershipUsage` has no field for it. There's **no** stored `renew_date` column on `member_memberships` (recurring plans can't even have an `end_date`), so `next_due_date` from the status view is the right source.

**Proposed implementation:**
- Add `renew_date: date | None` to `MembershipUsage` (`classes_cycle_counts_schema.py`) and `CheckinMembershipBreakdown` (`classes_schema.py`).
- Map `ms.next_due_date` → `renew_date` in `ClassesCycleCountsService` (row → `MembershipUsage`); carry it through `_build_breakdown` (`classes_checkin_service.py`). No SQL change needed — the column is already selected.
- Trial / one-time → `None`: **verify** whether `member_memberships_status.next_due_date` is already NULL for non-recurring plans; if not, force `None` when `plan_type != recurring`.
- `Database/openapi.json` regen for the new field.

**Open detail:** confirm the view's `next_due_date` semantics for trial/one_time before deciding whether to trust it or force `None`.

**Files:** `FastApiBackend/src/classes/schema/classes_cycle_counts_schema.py`, `classes_schema.py`, `src/classes/service/classes_cycle_counts_service.py`, `classes_checkin_service.py`, `Database/openapi.json`

## 12. NEW FEATURE — start multiple memberships atomically (one transaction, not N separate ones)

**Status:** 🟦 Feature — needs a design pass before building (100% needed, per user)

**Requirement (user):** Add a way to add + start **multiple** memberships at once for a member. It must **not** be separate transactions — partial success (some memberships started + charged, others failed) is unacceptable.

**Current single-start flow** (`POST /api/v1/member_memberships/start`, `member_memberships_start.py` — the largest service file, 474 lines): one `MemberMembershipsStartRequest` = one `plan_id`/`price_id`. DB-first insert one row → Stripe → set `stripe_item_id` → on any error, clean up the single pending row.

**What's already feasible vs. the hard parts:**
- ✅ **Recurring batch:** `update_payments_recurring(member_id, add_ids=[…], cancel_ids=[…], …)` already takes a **list** (`:154`). N recurring adds → one subscription sync → one combined invoice/proration. Low difficulty — the orchestrator just passes all recurring adds in one call instead of one-at-a-time.
- ⚠️ **One-time batch:** `_charge_one_time` → `create_invoice_payment` is single-price-per-invoice (`:448-458`). Combining N one-time memberships into ONE invoice requires a payments-layer change (multi-line invoice / multiple prices on one invoice).
- 🔴 **Mixed (recurring + one-time together):** Stripe has **no cross-object atomic transaction** — a sub sync and a one-time invoice are distinct Stripe operations. "One transaction" can't be literal here. Achievable guarantee = **DB atomic** (all rows in one DB transaction) + combined invoicing per type + a **compensation/rollback** path that tears down any Stripe objects already created (and the DB rows) if a later step fails.

**Design decisions needed (don't assume — design pass):**
1. **Request shape:** batch model — `member_id`, `gym_id`, one `idempotency_key`, `list[item]` where each item = `{plan_id, price_id, prorate, paid_with_cash}`. Plus a validator for intra-batch conflicts (no two items for the same plan; the existing "one active membership per plan" check must also consider the batch as a set).
2. **Atomicity contract:** define precisely — DB single transaction (easy); recurring → single sync call; one-time → single combined invoice (needs payments change) or accept multiple; mixed → all-or-nothing via compensation. What exactly rolls back on partial Stripe failure?
3. **Per-item vs batch-level** `prorate` / `paid_with_cash` / `idempotency_key`.
4. **Preview:** a batch preview (combined charge) mirroring `preview_start`.
5. **Endpoint:** new `POST .../start-batch`, or generalize `start` to accept 1..N? Keep single for back-compat or migrate the CRM caller?

**Reality check:** Literal "one transaction" across recurring + one-time is not possible in Stripe — be explicit that the guarantee is DB-atomic + combined-where-possible + compensating rollback. Recurring-only batches are genuinely clean; one-time and mixed are the real work. This is big enough (and the host file is already the largest service) that the batch logic should land as its **own orchestrator/sub-service**, not bolted onto `member_memberships_start.py` (ties to the #9 "split oversized service" concern). **Recommend a dedicated eng design pass (`/plan-eng-review`) before implementation.**

**Blast radius:** `member_memberships_schema.py` (batch request), `member_memberships_router.py` (new endpoint + preview), a new batch orchestrator under `member_memberships/service/memberships/`, the payments layer (multi-line one-time invoice), `MembershipPaymentSyncService` (already list-capable for recurring), the CRM start-membership flow + request model, `Database/openapi.json`, tests.

**Files:** `FastApiBackend/src/member_memberships/**`, `FastApiBackend/src/payments/**`, CRM start-membership dialog + `member_memberships_start_request.dart`, `Database/openapi.json`

## 13. Discounts in the sync: kill subscription-level discounts + make item discounts a desired-state input

**Status:** ✅ Part A DONE (sub-level discounts removed, both sides) · Part C **REJECTED** (kept the 4-bucket sum model — Stripe stacks sequentially, so we sum ourselves) · Part B preview-aware DONE (preview resolves coupons), `preview_*` staging statuses not wired. See the status block at the top.

This is one redesign of *where discounts live in the sync*, in two parts.

### Part A — remove subscription-level discounts entirely (item-level only, forever)

**Finding:** `subscription_discounts: list[SubscriptionItemDiscount] = []` exists on `IntervalBucket` (`payment_sync_schema.py:114`) and on the payments request schema (`payments_members_schema.py:83`), and the payments subscription create/update services set Stripe's subscription-level `discounts` from it (`_build_subscription_discounts`, `payments_subscription_base.py:182`; called at `payments_subscription_create.py:86` / `payments_subscription_update.py:59`). **It's already dead in the sync path:** `build_subscription_bucket` never sets it (`payment_sync_builder.py:182`), so `bucket.subscription_discounts` is always `[]`; the discount engine only ever sets **item-level** `item.discounts` (`membership_payment_sync_service.py:377`). Today create/update effectively pass `discounts=""` (clear) on every sync.

**Removal scope (safe — dead in the sync path):**
- Drop `subscription_discounts` from `IntervalBucket` (`payment_sync_schema.py:114`) and the 4 pass-throughs in `payment_sync_stripe.py` (132, 145, 291, 304).
- Drop the field from `payments_members_schema.py:83`; delete `_build_subscription_discounts` (`payments_subscription_base.py:182-191`) + its calls (`payments_subscription_create.py:86`, `payments_subscription_update.py:59`); drop the sub-level line in the coupon-validation collector (`payments_subscription_base.py:310`) — keep the item-level line above it.
- **Test:** `tests/payments/test_payments_subscription_service.py:175-190` creates a real Stripe sub *with* a subscription-level discount and asserts it attaches — delete or rewrite to assert **item-level** discounts instead (it tests the removed behavior). Not in `openapi.json` (internal schema), so no contract regen.
- `SubscriptionItemDiscount` the model **stays** (item-level `item.discounts` still uses it).
- Minor: `_current_coupon_ids` reads `sub.discounts` (sub-level) ∪ item discounts — can stop reading the sub-level set since it'll always be empty.

### Part B — let discounts be a desired-state input on `SyncItem` (enables preview-with-discount + discount-on-create)

**The real problem (user):** You can't **preview adding a discount**, and you can't **add a discount on create**. Today discounts are *only read* from the snapshot table at sync (`SyncItem` deliberately carries no discounts — see its docstring; sync reads `get_applied_discounts_by_member.sql`). There's nothing that lets you pass a discount *in* as an "add." So: a not-yet-applied discount has no snapshot to preview, and starting a membership with a discount is two non-atomic steps (start → apply → sync) with no combined preview.

**Approach (user, latest) — DB-first; the sync just reads; NO discounts on `SyncItem`:** The sync *already* reads applied discounts from the DB snapshots (`get_applied_discounts_by_member.sql`) and converges Stripe. So there's no reason to thread discounts onto `SyncItem` — the DB write *is* the operation and the sync reflects it. This **deletes Part B's `SyncItem` mechanism** (and supersedes the earlier "desired state" / explicit add-on-SyncItem framings):
- **Add / add-on-create:** write the snapshot (and, on create, the membership row) to the DB — in **one transaction** for atomicity — then the sync reads both and converges (creates the line + attaches the coupon). Already how apply works today (apply writes a snapshot, then syncs); add-on-create just batches the membership + snapshot writes into the same transaction. Ties to #12.
- **Remove:** delete the snapshot; the sync reads (it's gone) and detaches the coupon.
- **Preview (the only new piece):** add a small **preview-state enum** on the snapshot — e.g. `applied` (committed) / `preview_add` / `preview_remove` — so preview can stage a hypothetical change the preview read picks up *without billing it*. One read→resolve→converge path serves both; the only branch is a status filter (real sync reads `applied`; preview reads `applied` minus `preview_remove` plus `preview_add`).

**Why simpler:** one input (the DB), one path, no parsing add/remove params to reconstruct current state — the DB *is* the state; the engine "automatically adds what needs adding" because it mirrors the DB.

**Status enum — full lifecycle (decided, per user):** `preview_add` / `preview_remove` / `applied` / `deleted`. The **sync writes the status** as its terminal step (after the Stripe op succeeds), generalizing today's "`stripe_coupon_id IS NULL` = un-synced" into an explicit state machine the caller can read:
- `applied` — committed and live on Stripe (coupon attached).
- `deleted` — **soft-delete**: removal committed + coupon detached; the row is kept (not physically deleted) so the caller/history knows the removal happened and completed.
- `preview_add` / `preview_remove` — requested but **not yet confirmed by a successful sync**.

The live-coupon read is `status = applied` only (excludes `preview_*` and `deleted`) — the hard safety net so a non-`applied` row can never bill.

**Sync-failure semantics (the reason for the enum over a physical delete):** because the sync only promotes a row to `applied`/`deleted` after Stripe succeeds, a **failed sync leaves the row in its `preview_*` state** → it never bills, the caller sees exactly that it didn't land, and a retry/reconciler re-runs the sync to promote it. This is also why remove is a soft-delete (`deleted` status) rather than a hard `DELETE`: a hard delete loses the "did the detach actually happen?" signal.

**The decision this forces — preview vs. real-pending must be distinguishable (load-bearing):** `preview_add`/`preview_remove` double as both a *dry-run preview* and a *real change pending sync* — identical as a row. So a leftover dry-run `preview_add` could be wrongly promoted to `applied` by the next real sync for that member. Preview rows therefore **must be strictly scoped** (e.g. keyed to a preview/session id the real sync ignores) and/or cleaned up before any real sync. This is **correctness, not tidiness**. (Alternative: split into separate real-pending states, but that exceeds the clean 4-state model.) The table is Stripe-gated, so preview rows never surface to clients regardless.

**Caveat to "same logic for everything":** there's still a status filter (real vs preview) — a `WHERE` clause, far simpler than the `SyncItem`/desired-state machinery it replaces.

### Part C — coupon model: ONE coupon per applied discount (supersedes the per-line aggregation)

**Status:** 🟦 Chosen direction (per user) — one open verification item

**Revision (per user) — explicit add/remove, NOT desired-state:** The earlier "desired state" framing (pass the full desired set; engine converges) is **walked back**. The user does *not* want the engine to reason about a full desired set or compute desired-vs-current diffs ("i don't want the thing to have to worry about all of that"). The operations are explicit **add-discount** and **remove-discount** — the caller says exactly what to add or remove, and the engine performs just that mutation. Per-discount coupons (below) are precisely what makes that clean: each discount is independently add/removable because it has its own coupon. The existing apply/remove snapshot path already *is* explicit add/remove; this keeps that model (and extends add to create + preview), rather than turning it into a reconciler.

**Decision:** Replace the current "aggregate a line's discounts into one summed coupon" model with **one coupon per applied discount**, keyed on `applied_discount_id`. Per-discount value math is a simple gate: **percent coupon = `percentage_off / quantity`**; dollar coupon = `dollar_off` unchanged. With one coupon per discount: **add** = create the snapshot + attach its coupon; **remove** = delete the snapshot + detach its coupon. No full-set reconciliation — the engine just resolves the snapshots that exist and performs explicit adds/removes.

**Why (the matchability problem with today's design):** Today `_aggregate_values` (`payment_sync_builder.py:293`) collapses every same-`(mode, kind)` snapshot on a line into ONE summed coupon (`Σ percents ÷ quantity`; `Σ dollars`), and the coupon id is purely value-derived (`pct_<bps>_<mode>` / `amt_<cents>_<mode>`, `payment_sync_coupons.py:48`, reused gym-wide). That makes the live Stripe state **lossy for reconciliation**: it shows only the aggregate, so the sync can tell the *total* is off but **not which individual discount is missing or extra** ("we just know the number is off"). `once`-consumption is ambiguous for the same reason (shared presence handle). Per-discount coupons make the diff exact and give each `once` its own presence handle.

**Corrects an earlier note in this audit:** the "shared deterministic coupon id is fine / same as items" position is **superseded** — matchability requires the coupon to be **unique per application** (keyed on `applied_discount_id`), otherwise two same-value discounts on one line collide (Stripe dedupes identical coupons in the `discounts` array → one is silently lost).

**Why my earlier "can't stack coupons" objection was wrong:** the current design *already* stacks multiple coupons per line (the 4 `(once|ongoing)×(percent|dollar)` buckets — e.g. a `once`-percent and an `ongoing`-percent both hit invoice 1). So multi-coupon-per-line is already in use; per-discount coupons are just more of the same.

**Open verification item (the one real tradeoff):** summing-into-one-coupon is *exact* additive within a bucket; per-discount coupons rely on Stripe combining e.g. `3.33% + 6.67%` to exactly 10% of the line. That's only exact if Stripe stacks percent discounts **additively**. If it stacks **sequentially (multiplicative)**, a multi-percent line is off by a few cents (e.g. $29.33 vs $30 on a qty-3 line with 10%+20%). **Verify Stripe's percent-stacking against the Connect account before committing.** Additive → strictly better; sequential → small rounding tradeoff for the matchability win.

**What this changes:**
- `payment_sync_builder.py`: replace `_aggregate_values` (sum-then-÷ per mode/kind) with a per-discount transform (`percent/quantity`, dollar as-is); `plan_line_discounts` emits one value per surviving snapshot, not per `(mode, kind)`.
- `payment_sync_coupons.py`: `coupon_id` keyed on `applied_discount_id` (per-application), not value-only.
- `_current_coupon_ids` / `_is_consumed_once`: per-discount presence diff instead of aggregate presence.
- The writeback already stores `stripe_coupon_id` per snapshot (`set_snapshot_coupon_id.sql`) — now it's a per-application coupon, so the handle is exact.

**Docs to update when this lands:** `sync-guide` §5 (`_aggregate_values` → per-discount), §6 (drops the sub-level `sub.discounts` read), §7 (deterministic value-based id → per-application id) + the `SyncItem` "discounts are no longer threaded through here" docstring; `discounts-guide` (percent×quantity fix framing + the apply-vs-sync seam); `FastApiBackend/payment_sync.mermaid` (the orchestration-flow diagram — the coupon/preview steps change). All living documents.

**Recommendation:** Part A is a safe removal that can land first/independently. Part B is the feature and reworks the same payments/sync discount surface — do them together (or A then B) and run a `/plan-eng-review` on Part B's snapshot-creation question before coding.

**Files:** `FastApiBackend/src/member_memberships/service/payment_sync/*` (`payment_sync_schema.py`, `payment_sync_stripe.py`, `payment_sync_builder.py`, `payment_sync_coupons.py`, `membership_payment_sync_service.py`), `FastApiBackend/src/payments/schema/payments_members_schema.py`, `FastApiBackend/src/payments/service/subscription/*`, `tests/payments/test_payments_subscription_service.py`, plus the apply path + preview for Part B.

## 14. Split the explicit freeze/unfreeze into a dedicated sync-service method

**Status:** ✅ DONE — extracted to the standalone `PaymentSyncFreeze` service (DB-first `sync_freeze_state`, no DB writes); the explicit freeze action no longer routes through `update_payments_recurring`, which keeps only the maintenance re-apply.

**Finding:** The explicit freeze/unfreeze action is threaded through `MembershipPaymentSyncService.update_payments_recurring` via `freeze_end_date` / `unfreeze` params, gated by `_validate_freeze_params` which rejects combining a freeze with membership changes (and freeze+unfreeze together). So `member_memberships_freeze.py` calls `update_payments_recurring(member_id, add_ids=[], cancel_ids=[], freeze_end_date=…)` and runs the **entire** sync (build bucket → `sync_freeze_state` → `_attach_computed_coupons` → `execute_sync` → price writeback) just to apply a `pause_collection`.

**Why it's worth splitting:**
- The runtime `_validate_freeze_params` guard enforces a mutual exclusion that a separate method would make **structurally unrepresentable** (no add/cancel params to misuse).
- A pure freeze only needs `resolve_parent` + `sync_freeze_state`. Today it also recomputes coupons (extra Stripe reads + snapshot writebacks), re-executes the subscription with unchanged items (redundant Stripe update), and runs **price writeback** — which reads the *upcoming invoice while collection is paused* (the most dubious part). All wasted work per freeze.

**Chosen design (per user):**
- Add a **dedicated** method on `MembershipPaymentSyncService` — e.g. `set_freeze_state(member_id, *, freeze_end_date=None, unfreeze=False)` — that does only `resolve_parent` (+ gym Stripe account) → `sync_freeze_state`, and **skips** the bucket build / coupon recompute / `execute_sync` / price writeback.
- The on-request freeze/unfreeze (`member_memberships_freeze.py`) calls this dedicated function directly instead of `update_payments_recurring` with empty add/cancel.
- Remove `freeze_end_date` / `unfreeze` params **and** `_validate_freeze_params` from `update_payments_recurring`.
- **Keep** the maintenance `sync_freeze_state` call inside `update_payments_recurring` (with no explicit dates → falls back to the parent's intrinsic `is_frozen`), so a membership change on an already-frozen account still re-applies the pause in the correct billing order. Only the *explicit action* moves out; the *maintenance re-apply* stays.

**Open detail:** one method (`set_freeze_state` with the freeze-vs-unfreeze precedence, mirroring `sync_freeze_state`) vs. two (`freeze` / `unfreeze`). Two is maximally structural; one thin-wraps `sync_freeze_state`. Minor — decide at implementation.

**Docs to update (living):** `sync-guide` §2 (entry-points table — add the dedicated method, note the freeze caller no longer routes through `update_payments_recurring`), §3 (the explicit freeze is no longer a branch of the main sequence), §8 (`sync_freeze_state` now has two callers: maintenance + the dedicated action); `FastApiBackend/payment_sync.mermaid` (the freeze step moves out of the main `update_payments_recurring` flow).

**Blast radius:** `FastApiBackend/src/member_memberships/service/payment_sync/membership_payment_sync_service.py` (new method, drop params + guard), `payment_sync_stripe.py` (`sync_freeze_state` unchanged, new direct caller), `src/member_memberships/service/memberships/member_memberships_freeze.py` (call the dedicated method), `tests/` (freeze tests), `sync-guide`.

## 15. `_SyncParams` NamedTuple defined on top of the sync service → moved to schema

**Status:** ✅ Fixed

**Finding:** `_SyncParams(NamedTuple)` was defined at the top of `membership_payment_sync_service.py` (the return type of `_build_sync_params`), while every sibling intermediate model (`ParentProfile`, `IntervalBucket`, `AppliedDiscountSnapshot`, `SyncItem`, `IntervalDesiredItem`, `LineDiscountValue`, `LineDiscountPlan`) already lives in `payment_sync_schema.py` as a `BaseModel`. A model floating atop a service file is the thing the convention avoids.

**Fix:** Moved it to `payment_sync_schema.py` as `SyncParams(BaseModel)` (renamed off the `_` since it's now a shared schema type; converted `NamedTuple` → `BaseModel` to match the file — the construction already used keyword args, so no call-site change beyond the name). Service imports it; removed the local class and the now-unused `NamedTuple` import. Compiles clean, 15 `test_payment_sync_builder` tests pass.

**Files:** `FastApiBackend/src/member_memberships/schema/payment_sync_schema.py`, `FastApiBackend/src/member_memberships/service/payment_sync/membership_payment_sync_service.py`

**Note (preview gap):** While here, re-confirmed `_attach_computed_coupons` runs only in `update_payments_recurring`, never in preview — that's the same preview-can't-show-discounts gap already captured in #13 Part B, not a separate finding.

## 16. Generalize the sync-status enum to `member_memberships` + go fully DB-first (drop imperative `add_ids`/`cancel_ids`)

**Status:** 🟡 PARTIAL — the `stripe_sync_status` enum + nullable column landed on both tables (schema). The caller rewiring (drop `add_ids`/`cancel_ids`, write DB-first) **and** the sync stamping `applied`/`deleted` are NOT done — this is the big remaining *functional* work (the engine is non-functional at the caller layer until it lands).

**The unified flow (user):** The same sync-status state machine from #13 (discounts) applies to **recurring memberships** too. The DB is the desired state; the sync converges Stripe and **stamps the status as confirmation**:
- **Cancel:** the membership service sets `cancel_date`; the sync reads, sees the row is no longer in the desired state, removes it from Stripe, and stamps `deleted`. No imperative `cancel_ids` passed in.
- **Add / add-on-create:** write the membership row (a new row is already identifiable by `stripe_item_id IS NULL`); the sync adds it to Stripe, sets `stripe_item_id`, and stamps `applied`. The caller checks the status went `applied`. No `add_ids` needed — the `prorate` flag on the row drives proration.
- **Preview:** write `preview_*` rows; the real sync ignores them; the preview path treats them as the add/remove request.

**Why a membership needs the status (today's gap):** `cancel_date` and `stripe_item_id` are **both immutable once set** (triggers in `member_memberships.sql`). So `stripe_item_id` can't be nulled to signal "removed from Stripe," and `cancel_date` only records *intent*, not *confirmation*. If the cancel sync fails, the membership is cancelled in the CRM but **still billing on Stripe with no signal**. An explicit `deleted` (sync-confirmed-removed) status closes that — "every recurring row that's not active carries a `deleted` flag once Stripe is in sync."

**This drops the imperative params:** today cancel passes `cancel_ids` (`member_memberships_cancel.py:59-69`) and start passes `add_ids`. Going DB-first, the sync derives the whole desired state from the DB (active rows by `cancel_date IS NULL`, new rows by `stripe_item_id IS NULL`, discount snapshots, `preview_*` markers), so `update_payments_recurring` no longer needs `add_ids`/`cancel_ids` at all. (Freeze already split out in #14.) This is the cleanest form of the re-derive-and-converge reconciler.

**Keep orthogonal — two different status axes:**
- **Lifecycle status** — the existing *derived* `member_memberships_status` view (active/cancelled/ended/frozen from `cancel_date`/`end_date`/freeze). Stays.
- **Stripe-sync status** — the NEW column the sync writes (`applied` / `deleted` / `preview_add` / `preview_remove`). Name it distinctly (e.g. `stripe_sync_status`) so it's never conflated with the lifecycle status. Do **not** fold one into the other.

**Failure semantics (same as #13):** the sync stamps the terminal status (`applied`/`deleted`) only after Stripe succeeds, so a failed sync leaves the row in its pre-terminal state → never mis-billed, caller/reconciler sees it didn't complete and retries. The reconciler (sync-guide §10) is the backstop for idle rows.

**Decisions for the design pass:**
1. Exact state set + column name on `member_memberships` (and aligning it with the `member_membership_applied_discounts` status from #13 — same enum, or per-table?).
2. Removing `add_ids`/`cancel_ids` from `update_payments_recurring` — verify nothing else relies on the imperative path; the new-row (`stripe_item_id IS NULL`) + `cancel_date` + `preview_*` reads must fully cover what the params did (including proration intent via the `prorate` column).
3. Preview-row scoping (load-bearing, per #13) now also applies to membership rows.

**Blast radius:** `Database/supabase/schemas/member_memberships.sql` (+ `member_membership_applied_discounts.sql`) new status column/enum + RLS, `member_memberships/service/payment_sync/*` (read path derives desired state from DB; `update_payments_recurring` drops params; sync stamps status), `member_memberships_cancel.py` / `member_memberships_start.py` (DB-first, drop imperative params), the preview path, `sync-guide` (§2/§3/§4) + `payment_sync.mermaid`, tests. Ties to #12, #13, #14.

## 17. Full writeback — always write the whole sync-owned state; status from Stripe-link presence

**Status:** 🟦 Chosen direction (per user) — design pass (pairs with #13/#16)

**Principle (user):** Stop doing partial/conditional writebacks. Every sync writes back the **full computed state** for each synced row in one UPDATE per table, instead of N targeted column updates + "did this change? / is this consumed?" filtering. Idempotent — a same-value UPDATE is a cheap no-op ("if it's the same it stays the same"). Replaces `update_stripe_item_id.sql`, `update_profile_sub_ids.sql`, `sync_prices_by_plan.sql`, `set_snapshot_coupon_id.sql`, `stamp_snapshot_end_date.sql`, `update_next_due_date.sql` + their conditionals with one full-row write per table.

**Boundary — "all columns" = all SYNC-OWNED columns, not literally every column.** The writeback must not clobber member-identity fields, `created_at`, or PKs/FKs. It lists exactly the columns the sync computes:
- `member_memberships`: `stripe_item_id`, `next_due_date`, `total_price`, sync-status (#16).
- `members`: `stripe_sub_id`, `total_monthly_recurring_price`.
- `member_membership_applied_discounts`: `stripe_coupon_id`, `end_date`, status (#13).

**Immutable-trigger interaction (free safety net):** `stripe_item_id` / `cancel_date` are immutable-once-set. Always-write is fine: the trigger only raises on `NEW IS DISTINCT FROM OLD`, so echoing the current value is a no-op, and the one legit transition (`stripe_item_id` NULL→value on first sync) is allowed. If the sync ever computed a *different* value for an immutable column, the trigger catches it — a bonus guard.

**Status from Stripe-link presence (user):** the sync reads the live subscription anyway, so the status falls out of it — a row whose item is in the live sub → `applied`; a row not in it → `deleted`. "All subscriptions/items without a link → `deleted`," computed declaratively rather than via targeted per-removal updates. This also **absorbs Stripe-side cancellations** (dunning) into `deleted` — the "lifecycle drift → Stripe wins" direction (sync-guide §10).

**The guard on "unlinked → deleted":** it must be scoped to rows that *should* be gone. A **brand-new** row (`stripe_item_id IS NULL`, `cancel_date IS NULL`) is also "unlinked" but is *pending add*, not deleted. So: `deleted` = (should be gone — cancelled / not in the desired active set) **and** confirmed absent from the live sub. New/pending rows (`cancel_date IS NULL`) are never marked deleted — `applied` once linked, pending until then. `cancel_date` separates "unlinked because removed" from "unlinked because not-yet-created."

**Decisions for the design pass:** confirm the full-writeback column lists per table; confirm `deleted` is driven by (desired-set membership ∧ live-sub absence), not raw `stripe_item_id`-in-sub; ensure preview (`preview_*`) rows are excluded from the live-link→status computation.

**Blast radius:** the writeback SQL (collapse the targeted files into one full-row write per table) + `price_writeback.py` / the writeback orchestration in `membership_payment_sync_service.py`, `sync-guide` §7/§8 + `payment_sync.mermaid`, tests. Ties to #13, #16.

## 18. Applied-discount snapshots are a separate parallel list re-joined by `stripe_item_id` — attach them to the desired item

**Status:** ✅ DONE ("Part E") — `AppliedDiscount` rides `ActiveMembershipRow.discounts`; `get_active_memberships(family_ids, today)` reads memberships + their active discounts in one call (end_date filter is in SQL); the builder groups by `price_id` and `PaymentSyncDiscounts.resolve` returns a `ResolvedDiscounts`; `SyncParams.snapshots` is gone. (The "new line skipped" gotcha is now a read-filter limitation, not a join-key one.)

**Finding:** In `_build_sync_params`, `snapshots = self._queries.get_applied_discounts(family_ids)` is read as a **separate list** and returned on `SyncParams` alongside the bucket. `build_desired_items` builds `IntervalDesiredItem`s that **carry no discounts** (by design today), `consolidate_by_price` merges items with no discount awareness, and `plan_line_discounts` re-associates snapshots to bucket items via `by_item[snap.stripe_item_id]`. The snapshot and the desired item are the **same grain** (one per membership pre-consolidation), so keeping them separate only to re-join by `stripe_item_id` later is artificial.

**Why it matters beyond tidiness — fixes the "new line skipped" gotcha (sync-guide §11):** the `stripe_item_id` re-join is exactly why a brand-new line (`stripe_item_id IS NULL`) can't be matched to its snapshots and gets **no coupon until the next sync**. If the snapshot rides on the desired item (matched at build time by `member_id`/`plan_id`, before Stripe assigns an item id), a new line carries its discount immediately. (The skip is a join-key artifact, not a Stripe limitation — confirm coupons attach on item-create.)

**Proposed change (per user) — fold the snapshots into the membership read; carry them on the row → item:**
- **`get_active_memberships` reads the snapshots too.** It `LEFT JOIN`s the applied-discount snapshots (aggregated per membership, e.g. a jsonb array) + their value version, so one query returns each membership **with** its discounts. Removes the separate `get_applied_discounts` query and `get_applied_discounts_by_member.sql`. (Must read the **unfiltered** base tables at service-role — same as today's snapshot read — so half-synced rows with no `stripe_coupon_id` yet stay visible to the sync.)
- **`ActiveMembershipRow` gains `discounts: list[AppliedDiscountSnapshot]`** — the membership carries its applied-discount inputs from the read.
- **`PaymentsSubscriptionDesiredItem` gains `snapshots: list[AppliedDiscountSnapshot]`** — the applied-discount *inputs*, distinct from the resolved coupon *outputs* (`item.discounts: list[SubscriptionItemDiscount]`); don't conflate the two. `build_desired_items` copies them from `ActiveMembershipRow` onto the item.
- **`consolidate_by_price` merges the snapshot lists** when collapsing items onto a shared line.
- **`plan_line_discounts(bucket)` reads `item.snapshots`** per item — drop the separate `snapshots` param and the `by_item[stripe_item_id]` re-grouping; `SyncParams.snapshots` goes away entirely.

Net: discounts ride the membership from the read all the way to the line — no separate query, no separate list, no `stripe_item_id` re-join.

**Docs to update:** `sync-guide` §4 (snapshots fold into `get_active_memberships`, not a separate read), §5 (`plan_line_discounts` reads item-attached snapshots), §11 (new-line-skipped gotcha removed) + `payment_sync.mermaid`.

**Files:** `FastApiBackend/src/member_memberships/schema/payment_sync_schema.py` (`ActiveMembershipRow`), `FastApiBackend/src/payments/schema/payments_members_schema.py` (`PaymentsSubscriptionDesiredItem`), `payment_sync_queries.py` + `get_active_recurring.sql` (join in snapshots; delete `get_applied_discounts_by_member.sql`), `payment_sync_builder.py`, `membership_payment_sync_service.py`. Ties to #13 (discount-in-sync rework).

## 19. Preview should return "due now" (with why) + the regular recurring amount, separately

**Status:** 🟦 Feature — preview-contract enhancement (ties to #12, #13)

**Requirement (user):** The subscription preview should return **(a) what's due *now*, with *why*** (the breakdown explaining the immediate charge) and **(b) separately, the regular recurring amount** (what the member pays each cycle going forward).

**Current state:** `PaymentsInvoicePreviewResponse` returns a **single** invoice — `amount_due` / `subtotal` / `total` / `currency` / `lines[]` — built from Stripe's immediate invoice preview (`preview_execute_sync`). Two gaps:
1. **No due-now vs. recurring split.** The immediate (prorated) charge and the steady-state per-cycle amount are conflated into one `amount_due`; the regular recurring figure isn't surfaced on its own.
2. **No structured "why."** `PaymentsInvoicePreviewLineItem` carries only `amount` / `description` / `stripe_price_id` / `quantity` — the reason a line exists (base charge vs. **proration** vs. **discount**) is at best buried in free-text `description`, with no proration flag or period. The CRM can't cleanly render "Due now $X = $Y proration + $Z first period − $W discount."

**Proposed shape:**
- Restructure the preview response into two parts:
  - `due_now`: `{ amount, currency, lines[] }` — the immediate charge, each line tagged with a **kind** (`base` / `proration` / `discount`) + `period`, so the total is explainable.
  - `recurring`: `{ amount, currency, lines[] }` — the regular per-cycle total (post-discount), what they pay each interval normally.
- **Sourcing:** `due_now` from Stripe's upcoming/immediate invoice preview (its `proration` flags + periods give the "why"); `recurring` from the steady-state per-cycle post-discount totals (the bucket's resolved line totals, or a next-full-cycle preview). With multi-interval (PaymentRefactor §9) the recurring amount may span intervals — design for one figure per interval if needed.
- Add the `kind`/proration/period fields to `PaymentsInvoicePreviewLineItem` to carry the "why."

**Applies to all preview endpoints** (`preview_start_membership` + the other `PaymentsInvoicePreviewResponse | None` previews in `member_memberships_router.py` at ~478/540/679), and must reflect discounts once discount-preview lands (#13 Part B — the `preview_*` status). Batch preview for multi-start (#12) should return one combined due-now + recurring.

**Files:** `FastApiBackend/src/payments/schema/payments_invoice_schema.py` (response + line item), `payment_sync_stripe.py` (`preview_execute_sync` → split due-now/recurring), the preview service methods + `member_memberships_router.py` preview endpoints, `Database/openapi.json`, the CRM preview UI, tests. Ties to #12, #13.

## 20. Extract `once`-consumption + `end_date` settling into a separate pre-sync component (sync shouldn't edit the DB mid-flow)

**Status:** ✅ DONE — extracted to the `PaymentSyncOnceDiscounts` pre-sync settle: it stamps a consumed `once`'s `end_date` before the build reads, so the sync reads an already-settled DB and converges with no mid-flow DB edits. (The `end_date` exclusion itself now lives in the read SQL, not in code.)

**Finding:** The discount-lifecycle logic — `once`-consumption detection and `end_date` enforcement — is nested deep inside the sync: `_attach_computed_coupons` → `plan_line_discounts` / `_plan_one_line` (`_is_consumed_once`, `_is_past_end_date`) and `_apply_line_plan` (`stamp_snapshot_consumed`, which **writes the DB mid-convergence**). So `update_payments_recurring` mutates snapshots partway through just to determine the desired discount state.

**Principle (user):** The DB going *into* `update_payments_recurring` should **already be in the state it should be in**, and the sync should **only write at the end** (its convergence results). Settling the discount lifecycle (finalize `once`-consumption, enforce `end_date`) is a **precondition** for syncing, not part of the convergence. Extract it into its own component — the same way the explicit freeze action is being split out (#14) — so the sync becomes purely declarative: read the correct DB → converge Stripe → write results once.

**Two phases:**
1. **Settle (new, pre-sync):** read the live subscription's current coupons (for `once`-presence), stamp the DB for anything consumed/expired (`once` consumed → stamp `end_date`/status; past-`end_date` ongoing → marked gone). After this, the DB snapshots reflect the true current desired state. This is pure lifecycle settling — it does **not** converge Stripe.
2. **Sync (`update_payments_recurring`):** reads the now-correct DB, converges Stripe, writes back results (coupon ids, stripe item ids, status, totals) **at the end only**. No mid-flow DB edits to discover desired state.

**Why this is right:** clean separation (lifecycle settling vs. convergence); the sync stops being a thing that edits the DB to figure out its own input; and the settle component is **exactly the scheduled reconciler's core duty** (§4 / sync-guide §10 — enforce `end_date` cutoffs + finalize `once`-consumption on idle members), so the reconciler reuses it instead of re-running a full sync.

**Honest consideration — avoid a double Stripe read:** settle needs the live-sub coupon read for `once`-consumption (the `end_date` half is pure date logic); the sync may also read the sub. Read the live state once and hand it to both (or accept two reads) — a design detail, not a blocker.

**Docs to update:** `sync-guide` §3 (settle becomes a distinct pre-phase before the converge sequence), §5 (the `_is_consumed_once` / `_is_past_end_date` gates move into settle), §7 (`stamp_snapshot_consumed` moves out of `_apply_line_plan`), §10 (reconciler runs the settle component) + `payment_sync.mermaid`.

**Files:** `FastApiBackend/src/member_memberships/service/payment_sync/membership_payment_sync_service.py` (extract settle, slim `_attach_computed_coupons`), `payment_sync_builder.py` (consumption/end_date gates move), `payment_sync_queries.py` (`stamp_snapshot_consumed`). Ties to #13 (discount model), #14 (parallel split), #16/#17 (DB-first + write-at-end), §4/§10 reconciler.

## 21. `update_payments_recurring` should return nothing (the action is fire-and-converge; use preview for the invoice)

**Status:** 🟦 Chosen direction (per user) — falls out of #16/#17 (DB-first + full writeback)

**Principle (user):** The sync action writes everything it needs to the DB itself, so it shouldn't return anything. `update_payments_recurring` → `None`. The result lives in the DB; callers read it (e.g. check the sync-status went `applied`, per #16). **Preview** is the read path for the financial figures — "if you want the invoice, use preview." The mutating action ≠ the preview.

**Current state:** `update_payments_recurring` returns `PaymentsSubscriptionResponse | None`. The **only** caller that uses the return is `member_memberships_start.py:154` — it extracts `stripe_item_id` + `next_due_date` from it and writes them back. Cancel / freeze / update_price / update_discounts / linked all ignore the return today.

**What this depends on (#16/#17):** once the sync writes `stripe_item_id`, `next_due_date`, sync-status, and totals to the DB itself (full writeback at the end), the start service no longer needs the return — it inserts the row, runs the sync, and checks the DB (the `applied` status). Then the return is dead and the signature becomes `-> None`. (`execute_sync`'s subscription result is still used *internally* to drive the writeback — it just isn't surfaced to callers.)

**Preview unchanged in spirit:** `preview_update_payments_recurring` keeps returning the invoice (and gets richer per #19 — due-now + recurring). The split is clean: action returns nothing; preview returns the numbers.

**Files:** `FastApiBackend/src/member_memberships/service/payment_sync/membership_payment_sync_service.py` (`update_payments_recurring -> None`), `member_memberships_start.py` (drop the return-extraction; rely on the sync's writeback + status check). Ties to #16, #17, #19.

## 22. Proration behavior must be passed explicitly to the sync, not inferred from DB `prorate` flags

**Status:** ✅ DONE — explicit `proration_behavior: Literal["none","always_invoice"] = "none"` on `update_payments_recurring` / `execute_sync` / `_sync_bucket` / preview, threaded into both the create and update Stripe requests; the `any(item.prorate …)` inference is removed. This also fixed a latent crash: the create path referenced `item.prorate` on a model that no longer has the field.

**Finding:** `execute_sync` infers proration from the items: `proration_behavior = "always_invoice" if any(item.prorate for item in bucket.items) else "none"` (`payment_sync_stripe.py`). `item.prorate` comes from the DB (`member_memberships.prorate` → `SyncItem.prorate` → bucket item), so the sync is **guessing** how to bill a change from stored state.

**Principle (user):** Proration is a decision about *this specific action* ("do I cut a prorated invoice for this change right now?"), **not** desired end-state — so it can't be derived from the DB. It must be **explicitly passed by the caller/user** to the sync action, with a **default of `none`**.

**Why this is the exception to DB-first (#16):** the DB-first direction removes the imperative *what* (add/cancel — derivable from DB state). But the *how-to-bill-this-transition* (proration) is genuinely transient — it has no place in the desired-state DB and must travel on the request. So `proration_behavior` stays an explicit per-call param even as `add_ids`/`cancel_ids` go away.

**Change:**
- Add `proration_behavior: Literal["none", "always_invoice"] = "none"` to `update_payments_recurring` → `execute_sync`; **remove** the `any(item.prorate …)` inference.
- The request carries the admin's proration choice; the caller (start / update_price / …) passes it through.
- **Preview must take it too** (#19): the due-now figure depends on proration, so `preview_*` accepts the same explicit `proration_behavior`.

**Open detail:** does `member_memberships.prorate` / `SyncItem.prorate` become vestigial once proration is an explicit action param? If the per-row flag no longer drives behavior, decide whether to keep it as a record of how a membership was started or drop it.

**Files:** `FastApiBackend/src/member_memberships/service/payment_sync/payment_sync_stripe.py` (`execute_sync` + `preview_execute_sync`), `membership_payment_sync_service.py` (param), the callers (`member_memberships_start.py`, `member_memberships_update_price.py`, …), the request schemas, `Database/openapi.json`, tests. Ties to #16, #19, #21.

## 23. Shared `BillingParentResolver` — migrate every `resolve_parent` caller onto it (deferred)

**Status:** 🟦 Plumbing landed (refactor step 1) — the mass caller migration is deferred (per user)

**What landed:** Parent/billing-account resolution became a real shared service, `BillingParentResolver` (`FastApiBackend/src/shared/billing_parent_resolver.py`), registered in DI (`core/dependencies.py` → `billing_parent_resolver`). It owns the parent lookup (`resolve_parent`) and the parent+gym-Stripe-account combo (`resolve`). The `ParentProfile` model moved to `src/shared/billing_parent.py` and `resolve_parent.sql` to `src/shared/sql/`; `PaymentSyncQueries.resolve_parent` was deleted (moved here). The payment sync injects this resolver; the standalone `PaymentSyncFreeze` takes an already-resolved `ParentProfile` (so the freeze request resolves once via this resolver, then calls freeze).

**Deferred (the mass change — do NOT bundle into step 1):** every other `resolve_parent` caller still routes through `MembershipPaymentSyncService.resolve_parent` (a thin delegate) instead of injecting `BillingParentResolver` directly:
- `member_memberships_start.py` (×2), `member_memberships_charge_card.py`, `member_memberships_mark_paid_cash.py`, `member_memberships_freeze.py` (×2).
- These should inject `BillingParentResolver` and call it, then the public `MembershipPaymentSyncService.resolve_parent` delegate can be removed.

**Also worth folding in later:** `get_family_ids` (family resolution) still lives in `PaymentSyncQueries` and takes a `ParentProfile` — it's the natural companion to parent resolution and could move onto/beside the shared resolver. And the engine imports `ParentProfile` from `src.shared.billing_parent` directly now; `payment_sync_schema.py` imports it only for `SyncParams.parent`.

**Files:** `FastApiBackend/src/shared/billing_parent.py`, `billing_parent_resolver.py`, `src/shared/sql/resolve_parent.sql`, `src/core/dependencies.py`, the `resolve_parent` callers listed above.

## 24. Coupon I/O delegated to `PaymentsStripeDiscountService` (sync stops calling Stripe directly)

**Status:** ✅ DONE (membership-refactor worktree)

**What landed:** `PaymentSyncCoupons` no longer imports the Stripe SDK — it keeps only the
deterministic-id scheme (`pct_<bps>_<mode>` / `amt_<cents>_<mode>`) + the validate-or-replace policy
and **delegates all coupon find/create/delete to `PaymentsStripeDiscountService`**. That service was
reshaped into the single owner of Stripe coupon I/O: `find_discount(coupon_id, account)`
(retrieve-or-`None`), `create_discount` (under a **caller-supplied `coupon_id`**; idempotent on a
create race — returns the existing coupon), `delete_discount`, and `retrieve_discount` (kept for the
subscription coupon-validation path). The dead `update_discount` was removed, and the old
one-coupon-per-`gym_discounts`-row metadata (`crm_discount_id` / `StripeCouponMetadata`) was
**deleted** — value-coupons are shared across every discount at a value, made on the spot.
`sync-guide` §1/§7 now carry the hard rule: nothing under `payment_sync/` touches the Stripe SDK
directly. **Audit note:** the only other direct-Stripe caller outside `src/payments/` is
`gyms_stripe_connect_service.py` (Connect-account onboarding — a distinct domain with no
payments-layer service); flagged, not yet routed.

**Files:** `src/member_memberships/service/payment_sync/payment_sync_coupons.py`,
`payment_sync_discounts.py`, `src/payments/service/payments_stripe_discount_service.py`,
`src/payments/schema/payments_discount_schema.py`,
`src/payments/schema/metadata/stripe_coupon_metadata.py` (deleted), `src/core/dependencies.py`,
`.claude/skills/sync-guide` + `payments-guide`.

## 25. NEW — concurrency / global member lock (prevent concurrent edits/sync on the same family)

**Status:** 🟦 To design

**Requirement (user):** While one admin is editing/syncing a member, no one else may run a
conflicting edit/sync on the **same paying-parent family**. Today there is **zero** concurrency
guard — two concurrent `update_payments_recurring` on the same family both read, both call Stripe,
and both write back last-write-wins (the sync is a multi-transaction cascade with Stripe calls in the
middle). On billing-critical code this can mis-bill or desync Stripe↔CRM.

**Postgres/Supabase support — YES** (Supabase *is* Postgres): `SELECT … FOR UPDATE` (row lock, but
only lives for one transaction — insufficient across the multi-transaction sync, and it would pin a
pooled connection across Stripe HTTP I/O), or **advisory locks** (`pg_advisory_lock` /
`pg_advisory_xact_lock` / `pg_try_advisory_lock(key)`) — a named lock on `hashtext(parent_member_id)`.
The latter is the right tool. **Recommended:** a per-parent advisory lock keyed on the resolved
paying-parent `member_id` (NOT one global lock for the whole gym), acquired at the start of the
mutate+sync operation, `pg_try_advisory_lock` → **409 fail-fast** if held, released in `finally`.
Optional UI layer: a `member_locks(member_id, locked_by, locked_at, expires_at)` table with a TTL for
the "Bob is editing, you see read-only" experience. Natural to land with the #16 caller rewiring. Full
design in `FastApiBackend/TODO_SYNC_REFACTOR.md` §11.

**Decisions for the design pass:** (a) backend operation serialization vs (b) UI edit-session lock vs
both; fail-fast 409 vs block-with-timeout; where the lock attaches (a shared decorator/context manager
around the lifecycle callers + the sync entry points).

**Files:** `src/shared/database.py` (or a new lock helper), the lifecycle callers + the sync entry
points, and `Database/supabase/schemas/` only if the UI `member_locks` table is chosen.

<!-- Entries appended below as we go. -->
