# Payment-Sync Refactor — Handoff / TODO (what's LEFT)

> **Read this whole file before touching `src/member_memberships/service/payment_sync/`.**
> This is a slow, **human-in-the-loop** refactor of the **most billing-critical code in the
> backend** — it decides how real members are charged. Every change is **proposed, reviewed,
> and approved one piece at a time. Never a big sweep. Propose → wait → write.** A mistake here
> mis-bills real customers. (This rule also lives in `.claude/skills/sync-guide/SKILL.md` and
> `FastApiBackend/CLAUDE.md`.)
>
> This doc lists **what is still LEFT**. The finished work is summarized in §1 (so you know what
> exists) but is not re-explained as "to do". The authoritative description of the *current*
> engine is the **`sync-guide`** skill — read it alongside this.

---

## 0. Orientation — where everything is

- **Worktree:** `/.../codebase/.claude/worktrees/membership-refactor-step1`, branch
  `worktree-membership-refactor-step1` (pushed to origin — the work is safe there). All edits
  happen here, isolated from the main checkout. **Commit + push at each milestone.**
- **The engine:** `FastApiBackend/src/member_memberships/service/payment_sync/`.
- **Living docs (engine source of truth):** `.claude/skills/sync-guide/SKILL.md` (CURRENT — kept
  up to date this session) and `.claude/skills/payments-guide/SKILL.md` (CURRENT). **STALE:**
  `.claude/skills/discounts-guide/SKILL.md` (still says "snapshot") and
  `FastApiBackend/payment_sync.mermaid` (never updated this session) — see §2.5.
- **The audit that started this:** `MANUAL_REVIEW.md` (repo root). Items #12–#25 drive this
  refactor; the top of that file has a status table. Mapping at the bottom of this doc (§9).

### How to verify (do this after EVERY change)
The worktree has **no `.venv`**. Use the MAIN checkout's venv. From `FastApiBackend/`:
```bash
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
d.DependencyInjector().payment_sync_service()
d.DependencyInjector().member_memberships_service()
print('DI OK')
"
```
- The `.env` has one unquoted comma value (a CORS line) that breaks `source` — load with
  `dotenv_values`. `import src.shared.db_schema_path` **before** anything importing `schema.*`.
- `.venv` console scripts (`pytest`, `ruff`) have stale shebangs — invoke via
  `"$MAIN/.venv/bin/python" -m pytest|ruff`, not the bare script.
- I **cannot execute SQL against the DB** here. SQL files are verified only by compile/ruff/DI +
  reasoning. The user runs it live to confirm.
- The discount math is verified by an inline trace; re-run it after touching the math
  (`PaymentSyncDiscounts._aggregate_line_values`): expected 30→20 seq=44, (A=44,B=10)/2=27,
  100→100, dollars summed=2000, expired excluded.

### ⚠️ Migrations the user still owes (schema changed; user runs migrations, NEVER you)
Tell the user to **re-run the migration** before testing live — these schema changes are
uncommitted to their DB:
1. `stripe_sync_status` enum now includes **`not_added`** and **`migrating`**; both
   `stripe_sync_status` columns are now **`NOT NULL DEFAULT 'not_added'`**.
2. The client views `member_memberships` and `member_membership_applied_discounts` changed their
   `WHERE` to `stripe_sync_status NOT IN ('not_added','preview_add','preview_remove')`.
3. **NEW:** `trg_prevent_cancel_date_overwrite` and `trg_prevent_stripe_item_id_overwrite` now skip
   the immutability check when `OLD.stripe_sync_status = 'migrating'` — this is what lets the
   DB-first cancel revert (clear `cancel_date`) and `update_price` move the immutable
   `stripe_item_id` to the new price's line. Without the re-run, cancel-revert and price migration
   raise the old immutability error.
(Per `Database/CLAUDE.md`: **never run `supabase` migrations or `python_data/main.py` seeds.**)

---

## 1. Current engine state — what EXISTS now (so you don't redo it)

`PaymentSyncService` is a **declarative reconciler**: on every membership mutation it throws away
whatever Stripe has, **re-derives the full desired subscription state from the DB**, converges
Stripe, then writes everything back to the DB. The CRM owns intent; Stripe owns outcomes. The
service is a **thin orchestrator** over focused sub-services.

