# Payment-Sync Refactor — Handoff / TODO (what's LEFT)

> **Read this whole file before touching `src/member_memberships/service/payment_sync/`.**
> This is a slow, **human-in-the-loop** refactor of the **most billing-critical code in the
> backend** — it decides how real members are charged. Every change is **proposed, reviewed, and
> approved one piece at a time. Never a big sweep. Propose → wait → write.** A mistake here
> mis-bills real customers. (This rule also lives in `.claude/skills/sync-guide/SKILL.md` and
> `FastApiBackend/CLAUDE.md`.)
>
> This doc lists **what is still LEFT** and, in §1, **what already EXISTS** (so you don't redo it).
> The authoritative, always-current description of the engine is the **`sync-guide`** skill — read it
> alongside this, plus `memberships-guide`, `discounts-guide`, `payments-guide`, and the two diagrams
> (`payment_sync.mermaid`, `architecture.mermaid`). **Your FIRST job is §2.1 — make the tests work.**

---

## 0. Orientation — where everything is + how to work

- **Worktree:** this work lives in a git worktree under `.claude/worktrees/`, branch
  `worktree-membership-refactor-step1` (on origin). **Do NOT push without asking the user** (their
  standing rule — commit locally, ask before `git push`).
- **The engine:** `FastApiBackend/src/member_memberships/service/payment_sync/`.
- **The lifecycle callers (what drives the engine):**
  `FastApiBackend/src/member_memberships/service/memberships/` (start / cancel / update_price /
  freeze / mark_paid_cash / charge_card / update_discounts) + `member_memberships_base.py` (shared
  helpers), and `src/members/service/management/members_management_linked.py` (link / unlink).
- **Living docs — ALL CURRENT, read them:** the skills `sync-guide` (the engine — the deepest
  source), `memberships-guide` (plans + member_memberships data model + lifecycle callers),
  `discounts-guide` (the 3-table discount model), `payments-guide` (the Stripe primitives + the
  payments layer). Diagrams: `FastApiBackend/payment_sync.mermaid` (the orchestration flow, with the
  preview-vs-real branch) and `FastApiBackend/architecture.mermaid` (DI wiring). All were rebuilt this
  session to match the code — trust them, and keep them in sync if you change the engine.
- **The audit that started this:** `MANUAL_REVIEW.md` (repo root). Items #12–#29 drive this refactor.

### How to verify (do this after EVERY change)
The worktree has **no `.venv`**. Use your MAIN (non-worktree) checkout's venv. From `FastApiBackend/`:
```bash
python -m py_compile <files>
python -m ruff check <files>          # ruff 0.15; `--fix` auto-removes unused imports
# DI build / import smoke test (needs deps + settings):
# Point MAIN at YOUR primary (non-worktree) checkout's FastApiBackend — the one with a built .venv:
MAIN=/path/to/your/main-checkout/FastApiBackend
"$MAIN/.venv/bin/python" -c "
import os; from dotenv import dotenv_values
os.environ.update({k:v for k,v in dotenv_values('$MAIN/.env').items() if v is not None})
import sys; sys.path.insert(0,'src')
import src.shared.db_schema_path            # MUST import first (registers schema.* path)
import src.core.dependencies as d
d.DependencyInjector().payment_sync_service()
d.DependencyInjector().member_memberships_service()
d.DependencyInjector().members_management_service()
print('DI OK')
"
```
- `.venv` console scripts (`pytest`, `ruff`) have stale shebangs — invoke via
  `"$MAIN/.venv/bin/python" -m pytest|ruff`, not the bare script.
- `import src.shared.db_schema_path` **before** anything importing `schema.*`.
- The `.env` has one unquoted comma value (a CORS line) that breaks `source` — load with
  `dotenv_values`, as above.
- You **cannot execute SQL against the DB from a script here.** SQL files are verified by
  compile/ruff/DI + reasoning; the user runs the DB live. **Tests (§2.1) DO hit a live DB + Stripe.**
- The mermaids are validated with: `python3 ~/.claude/skills/mermaid-creation/scripts/check_siblings.py
  <file>` (0 violations), an `npx @mermaid-js/mermaid-cli` render, and a Mermaid-9 parse — see the
  `mermaid-creation` skill. Keep both diagrams current if you touch the engine/DI.

### Schema / migrations (user runs them, NEVER you)
The schema changes for this refactor have a generated migration (`Database/supabase/migrations/
20260606214156_sync_update.sql`) — the user ran it. The changes it carries:
`stripe_sync_status` enum (`not_added` / `applied` / `deleted` / `preview_add` / `preview_remove` /
`migrating`), both `stripe_sync_status` columns `NOT NULL DEFAULT 'not_added'`; the client views
`member_memberships` + `member_membership_applied_discounts` gate on `stripe_sync_status NOT IN
('not_added','preview_add','preview_remove')`; the immutability triggers
(`trg_prevent_cancel_date_overwrite` locks `cancel_date` only once `stripe_sync_status = 'deleted'`;
`trg_prevent_stripe_item_id_overwrite` blocks `stripe_item_id` changes EXCEPT while `'migrating'`); a
CHECK on `member_membership_applied_discounts` forbidding `stripe_sync_status = 'migrating'`.
**Per `Database/CLAUDE.md`: never run `supabase` migrations or `python_data/main.py` seeds yourself.**
If you change a schema file, tell the user to re-run the migration.

---

## 1. Current engine state — what EXISTS now (do NOT redo it)

`PaymentSyncService` is a **declarative reconciler**: on every membership mutation it throws away
whatever Stripe has, **re-derives the full desired subscription state from the DB**, converges Stripe,
then writes everything back to the DB. The CRM owns intent; Stripe owns outcomes. The service is a
**thin orchestrator** over focused sub-services (DI-wired in `src/core/dependencies.py`).

### 1a. The three entry points (`payment_sync_service.py`)
- **`update_payments_recurring(member_id, idempotency_key, pay_first_invoice_out_of_band=False,
  proration_behavior="none") -> None`** — the real sync. Sequence:
  1. **resolve** parent + gym account — `BillingParentResolver.resolve(member_id) -> (ParentProfile,
     stripe_account_id)` (follows `members.account_linked_to_id` once to the paying parent).
  2. **maintenance freeze re-apply** — `PaymentSyncFreeze.sync_freeze_state(parent, account, *,
     idempotency_key)` converges `pause_collection` to the parent's DB freeze window. **REAL ONLY.**
  3. **settle once-discounts** — `PaymentSyncOnceDiscounts.sync_once_discounts(parent, account)`:
     reads the family's unconsumed `once` discounts + the live sub's coupons; a coupon gone from the
     sub = consumed → `mark_once_consumed` stamps `end_date = today`. **Runs in preview too.**
  4. **build** — `PaymentSyncBuilder.build_sync_params(parent, account, preview=False)`: reads the
     active recurring memberships (each carrying its applied discounts), groups by `price_id`,
     **delegates coupon resolution to `PaymentSyncDiscounts.resolve(groups, account)`**, assembles the
     `IntervalBucket`. Returns `SyncParams(bucket, parent, stripe_account_id, coupon_links,
     memberships)`. **No DB writes.**
  5. **execute** — `PaymentSyncStripe.execute_sync(...)`: items → existing sub? `update` : `create`;
     empty bucket + existing sub → `cancel`; else no-op. Explicit `proration_behavior`. Returns
     `PaymentsSubscriptionResponse | None`.
  6. **writeback** — `PaymentSyncWriteback.write(params, sub_result)` persists EVERYTHING (see 1c).
  Returns **`None`** — callers confirm by reading the DB (`stripe_sync_status`).
- **`preview_update_payments_recurring(member_id, proration_behavior="none") -> PaymentsInvoicePreviewResponse | None`**
  — resolve → **settle once-discounts (yes, same as real)** → `build_sync_params(preview=True)` →
  `preview_execute_sync` (Stripe upcoming-invoice preview; `preview_update`/`preview_create`; never
  cancels). **Skips ONLY: the freeze re-apply + the convergence writeback.** It DOES settle (stamps a
  consumed `once`'s end_date — a settled fact) and DOES find-or-create coupons (idempotent, gym-wide),
  so the preview total reflects discounts. (This was a common doc bug — preview is NOT write-free; it
  settles. The boundary is "convergence writeback + freeze," not "writes.")
- **`bulk_payment_sync(member_ids) -> None`** — loops, fresh `uuid4()` key per member, swallows
  per-member errors. Used by the plan-reprice fan-out (`membership_plans`) and the future reconciler.

### 1b. Sub-service map (files under `payment_sync/`)
- `payment_sync_service.py` — `PaymentSyncService` orchestrator. DI deps: `db_pool`,
  `subscription_service`, `parent_resolver` (`BillingParentResolver`), `freeze` (`PaymentSyncFreeze`),
  `once_discounts` (`PaymentSyncOnceDiscounts`), `builder` (`PaymentSyncBuilder`). Builds `_stripe`
  (`PaymentSyncStripe`) + `_writeback` (`PaymentSyncWriteback`) internally.
- `payment_sync_builder.py` — `PaymentSyncBuilder(db_pool, discounts)`: `build_sync_params` →
  `_group_by_price` / `_build_bucket`; delegates coupons to `PaymentSyncDiscounts`.
- `payment_sync_discounts.py` — `PaymentSyncDiscounts(discount_service)`: owns the discount MATH
  (`_aggregate_line_values`) + `resolve(groups, account) -> ResolvedDiscounts`; builds
  `PaymentSyncCoupons` internally. **Math (lock it in tests):** per line, per mode (`once`/`ongoing`):
  percents compound **sequentially within a membership** (`eff = 1 − Π(1−pⱼ/100)`) then **÷ quantity**;
  dollars **summed**; percent value + dollar value carry **disjoint** `contributing_ids`. Dollar coupon
  attaches before percent (Stripe sequences dollar→percent).
- `payment_sync_coupons.py` — `PaymentSyncCoupons(discount_service)`: deterministic id
  (`pct_<bps>_<mode>` / `amt_<cents>_<mode>`) + validate-or-replace; **delegates all Stripe coupon I/O
  to `PaymentsStripeDiscountService`** (no direct Stripe SDK in the engine).
- `payment_sync_once_discounts.py` — `PaymentSyncOnceDiscounts(db_pool, subscription_service)`:
  `sync_once_discounts` (pre-sync settle) + `_current_coupon_ids` (live sub read).
- `payment_sync_freeze.py` — `PaymentSyncFreeze(subscription_service)`: `sync_freeze_state` (DB-first
  `pause_collection`; reads `parent.is_frozen` + `freeze_end_date`).
- `payment_sync_stripe.py` — `PaymentSyncStripe(subscription_service)`: `execute_sync` /
  `preview_execute_sync` / `_sync_bucket`. Idempotency suffixes `:sub_create` / `:sub_update` /
  `:sub_cancel`.
- `payment_sync_writeback.py` — `PaymentSyncWriteback(db_pool, subscription_service)`: `write` +
  `_apply_membership_rows` + `_mark_removed_deleted`. **Composes** `price_writeback.py` (`PriceWriteback`).
- `payment_sync_queries.py` — `PaymentSyncQueries`: all the SQL loads (see 1d).
- `payment_sync_schema.py` — `ActiveMembershipRow` (carries `discounts`), `AppliedDiscount`,
  `OnceDiscount`, `IntervalBucket`, `LineDiscountValue` (Field bounds + percent-XOR-dollar validator),
  `ResolvedDiscounts`, `SyncParams`. **`SyncItem` is gone.**
- shared: `src/shared/billing_parent.py` (`ParentProfile`), `billing_parent_resolver.py`
  (`BillingParentResolver` — `resolve_parent` → `ParentProfile`, `resolve` → `(ParentProfile,
  account)`), `gym_timezone.py` (`gym_today`, `stripe_ts_to_gym_date`, `get_gym_timezone`),
  `db_first_helpers.py` (`cleanup_pending_row`, **`sync_or_revert`**, `staged_preview`,
  `SyncNotConfirmedError`).

### 1c. The writeback (`PaymentSyncWriteback.write`, real path only)
In order: `_apply_membership_rows` (map live `sub_result.items` by `stripe_price_id` → each membership
row → `apply_membership_sync` = `stripe_item_id` + `next_due_date` (gym-local via
`stripe_ts_to_gym_date`) + `'applied'`); coupon links (`set_applied_discount_coupon_id` per
contributing applied-discount → `stripe_coupon_id` + `'applied'`); `_mark_removed_deleted` (cancelled
rows confirmed absent from the live sub → `mark_membership_deleted` = `'deleted'`);
`update_profile_sub_id` (parent `stripe_sub_id_month`, `None` if cancelled); `PriceWriteback.
sync_prices_from_stripe` (post-discount per-plan + parent monthly totals). **`stripe_item_id` is never
nulled** — a `deleted` row keeps its line id as the historical invoice-line record.

### 1d. The caller contract (DB-first → pre-sync → verify → revert)
Documented fully in **`sync-guide` §2**. Every lifecycle caller (via `sync_or_revert` /
`staged_preview` in `db_first_helpers.py`):
0. **Pre-sync** (`_pre_sync_payments(member_id)` on `MemberMembershipsBase`, fresh key) — converge to a
   clean DB↔Stripe baseline before mutating, so it never builds on a drifted DB. Previews skip this.
1. **Write the desired DB state** (insert pending row / set `cancel_date` / write new `price_id` /
   freeze window / `account_linked_to_id`).
2. **Call the param-less sync.**
3. **Verify the writeback landed** (read `stripe_sync_status` via `_get_sync_status` on the unfiltered
   base), **else revert** the DB change.

| caller | DB write | verify | revert |
| --- | --- | --- | --- |
| start (recurring) | insert pending (`not_added`) | row → `applied` | delete pending row |
| cancel | set `cancel_date` (status stays `applied`) | row → `deleted` | clear `cancel_date` (allowed: not yet `deleted`) |
| update_price | new `price_id` + stage `migrating` | row → `applied` | restore old price (reset `applied`) |
| freeze / unfreeze | write / clear freeze window | — (no row status) | restore / re-clear window (revert-on-exception) |
| link / unlink | set / clear `account_linked_to_id` | — (child has no recurring) | unlink / re-link (revert-on-exception) |
| charge_card / mark_paid_cash (#23) | — (inject `BillingParentResolver`, validate parent) | — | — (no sync) |

**`migrating` is for PRICE MIGRATIONS ONLY** — it's the one state where the immutable `stripe_item_id`
may move to a new price's line. **Cancel does NOT use `migrating`** — `cancel_date` locks only once the
row is actually `'deleted'`, so an unconfirmed cancel reverts by clearing `cancel_date`.

### 1e. Key SQL (engine + callers)
`payment_sync/`: `get_active_recurring.sql` (reads `member_memberships_unfiltered`, `cancel_date IS
NULL AND stripe_sync_status::text <> ALL(:excluded_statuses)`), `get_family_ids.sql`,
`apply_membership_sync.sql`, `get_cancelled_recurring.sql`, `mark_membership_deleted.sql`,
`sync_prices_by_plan.sql`, `sync_profile_monthly_total.sql`, `update_profile_sub_ids.sql`,
`update_stripe_item_id.sql`. `applied_discounts/`: `get_applied_discounts_by_member.sql` (date +
status filtered: `(end_date IS NULL OR end_date > :today) AND stripe_sync_status::text <>
ALL(:excluded_statuses)`), `set_applied_discount_coupon_id.sql` (coupon + `'applied'`),
`mark_once_consumed.sql`, `get_unconsumed_once_discounts.sql`. caller SQL (`member_memberships/sql/`):
`member_memberships_insert.sql` (parameterized `stripe_sync_status` — `not_added` real / `preview_add`
preview), `member_memberships_cancel.sql` (sets `cancel_date` only), `member_memberships_uncancel.sql`
(clears `cancel_date`), `member_memberships_update_price.sql` (price + `:sync_status` CAST),
`member_memberships_sync_status.sql` (verify read), `set_membership_sync_status.sql` (preview staging).
`_excluded_statuses(preview)` lives in `payment_sync_queries.py` (real drops all `preview_*`; preview
keeps `preview_add`, drops `preview_remove`; both drop `deleted`).

### 1f. Done this session (do NOT redo)
Part E (discounts ride the membership); `PaymentSyncBuilder` + `PaymentSyncDiscounts` split; coupon I/O
delegated to `PaymentsStripeDiscountService`; explicit `proration_behavior` (no `item.prorate`);
date filter in SQL; `LineDiscountValue` validators; dead `IntervalBucket.total_price` removed;
`PaymentSyncWriteback`; `-> None`; `#16` unfiltered-base read; **all lifecycle callers rewired DB-first
+ verify-revert + pre-sync**; the `migrating`/`deleted` trigger design; never-archive-prices;
gym-local dates; `stripe_sync_status` NOT NULL; **preview staging for start/cancel/update_price**;
`SyncItem` removed; **`tests/helpers/service_factory.py` fixed** (constructs the current services); all
docs + diagrams current; minor cleanups (orphan `price`, dead `stripe_ts_to_date`, disjoint
`contributing_ids`).

---

## 2. WHAT'S LEFT (in priority order)

### 2.1 🔴 TESTS — restabilize + add (DO THIS FIRST)

The engine + callers are rewritten and the DI builds, but the **test files are stale or missing**. The
factory is fixed (so setup no longer TypeErrors), but the tests themselves must be made real.

**How the test suite works (read `FastApiBackend/CLAUDE.md` "Integration tests…"):**
- Tests run against a **real shared LOCAL Supabase DB + a real shared Stripe TEST Connect account** —
  **no transaction rollback, no ephemeral DB.** Every test must delete exactly what it created.
- Use the function-scoped **`created`** fixture (`CreatedResources` in `tests/conftest.py`):
  create-and-track wrappers `await created.member(...)/.plan(...)/.discount(...)/.payment_method()/
  .test_clock(...)`, and manual trackers `created.track_customer/track_product/track_price/
  track_coupon/track_plan_db/track_discount/track_member(<id>)`. Teardown is clocks → members → plans
  → discounts → Stripe customers → coupons → archive prices/products (FK-safe, best-effort).
- **NEVER delete the single seeded gym** (`tests/seed_constants.py`) or shared seed data.
- Build services via `tests/helpers/service_factory.py` (`build_member_memberships_service`,
  `build_payment_sync_service`, `build_member_management_service`, `build_membership_plans_service`,
  `build_payment_services`) — already fixed to the current constructors.
- Run: `"$MAIN/.venv/bin/python" -m pytest tests/...` (the bare `pytest` shebang is stale).

**🚫 The cardinal test rule (`FastApiBackend/CLAUDE.md`): NEVER write a test around a production bug.**
If a test fails because the engine/caller is wrong, **fix the engine/caller** — do not loosen the
assertion, call a method twice, flip a column via raw SQL instead of the real path, or `xfail`/`skip`
with a reason pointing at our code. If you can't fix it in the same change, **stop and surface the bug
to the user.** Tell-tale smells are listed in the CLAUDE.md — read them.

**Stale test files to fix or delete:**
- `tests/member_memberships/service/payment_sync/test_payment_sync_builder.py` — references **removed**
  symbols (`plan_line_discounts`, `LineDiscountPlan`, `AppliedDiscountSnapshot`). Rewrite against the
  current `PaymentSyncBuilder` + `PaymentSyncDiscounts`, or delete and replace with the new tests below.
- `test_discount_semantics.py`, `test_price_writeback.py` (if present) — check against the current
  code; they were the ones the broken factory failed at setup. Update to the current services.
- Delete any test asserting a removed route/method now 404s (no "this route is gone" tests).

**New coverage needed (the new surface has none):**
1. **`PaymentSyncDiscounts._aggregate_line_values` (the math)** — lock the trace: one 30% + one 20%
   `ongoing` on the same membership → effective 44% (not 50%); a line of qty 2 with member A at
   effective 44% and member B at 10% → line percent `(0.44+0.10)/2 = 27%`; 100% stays 100%; dollar
   discounts summed (e.g. $10 + $10 = $2000 cents); an expired discount (past `end_date`) excluded by
   the read; percent vs dollar get **disjoint** `contributing_ids`.
2. **`LineDiscountValue` validators** — percent `gt=0, le=100`; dollar `gt=0`; exactly one of
   percent/dollar (the `@model_validator`).
3. **`PaymentSyncOnceDiscounts`** — a `once` whose coupon is gone from the live sub gets `end_date`
   stamped; one still present does not; idempotent re-run.
4. **`PaymentSyncWriteback`** — maps live items → rows by `stripe_price_id`; stamps `applied` + line id
   + gym-local `next_due_date`; stamps `deleted` only for cancelled-and-absent rows; never nulls
   `stripe_item_id`.
5. **`sync_or_revert` (`db_first_helpers`)** — on sync exception → revert + re-raise; on `verify_fn`
   False → revert + `SyncNotConfirmedError`; revert failure is logged, not masked.
6. **`staged_preview`** — stages, runs preview, ALWAYS cleans up (even on exception).
7. **Gym-local dates** — `stripe_ts_to_gym_date` Tokyo (UTC+9) off-by-one: midnight JST timestamp →
   the JST date, not the UTC-previous date.
8. **End-to-end caller flows (the high-value ones — integration, with `created`):**
   - **start** recurring → row flips `not_added`→`applied`, gets a line id + next_due_date; a Stripe
     failure deletes the pending row.
   - **cancel** → `cancel_date` set, row → `deleted`; the `PaymentsResourceNotFoundError` tolerance
     (line already gone → still marks deleted, cancel stands).
   - **update_price** → row migrates to the new price's line (this exercises the `migrating` trigger —
     confirm the line id actually moved); a failed migration restores the old price.
   - **freeze/unfreeze** → `pause_collection` on/off; window written/cleared.
   - **link/unlink** → `account_linked_to_id` set/cleared; parent sub recomputed.
   - **apply_discounts** → snapshot rows written, coupon resolved + stamped back, total reflects it.
   - **preview** (start/cancel/update_price) → returns the HYPOTHETICAL invoice (staged row reflected),
     and the staged `preview_*` row is gone afterward (cleanup ran). Confirm a real sync racing isn't
     tested until the lock (§2.2) exists — note the gap, don't fake it.
9. **DB triggers** (these need the live DB, which tests have): `cancel_date` immutable once `deleted`
   but clearable while not-deleted; `stripe_item_id` immutable except while `migrating`; the
   applied-discount `migrating` CHECK rejects it.

When §2.1 is green, the engine is trustworthy and the rest can build on it.

### 2.2 🟡 Per-parent concurrency lock (#25) — LOAD-BEARING, do next
**The need:** while one op syncs a family, no other op (admin, bulk job, second tab, a preview, or the
webhook in §2.4) may run a conflicting sync on the **same paying-parent family**. Today there is **zero
guard**: two concurrent `update_payments_recurring` on one family both read, both call Stripe, both
write back last-write-wins (the sync is a multi-transaction cascade with Stripe HTTP in the middle).
On billing code this mis-bills / desyncs. **It also blocks #2.3/#2.4/#2.5** (they stage `preview_*` /
converge and must not race a real sync — see the §3 preview-race gotcha).
- **Use a Postgres advisory lock** (Supabase is Postgres): `pg_try_advisory_lock(hashtext(
  parent_member_id::text))` acquired at the start of the op, held across the whole DB+Stripe sequence,
  released in `finally`. `SELECT … FOR UPDATE` is insufficient (one txn only; the sync spans many txns
  + network I/O). Per-parent, NOT one global lock (that serializes the whole gym).
- **Recommended (confirm with user):** fail-fast — on lock-not-acquired raise **409 "member is being
  updated, try again"**. Attach via a shared decorator/context-manager around the lifecycle callers +
  the sync entry points (incl. preview + the webhook).
- **Open Qs for the user (ASK before building):** advisory-lock (backend serialization) vs. a
  `member_locks` UI edit-session table (TTL/heartbeat, "Bob is editing → read-only") vs. both;
  fail-fast 409 vs. block-with-timeout. The user leaned "fix it properly" but the flavor is unconfirmed.

### 2.3 🟡 Preview due-now vs recurring split (#19)
Today `preview_*` returns ONE `PaymentsInvoicePreviewResponse`. Restructure to:
- `due_now`: `{amount, currency, lines[]}` where each line carries a **kind** (`base` / `proration` /
  `discount`) + period — so the CRM renders "Due now $X = $Y proration + $Z first period − $W discount".
- `recurring`: `{amount, currency, lines[]}` — the steady per-cycle post-discount total.
Touches `payments_invoice_schema.py`, `payment_sync_stripe.py` (`preview_execute_sync` → split), the
preview service + `member_memberships_router.py` preview endpoints, `Database/openapi.json` (now
gitignored — regenerated at runtime, don't hand-edit), the CRM preview UI, tests. **This is the "new
feature" the user said to hold until the rest of the batch was reviewed — confirm before starting.**

### 2.4 🟡 Webhook-driven once-discount sync refresh (§2.7 idea — keep the DB in sync sooner)
When Stripe invoices a subscription, a consumed `once` discount's coupon drops off the live sub —
exactly what the once-settle detects. Today that's only picked up on the next lifecycle caller or
(eventually) the daily reconciler. **Add to the `invoice.paid` webhook**
(`src/stripe_webhooks/service/invoice_paid_handler.py`): after it persists the invoice/charge rows,
resolve the paying parent and call `update_payments_recurring` (or at least
`PaymentSyncOnceDiscounts.sync_once_discounts`) for that family — so a consumed `once`'s `end_date` is
stamped **promptly**. Mint a fresh idempotency key; idempotent. **Must take the §2.2 per-parent lock**
(a webhook sync must not race a caller's sync).

### 2.5 🟡 Discount preview staging
`preview_apply_discounts` still previews the membership's **current** discounts. Give it the same
staging treatment as start/cancel/update_price: accept proposed `add_preset_ids` / `remove_applied_ids`,
stage `preview_add` / `preview_remove` **applied-discount** rows (the discount read toggles on the same
`:excluded_statuses`), preview, clean up. Needs a signature + router change. **Also race-bound by §2.2.**

### 2.6 Open decisions (ask the user) + minor cleanups
- **❓ RLS vs view gate drift** — the filtered view gates on `stripe_sync_status NOT IN (...)`, but the
  `hide_incomplete_stripe_records` RLS policy in `access_rules/member_membership_applied_discounts.sql`
  still gates `USING (stripe_coupon_id IS NOT NULL)`. They mostly agree but can diverge (a `deleted`
  row has a coupon → passes RLS, hidden by view). Reconciling to the sync-status gate is a schema/RLS
  change (migration). User to decide if the coupon-presence RLS is intentional.
- **❓ `gyms_stripe_connect_service.py` calls Stripe directly** (Connect onboarding) — the one other
  direct-Stripe caller outside `src/payments/`. Different domain; decide whether to route it through a
  service too.

---

## 3. Gotchas still live (don't get surprised)
- **🔴 Preview-remove races a real sync (closed only by §2.2).** Staging `preview_remove` on a real
  `applied` row: the preview read excludes it (good), but `_EXCLUDED_REAL` ALSO excludes
  `preview_remove`, so a **concurrent real sync drops the membership's live Stripe line → mis-bill.**
  `preview_add` (start preview) is safe (a real sync ignores it). The user has accepted this interim
  risk ("I'll add the lock after") — but it MUST be closed by the per-parent lock before this is
  trusted in production. Cleanup is `finally`-bounded, not race-safe.
- **Consolidated fixed-dollar discount applies to the whole qty-N line** (percents are split ÷qty;
  dollars summed). Inherent to Stripe coupon semantics on a quantity line.
- **The writeback maps live items → rows by `stripe_price_id`** — a consolidated line is ONE Stripe
  item (qty N), so every family membership on that price gets the same `stripe_item_id` +
  `next_due_date`. Intended.
- **`<> ALL(:excluded_statuses)`** binds a Python list of enum *values* (strings); the column is cast
  `::text`. **Enum binds in SQL use `CAST(:p AS type)`**, never `:p::type` (asyncpg/text() breaks on
  `:p::`). This bit the membership-plans update path; it's why `update_price` / `set_membership_sync_
  status` SQL use `CAST(:sync_status AS stripe_sync_status)`.
- **Idempotency keys are suffixed** per Stripe sub-op (`:sub_create`/`:sub_update`/`:sub_cancel` in
  Stripe; `:freeze`/`:unfreeze` in Freeze). Pre-sync + `bulk` mint fresh `uuid4()`.
- **Reverse-drift residual:** if Stripe converged but the writeback failed to stamp the column (rare —
  last step), the verify-revert undoes the DB change while Stripe holds it. The idempotent re-sync /
  reconciler fixes it next run. This keeps things in sync "as much as possible" without a full saga.

---

## 4. Cardinal rules (repeat)
1. **One approved piece at a time. Never a big sweep.** Propose → wait → write.
2. **Never run migrations or seeds** — the user does. Tell them when a schema file changes.
3. **Don't `git push` without asking.** Commit locally; ask before pushing.
4. **Never reshape a test to pass against a broken path** — fix the engine/caller, or surface the bug.
5. **Update the living docs** (`sync-guide`, `memberships-guide`, `discounts-guide`, `payments-guide`,
   both `.mermaid` diagrams) in the SAME change that changes the engine. Validate mermaids per the
   `mermaid-creation` skill.
6. **Verify every change**: `py_compile` + `ruff` + DI build; the math is billing — trace a concrete
   dollar example when in doubt.