**`update_payments_recurring(member_id, idempotency_key, pay_first_invoice_out_of_band=False,
proration_behavior="none") -> None`** (real path):
1. **resolve** parent + gym account — `BillingParentResolver.resolve(member_id)`.
2. **maintenance freeze re-apply** — `PaymentSyncFreeze.sync_freeze_state(parent, account, *, idempotency_key)`.
3. **settle once discounts** — `PaymentSyncOnceDiscounts.sync_once_discounts(parent, account)`
   (stamps `end_date` on consumed `once` so the build drops them).
4. **build** — `PaymentSyncBuilder.build_sync_params(parent, account, preview=False)` reads the
   memberships+discounts, groups by `price_id`, calls `PaymentSyncDiscounts.resolve(groups,
   account)` (→ `ResolvedDiscounts`: per-price coupons + `applied_id→coupon` links), assembles
   the `IntervalBucket`. Returns `SyncParams(bucket, parent, stripe_account_id, coupon_links,
   memberships)`.
5. **execute** — `PaymentSyncStripe.execute_sync(...)` → `PaymentsSubscriptionResponse | None`.
6. **writeback** — `PaymentSyncWriteback.write(params, sub_result)` persists EVERYTHING (see
   below). Returns **`None`** — callers read the DB.

**`preview_update_payments_recurring(member_id, proration_behavior="none")`**: resolve → `build_sync_params(parent, account, preview=True)` → `preview_execute_sync`. **No writeback / settle / freeze.** It DOES find-or-create coupons (idempotent, gym-wide), so the preview total reflects discounts.

**Done this session (do NOT redo):**
- **Part E** — discounts ride the membership: `AppliedDiscount` rides `ActiveMembershipRow.discounts`; one-call read (`get_active_memberships`); group-by-price → `PaymentSyncDiscounts.resolve` → `ResolvedDiscounts`; `SyncParams.snapshots` gone; payments-side `subscription_discounts` removed; the word "snapshot" dropped from the engine.
- **Builder is a service** (`PaymentSyncBuilder`); the discount **math** lives in `PaymentSyncDiscounts._aggregate_line_values` (per-membership-sequential percent / summed dollar; dollar coupon attaches before percent so Stripe sequences dollar→percent). The **4-bucket sum model** (2 modes × 2 kinds) is final; **per-discount coupons were REJECTED**.
- **Coupon I/O delegated** to `PaymentsStripeDiscountService` — the engine has **no direct Stripe SDK**. `PaymentSyncCoupons` keeps only the deterministic-id (`pct_<bps>_<mode>`/`amt_<cents>_<mode>`) + **validate-or-replace** policy. `crm_discount_id`/`StripeCouponMetadata`/`update_discount` were removed.
- **Explicit proration** (`proration_behavior`, default `none`); the `item.prorate` inference is gone. **Date-lifetime filter is in SQL** (`:today`), not code. `LineDiscountValue` has bounds + percent-XOR-dollar validators. Dead `IntervalBucket.total_price` removed.
- **Part D — `PaymentSyncWriteback`** (real path only) stamps, per sync: each membership's `stripe_item_id` + `next_due_date` + `stripe_sync_status='applied'` (mapping live sub items → rows by `stripe_price_id`), the coupon links + `applied` on the applied-discount rows, `deleted` on cancelled rows confirmed gone from the live sub, the parent `stripe_sub_id_month`, and the post-discount price totals (it **composes** `PriceWriteback`). `update_payments_recurring -> None`.
- **#16 read change** — the engine reads `member_memberships_unfiltered` so **pending rows are visible** (`get_active_recurring.sql`: `cancel_date IS NULL AND stripe_sync_status::text <> ALL(:excluded_statuses)`); client views hide `not_added` + `preview_*`.
- **`stripe_sync_status` is a no-NULL enum**: `not_added` (default / pending) / `applied` / `deleted` / `preview_add` / `preview_remove` / `migrating`; columns `NOT NULL DEFAULT 'not_added'`.
- **DB-first START caller** — `member_memberships_start.py` (recurring branch): insert pending row → `update_payments_recurring(...)` (no return extraction; the writeback writes `stripe_item_id`/`next_due_date`) → returns `None`. Injects `BillingParentResolver` directly. **This is the MODEL for the other callers (§2.1).**
- **Never-archive-prices** — `membership_plans_price.py` + `update_membership` no longer call `deactivate_price`; the DB (`membership_plan_prices.is_active`) is the sole "current price" gate (avoids the update-during-migration race).
- **Gym-local dates** — `next_due_date`/`last_paid_date` use `stripe_ts_to_gym_date(ts, tz)` (shared in `src/shared/gym_timezone.py` with `get_gym_timezone(session, gym_id)`), in BOTH the writeback and the `invoice.paid` webhook (was UTC, off-by-one for east-of-UTC gyms).
- **Preview TOGGLE** — `build_sync_params(parent, account, preview)`; `get_active_memberships(ids, today, preview)` + `_get_discounts_by_item(...)` bind `:excluded_statuses` (real drops all `preview_*`; preview keeps `preview_add`, drops `preview_remove`). The plumbing is done; the rest of the preview feature is NOT (§2.2).

### Sub-service map (current files under `payment_sync/`)
- `payment_sync_service.py` — `PaymentSyncService` orchestrator. Injects `_parent`
  (`BillingParentResolver`), `_freeze`, `_once_discounts`, `_builder`; builds `_stripe`,
  `_writeback` internally. **No `_queries`, no `_price_writeback`, no `resolve_parent` anymore.**
- `payment_sync_builder.py` — `PaymentSyncBuilder` (DI: `db_pool`, `discounts`):
  `build_sync_params(parent, account, preview=False)` → `_group_by_price` / `_build_bucket`.
- `payment_sync_discounts.py` — `PaymentSyncDiscounts` (DI: `discount_service`): owns ALL discount
  math (`_aggregate_line_values`) + `resolve(groups, account) -> ResolvedDiscounts`; builds
  `PaymentSyncCoupons` internally.
- `payment_sync_coupons.py` — `PaymentSyncCoupons` (id scheme + validate-or-replace policy;
  **delegates** find/create/delete to `PaymentsStripeDiscountService`; no Stripe SDK).
- `payment_sync_freeze.py` — `PaymentSyncFreeze.sync_freeze_state` (DB-first `pause_collection`).
- `payment_sync_once_discounts.py` — `PaymentSyncOnceDiscounts.sync_once_discounts` (pre-sync settle
  + `_current_coupon_ids` live read).
- `payment_sync_queries.py` — `PaymentSyncQueries`: `get_family_ids`,
  `get_active_memberships(ids, today, preview)` + `_get_discounts_by_item(...)`,
  `get_unconsumed_once_discounts`, `set_applied_discount_coupon_id` (stamps coupon + `applied`),
  `mark_once_consumed`, `update_profile_sub_id`, **`apply_membership_sync`** (item id +
  next_due_date + `applied`), **`get_cancelled_recurring`** (item_id→stripe_item_id),
  **`mark_memberships_deleted`**. The `_excluded_statuses(preview)` helper lives here.
- `payment_sync_writeback.py` — `PaymentSyncWriteback` (DI: `db_pool`, `subscription_service`):
  `write(params, sub_result)` → `_apply_membership_rows` (maps live items→rows by price) /
  `_mark_removed_deleted`. **Composes** `PriceWriteback`.
- `payment_sync_stripe.py` — `PaymentSyncStripe` (execute/preview/_sync_bucket; create/update/cancel
  only; explicit `proration_behavior`).
- `price_writeback.py` — `PriceWriteback` (composed by the writeback now, NOT the orchestrator).
- shared: `src/shared/billing_parent.py` (`ParentProfile`), `billing_parent_resolver.py`
  (`BillingParentResolver`), `gym_timezone.py` (`gym_today`, `stripe_ts_to_gym_date`,
  `get_gym_timezone`), `src/shared/sql/` (`resolve_parent.sql`, `gym_timezone_by_id.sql`).
- payments layer: `PaymentsStripeDiscountService` (`find_discount` / `create_discount`-with-id /
  `delete_discount` / `retrieve_discount`).
- DI (`src/core/dependencies.py`): `billing_parent_resolver`, `payment_sync_freeze`,
  `payment_sync_once_discounts`, `payment_sync_discounts`, `payment_sync_builder`,
  `payment_sync_service`; `member_memberships_service` now also gets `parent_resolver`.

---

## 2. WHAT'S LEFT (the actual work — in priority order)

### 2.1 ✅ DONE — Rewire the lifecycle callers DB-first + verify-and-revert

All lifecycle callers are rewired. The contract is documented in **`sync-guide` §2 "The caller
contract"** (read it). Shape: write the desired DB state → call the param-less sync → verify the
`stripe_sync_status` writeback landed → revert the DB change if not (`sync_or_revert` in
`src/shared/db_first_helpers.py`).

- **cancel** — DB-first set `cancel_date` + stage `migrating` → sync → verify `deleted` → revert
  (`uncancel`). Keeps the `PaymentsResourceNotFoundError` tolerance. `stripe_item_id` kept.
- **update_price** — DB-first write new price + stage `migrating` → sync (writeback moves the line)
  → verify `applied` → revert to old price.
- **freeze/unfreeze** — DB-first window write → `PaymentSyncFreeze.sync_freeze_state` directly
  (injected) → revert the window on failure. NOT through `update_payments_recurring`.
- **link/unlink** — DB-first `account_linked_to_id` → sync the parent → revert relationship on
  failure (revert-on-exception; child has no recurring so no status verify).
- **#23** — `charge_card` + `mark_paid_cash` inject `BillingParentResolver` (drop the deleted
  `PaymentSyncService.resolve_parent`).
- **update_discounts** — dropped the removed `add_ids`/`cancel_ids` (already DB-first). `SyncItem`
  deleted.

**The `migrating` status is load-bearing:** the immutability triggers (`cancel_date`,
`stripe_item_id`) now allow the change while `stripe_sync_status = 'migrating'` — that's what lets
cancel revert and update_price move the line. **User owes the trigger migration (§0).**

**The engine is functional again.** Tests (§2.4) can be restabilized.

### 2.2 🟡 Finish PREVIEW (the toggle is done; the staging + response shape are not)

The **read toggle** is wired: `build_sync_params(..., preview=True)` → the reads include
`preview_add` and exclude `preview_remove` (real path excludes both). What's LEFT:

1. **The caller must STAGE preview rows, then CLEAN them up.** A preview reflects a *hypothetical*
   change that isn't in the DB yet. So to preview e.g. *adding* a membership: insert a membership
   row with `stripe_sync_status='preview_add'` → run `preview_update_payments_recurring` (the
   build reads it because `preview=True`) → **DELETE the preview row** afterward (in a `finally`).
   Preview-*removing*: stamp an existing row `preview_remove`, preview, then revert to its prior
   status. Same for **applied-discount** preview rows (the discount read toggles too).
2. **🔴 Scoping — CONFIRMED HARD BLOCKER on the concurrency lock (§2.3 / #25).** Staging
   `preview_remove` on a REAL (`applied`, billing) membership is **unsafe without the per-parent
   lock**. Trace: to preview a cancel/price-change you stamp the `applied` row → `preview_remove`.
   The preview read excludes it (correct). But `_EXCLUDED_REAL` ALSO excludes `preview_remove`, so a
   **concurrent real sync** on that family during the preview window (another admin action, a
   `bulk_payment_sync`, a webhook-triggered sync) treats the membership as removed and **drops its
   live Stripe line → mis-bills the member.** So `preview_remove` (cancel, update_price, discount
   removal) REQUIRES the lock to guarantee no real sync runs during the preview window.
   - `preview_add` (start preview) is *safe-ish*: a concurrent real sync excludes it → ignores the
     not-yet-real row → no mis-bill. Only risk is a leaked row (mitigate with `finally` cleanup + a
     sweep). So start-preview-via-staging can land before the lock; the remove-side cannot.
   - **Link/unlink previews need NO staging** — the child has zero recurring memberships (asserted),
     so linking/unlinking moves no membership rows and the parent's bill is unchanged; previewing the
     parent's current state is already correct.
   - **Recommendation:** do the **concurrency lock (§2.3) FIRST** (it's the natural next step after
     the caller rewiring AND it unblocks safe preview staging), then land preview staging. Until
     then the cancel/update_price/start/discount previews show the family's CURRENT state (each
     carries a `NOTE:` in code).
3. **#19 — split the preview response into "due now" vs "recurring".** Today
   `PaymentsInvoicePreviewResponse` returns ONE invoice. Restructure to:
   - `due_now`: `{amount, currency, lines[]}` where each line carries a **kind** (`base` /
     `proration` / `discount`) + period — so the CRM can render "Due now $X = $Y proration + $Z
     first period − $W discount".
   - `recurring`: `{amount, currency, lines[]}` — the steady per-cycle post-discount total.
   Touches `payments_invoice_schema.py`, `payment_sync_stripe.py` (`preview_execute_sync` →
   split), the preview service + the `member_memberships_router.py` preview endpoints,
   `Database/openapi.json`, the CRM preview UI, tests. (MANUAL_REVIEW #19.)
4. **Known caveat already in code:** the START caller's preview branch has a `NOTE:` — a recurring
   START preview can't reflect the new membership until staging (1) lands; it currently previews
   the family's CURRENT state. Fix it as part of (1).

### 2.3 🟡 Concurrency / global member lock (#25) — design + build

**The need:** while one admin is editing/syncing a member, no one else (admin, bulk job, second
tab, or a **preview**) may run a conflicting edit/sync on the **same paying-parent family**. Today
there is **zero** guard: two concurrent `update_payments_recurring` on one family both read, both
call Stripe, both write back last-write-wins (the sync is a multi-transaction cascade with Stripe
calls in the middle). On billing code this mis-bills / desyncs.

**Postgres/Supabase support — YES** (Supabase *is* Postgres):
- **`SELECT … FOR UPDATE`** (row lock) — lives for ONE transaction only. Our
  `DirectDatabasePool.session()` is one txn per call and the sync spans many txns across Stripe
  HTTP calls, so a row lock can't wrap the whole op without pinning a pooled connection across
  network I/O. Only prior use in the repo: `rewards/sql/redeem_reward.sql`.
- **Advisory locks** — `pg_advisory_lock` / `pg_advisory_xact_lock` / `pg_try_advisory_lock(key)`
  on `hashtext(parent_member_id::text)`. **The right tool**: acquire once at the start of the
  op, do the whole DB+Stripe sequence, release at the end (`finally`); a second op on the same
  parent blocks or fails fast.

**Recommended (confirm with user):** a **per-parent advisory lock** keyed on the resolved
paying-parent `member_id` (NOT one global lock — that serializes the whole gym).
`pg_try_advisory_lock(hashtext(parent_member_id))` → on failure **409 "member is being updated, try
again"** (fail fast, don't queue). Lock the parent so a child edit + a parent edit can't race the
shared family subscription. Attach via a **shared decorator/context manager** around the lifecycle
callers + the sync entry points. **It's natural to land this in the SAME pass as §2.1** (the
caller rewiring is where the lock belongs).

**Open questions for the user:** (a) backend-operation serialization (advisory lock) vs (b) a UI
edit-session lock (`member_locks` table with `locked_by`/`locked_at`/`expires_at` + TTL/heartbeat
for "Bob is editing → read-only") vs both; fail-fast 409 vs block-with-timeout. The user leaned
**"fix it properly"** but the exact flavor is unconfirmed — **ask before building.**

### 2.4 🟡 Tests — restabilize + add (do AFTER §2.1 makes the engine functional)

Tests run against a **real shared local Supabase + a real shared Stripe test Connect account** (no
rollback) — every test cleans up exactly what it creates via the `created` fixture (see
`FastApiBackend/CLAUDE.md`). **Never reshape a test to pass against a broken path** — fix the
engine/caller.
- `tests/helpers/service_factory.py` builds `PaymentSyncService` with the **OLD constructor** — the
  current one is `(db_pool, subscription_service, parent_resolver, freeze, once_discounts,
  builder)`. This breaks `test_price_writeback.py` + `test_discount_semantics.py` at setup. Fix the
  factory first.
- `tests/member_memberships/service/payment_sync/test_payment_sync_builder.py` — heavily stale
  (references removed `plan_line_discounts` / `LineDiscountPlan` / `AppliedDiscountSnapshot`).
  Rewrite against the current builder/discount math.
- **New tests needed:** `PaymentSyncDiscounts` (the math — lock 30+20=44, (A=44,B=10)/2=27,
  dollars summed, percent-XOR-dollar), `PaymentSyncOnceDiscounts`, `PaymentSyncWriteback` (the
  applied/deleted stamping + item-id mapping), `LineDiscountValue` validators, the preview toggle,
  the gym-local date conversion (Tokyo off-by-one).
- Delete tests for removed paths (don't keep "this route is gone" assertions).

### 2.5 🟡 Update the remaining living docs (in the same change that stabilizes the engine)
- **`discounts-guide` skill** — still uses **"snapshot"** as a defined term; the engine renamed it
  to **"applied discount"**. Rename throughout (and reconcile the percent×quantity framing with the
  current per-membership-sequential math). (`sync-guide` + `payments-guide` are already current.)
- **`FastApiBackend/payment_sync.mermaid`** — the orchestration-flow diagram was **NOT** touched
  this session and is very stale (no writeback node, old `_attach_computed_coupons`/freeze flow,
  no `-> None`). Re-author with the `mermaid-creation` skill (top-down `TB`, sibling-only edges,
  fixed palette, render + `check_siblings.py` + Mermaid-9 parse). Keep it in sync per `sync-guide`.

### 2.6 Minor cleanups
- ✅ **`ActiveMembershipRow.price` orphan removed** — dropped the field, the `price=row["price"]`
  parse (`payment_sync_queries.py`), and `mpp.price` from `get_active_recurring.sql`. (NB
  `member_memberships.total_price` is a **separate** DB column, still in active use — untouched.)
- ✅ **`stripe_ts_to_date` removed** — it was uncalled (every importer uses `stripe_ts_to_datetime`);
  deleted it + the now-unused `date` import from `stripe_time.py`.
- ✅ **Disjoint `contributing_ids`** — `_aggregate_line_values` now gives the percent value and the
  dollar value **disjoint** id lists (each discount is percent XOR dollar), so a dollar-`once`'s
  presence handle is its own dollar coupon, not the percent coupon. (Resolves the old §3 once-handle
  fragility — no value changes, only which ids each value writes back to.)
- 🔜 **`SyncItem` / `SyncItem.prorate`** — **NOT vestigial yet**: still imported by
  `member_memberships_cancel.py` + `member_memberships_update_price.py` (the old-path callers). Remove
  `SyncItem` **as part of the §2.1 caller rewiring** — those two stop importing it there.
- ❓ **`gyms_stripe_connect_service.py` calls Stripe directly** (Connect-account onboarding) — the one
  other direct-Stripe caller outside `src/payments/`. Different domain (no payments-layer service);
  decide whether to route it through a service too. (Unchanged — flagged for the user.)
- ❓ **Applied-discount RLS vs view gate drift** — the filtered view
  `member_membership_applied_discounts` now gates on `stripe_sync_status NOT IN
  ('not_added','preview_add','preview_remove')`, but the `hide_incomplete_stripe_records` RLS policy
  in `access_rules/member_membership_applied_discounts.sql` still gates `USING (stripe_coupon_id IS
  NOT NULL)`. They mostly agree but can diverge (a `deleted` row has a coupon → passes RLS, hidden by
  view). Reconciling the RLS to the sync-status gate is a **schema/RLS change → needs a migration**;
  left for the user to decide (is coupon-presence RLS intentional belt-and-suspenders?). The stale
  comment in `set_applied_discount_coupon_id.sql` (says the *view* gates on coupon presence) rides on
  this decision.

---

## 3. Gotchas still live (don't get surprised)

- **Preview over-states a consumed-but-unstamped `once`** on an idle member — preview skips the
  pre-sync settle (a write), so the number is optimistic until the next real sync stamps it.
- **Consolidated fixed-dollar discount applies to the whole qty-N line**, not one member (percents
  are split ÷qty; dollars are summed). Inherent to Stripe coupon semantics on a quantity line —
  flag in product terms if family + fixed-dollar combos are common.
- **The writeback maps live items → rows by `stripe_price_id`.** A consolidated line is ONE Stripe
  item (qty N) → every family membership on that price gets the same `stripe_item_id` +
  `next_due_date`. That's intended.
- **Idempotency keys are suffixed** per Stripe sub-op (`:sub_create` / `:sub_update` /
  `:sub_cancel` in `PaymentSyncStripe`; `:freeze` / `:unfreeze` in `PaymentSyncFreeze`).
  `bulk_payment_sync` mints a fresh `uuid4()` per member.
- **`<> ALL(:excluded_statuses)`** in the reads — `excluded_statuses` is a Python list of enum
  *values* (strings); the column is cast `stripe_sync_status::text`. Verify the bind behaves on the
  live DB (I couldn't execute it).

---

## 4. The cardinal rules (repeat)
1. **One approved piece at a time. Never a big sweep.** Propose → wait → write.
2. **Never run migrations or seeds** — the user does. Tell them when a schema change needs a re-run
   (see §0 — `not_added`/NOT NULL/view changes are owed).
3. **Update the living docs** (`sync-guide`, `discounts-guide`, `payment_sync.mermaid`) in the SAME
   change that stabilizes the engine.
4. **Never reshape a test to pass against a broken path** — fix the engine/caller.
5. **Verify every change**: `py_compile` + `ruff` + DI build. The math is billing — when in doubt,
   trace a concrete dollar example.
6. **Commit + push at each milestone** so the worktree is never lost.
