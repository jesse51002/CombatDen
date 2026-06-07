# Payment-Sync Refactor — Handoff (current state, fully detailed)

> **Read this whole file before touching `src/member_memberships/service/payment_sync/`
> or the discount/membership lifecycle callers.** This is a slow, **human-in-the-loop**
> refactor of the **most billing-critical code in the backend** — it decides how real
> members are charged. Every engine/caller change is **proposed, reviewed, and approved one
> piece at a time. Never a big sweep. Propose → wait → write.** A mistake mis-bills real
> customers. (Same rule in `.claude/skills/sync-guide/SKILL.md` and `FastApiBackend/CLAUDE.md`.)
>
> The authoritative, always-current description of the engine is the **skills** — read them
> alongside this doc: `sync-guide` (the engine, deepest source), `memberships-guide` (plans +
> member_memberships + lifecycle callers), `discounts-guide` (the 3-table discount model),
> `payments-guide` (Stripe primitives + webhooks). Diagrams: `FastApiBackend/payment_sync.mermaid`,
> `FastApiBackend/architecture.mermaid`.
>
> ⚠️ **The skills are slightly STALE after this session** — see §3.1. Updating them is the
> first remaining task. Trust the CODE over the skills where they disagree until §3.1 is done.
>
> **IMPORTANT — skills live in the worktree, not the codebase root.** Use
> `.claude/worktrees/membership-refactor-step1/.claude/skills/` (checked out on this branch).
> The codebase-root `.claude/skills/` is a different/older branch and will mislead you.

---

## 0. Orientation — where everything is + how to work

- **Worktree:** `.claude/worktrees/membership-refactor-step1`, branch
  `worktree-membership-refactor-step1`. **Do NOT `git push` without asking** (standing rule —
  commit locally, ask before pushing). Nothing has been pushed this session.
- **Engine:** `FastApiBackend/src/member_memberships/service/payment_sync/`.
- **Lifecycle callers:** `FastApiBackend/src/member_memberships/service/memberships/`
  (start / cancel / update_price / freeze / mark_paid_cash / charge_card / update_discounts) +
  `member_memberships_base.py`, and `src/members/service/management/members_management_linked.py`
  (link / unlink).
- **The audit that started this:** `MANUAL_REVIEW.md` (repo root). Items #12–#29.

### How to run the tests / verify (do after EVERY change)
The worktree has **no `.venv` / `.env`**. Use your MAIN (non-worktree) checkout's venv + `.env`.
A reusable runner script exists at `$CLAUDE_JOB_DIR/tmp/runpt.py` (only in the session that made
it); the equivalent inline form:
```bash
MAIN=/var/home/jm/Documents/CombatDen/codebase/FastApiBackend
WT=/var/home/jm/Documents/CombatDen/codebase/.claude/worktrees/membership-refactor-step1/FastApiBackend
"$MAIN/.venv/bin/python" -c "import os,sys;from dotenv import dotenv_values;\
os.environ.update({k:v for k,v in dotenv_values('$MAIN/.env').items() if v});\
os.chdir('$WT');sys.path.insert(0,'$WT');import pytest;sys.exit(pytest.main(['-q','-p','no:cacheprovider','<paths>']))"
```
- `.env` has one unquoted-comma CORS line that breaks `source`; `dotenv_values` is why.
- py_compile + `"$MAIN/.venv/bin/python" -m ruff check <files>` (ruff 0.15). `make format` churns
  unrelated files — hand-format, ruff is the gate.
- DI build smoke test: `import src.shared.db_schema_path` FIRST, then build the providers:
  `d.DependencyInjector().member_memberships_service()` / `.payment_sync_service()` /
  `.stripe_webhooks_service()`.
- **Tests hit a real shared LOCAL Supabase + a real shared Stripe TEST Connect account** — no
  rollback, no ephemeral DB. Every test deletes exactly what it creates via the **`created`**
  fixture (`tests/conftest.py`). NEVER delete the single seeded gym (`tests/seed_constants.py`).
- **You CANNOT run migrations or seeds** — the user runs them (`Database/CLAUDE.md`). Tell the
  user when a schema/seed file changes so they re-run.
- mermaids validated via `~/.claude/skills/mermaid-creation/scripts/check_siblings.py` + an
  `npx @mermaid-js/mermaid-cli` render + a Mermaid-9 parse.

### Commits this session (all LOCAL, none pushed), newest first
| hash | what |
| --- | --- |
| `4fa390d` | test: discount preview staging (add-preview cleans up / remove-preview reverts) |
| `feb160e` | test: update discount call-sites to split add/remove |
| `4d04d25` | feat: split discount apply → `add_discounts` / `remove_discounts`, each w/ preview (§2.5) |
| `be67a9d` | fix(db): view + RLS gate on stripe-id AND sync_status, both tables (§2.6) |
| `03ffcac` | feat: invoice.paid webhook settles consumed once discounts (§2.4) |
| `ecc27ac` | fix(seed): historical cancelled memberships → 'deleted' |
| `84600e5` | fix(billing): read item coupons via `discount.source.coupon` (Bug #2) |
| `7bbe1da` | fix(billing): one-time start stamps `applied` (Bug #1) |
| `4d4be16` | test: restabilize payment-sync suite + add unit coverage |

`e56838f` (prev session) rewrote this doc; everything above is THIS session. The only untracked
file is `Database/supabase/migrations/20260606214156_sync_update.sql` (user manages migrations).

---

## 1. The schema / migration baseline (already run by the user)
The migration `20260606214156_sync_update.sql` added the `stripe_sync_status` enum
(`not_added`(default) / `applied` / `deleted` / `preview_add` / `preview_remove` / `migrating`),
both `stripe_sync_status` columns `NOT NULL DEFAULT 'not_added'`, the immutability triggers
(`cancel_date` locks only once `'deleted'`; `stripe_item_id` immutable except while `'migrating'`),
and a CHECK forbidding `'migrating'` on applied-discount rows.

> **§2.6 (this session) changed the views + RLS — the migration must be RE-RUN.** See §3.2.

---

## 2. What's DONE this session (do NOT redo)

### 2.1 The test suite is restabilized + GREEN (`4d4be16` + the bug-fix commits)
- Fixed 3 import-broken files: rewrote `test_payment_sync_builder.py` →
  `test_payment_sync_discounts.py` (against `PaymentSyncDiscounts._aggregate_line_values`);
  fixed the 2 payments tests importing the deleted `stripe_coupon_metadata` module.
- New pure-unit coverage: the discount math (27% / 44% traces), `LineDiscountValue` validators,
  `PaymentSyncCoupons.coupon_id` + `_matches_value` + `find_or_create`, `sync_or_revert` /
  `staged_preview` / `cleanup_pending_row` (`tests/shared/test_db_first_helpers.py`),
  `stripe_ts_to_gym_date` off-by-one (`tests/shared/test_gym_timezone.py`).
- Fixed ~20 stale tests to current contracts: simplified coupon model (no metadata,
  caller-supplied `coupon_id`), required `gym_timezone` on sub update requests, item-level
  discounts, `update_membership` never archiving a Stripe price, removed `members.linked_discount_id`
  column, the real `link_account` flow (create_member ignores `account_linked_to_id`), `set_price`
  never archiving the old Stripe price.
- **Test-infra fixes:** `cleanup.delete_member_data` now deletes `member_charges` / `member_invoices`
  first (FK-safe — the webhook can write them for a test member); the mid-cycle coupon read uses
  `discount.source.coupon` (see Bug #2); stripe_webhooks fixtures insert `applied` memberships and
  assert gym-local `next_due_date`.
- **The whole suite is green** except **7 pre-existing rewards tests** (`GET /rewards/{reward_id}`
  is unwired — UNRELATED to this refactor; user said leave for now — see §3.5).

### 2.2 Bug #1 — one-time `start` now stamps `applied` (`7bbe1da`)
The recurring path stamps `applied` via `PaymentSyncWriteback`; the one-time path runs no sync and
only set `stripe_item_id`, so the row stayed `not_added` → hidden by the filtered `member_memberships`
view → a purchased one-time membership was invisible in the CRM. **Same root cause that hid all 118
existing memberships after the migration.** Fix: `update_stripe_item_id.sql` (used ONLY by the
one-time start) now also stamps `stripe_sync_status='applied'`. Also fixed the **seed** (`ecc27ac` +
within `7bbe1da`): the two direct-DB-insert membership paths (`generators/memberships.py` historical,
`api_creation/overdue_members.py` overdue) now insert a real status — `deleted` for cancelled
historical (matches the real cancel flow), `applied` otherwise. The API seed path already stamps it.
**The live DB was backfilled this session** (118 memberships + 2 applied discounts → `applied`).

### 2.3 Bug #2 — `get_subscription()` reads item coupons via `discount.source.coupon` (`84600e5`)
Stripe moved the coupon to `discount.source.coupon` (`discount.coupon` is now null), and
`_retrieve_subscription` didn't expand item discounts — so `get_subscription().items[*].discounts`
was **always empty**, blinding `PaymentSyncOnceDiscounts._current_coupon_ids` (it would mark a pending
`once` discount consumed prematurely). Fix in `payments_subscription_base.py`: `_retrieve_subscription`
expands `items.data.discounts`; new `_coupon_id_from_discount` helper reads `source.coupon` (legacy
`.coupon` fallback, skips bare `di_` ids). Empirically confirmed against live Stripe.

### 2.4 Webhook-driven once-discount settle (`03ffcac`) — §2.4 DONE
`invoice.paid` now calls **`PaymentSyncService.settle_once_discounts(member_id)`** (new thin method:
resolve parent → `PaymentSyncOnceDiscounts.sync_once_discounts`) so a consumed `once`'s `end_date` is
stamped promptly instead of waiting for the next manual op / reconciler. In `invoice_paid_handler.py`,
subscription path only, **best-effort** (a settle failure is logged, never rolls back the
invoice/charge writes; it runs in its own DB transaction). No-op when the family has no unconsumed
`once`. DI wires `payment_sync_service` into `InvoicePaidHandler`; the webhook conftest builds it.
**STILL needs the §2.2 per-parent lock** (a webhook settle must not race a caller's sync).

### 2.5 Discount apply SPLIT into add/remove, each with a `preview` bool (`4d04d25` + `feb160e` + `4fa390d`) — §2.5 DONE
Replaced the combined `apply_discounts(add_preset_ids, remove_applied_ids)` with **two separate
operations**:
- `MemberMembershipsUpdateDiscounts.add_discounts(item_id, member_id, preset_ids, idempotency_key, preview=False)`
- `MemberMembershipsUpdateDiscounts.remove_discounts(item_id, member_id, applied_ids, idempotency_key, preview=False)`
- Each returns `PaymentsInvoicePreviewResponse | None`. `preview=True` stages with **no commit**:
  add → insert `preview_add` applied-discount rows (then deleted on cleanup); remove → stamp the
  rows `preview_remove` (then reverted to `applied`). Runs the read-only preview build, which
  **already** toggles `:excluded_statuses` (keeps `preview_add` in / drops `preview_remove`), then
  ALWAYS cleans up via `staged_preview`. Previews skip the pre-sync.
- New SQL: `insert_applied_discount.sql` parameterized with `:sync_status`;
  `set_applied_discount_sync_status.sql` (stamp preview_remove + revert). Helpers in the service:
  `_add_preset_snapshots(sync_status=…) -> list[UUID]`, `_set_snapshots_status`, `_delete_snapshots`.
- Schema: `MemberMembershipsApplyDiscountsRequest` → `MemberMembershipsAddDiscountsRequest`
  (`preset_ids` + `preview`) and `MemberMembershipsRemoveDiscountsRequest` (`applied_ids` + `preview`),
  each rejecting empty + duplicate lists.
- Router: `POST /discounts/add` + `POST /discounts/remove` (each does real-or-preview via
  `request.preview`, returns `PaymentsInvoicePreviewResponse | None`) **replace** `PUT /discounts`
  + `POST /discounts/preview`. Facade (`member_memberships_service.py`) exposes `add_discounts` /
  `remove_discounts`.
- Tests: all call-sites updated; `test_discount_preview_staging.py` verifies the staging machinery
  (add-preview reflects discount + leaves no row; remove-preview returns to full + reverts the row).
- ⚠️ Race: the `preview_remove` stamping on a real `applied` row is NOT race-safe vs a concurrent
  real sync (it would drop the live line) — the `finally` cleanup bounds the window but it is closed
  only by the §2.2 lock. Interim risk accepted; MUST close before production.

### 2.6 View + RLS gate on stripe-id AND sync_status — no drift (`be67a9d`) — §2.6 DONE (schema only; migration pending)
Both filtered views (`member_memberships`, `member_membership_applied_discounts`) and both
`hide_incomplete_stripe_records` RLS policies now gate on **both** `stripe_*_id IS NOT NULL` **AND**
`stripe_sync_status NOT IN ('not_added','preview_add','preview_remove')`, kept in lockstep so the
view and RLS can't diverge. Edited `Database/supabase/schemas/member_memberships.sql`,
`member_membership_applied_discounts.sql`, and the two `access_rules/` files. **No currently-visible
row is affected** (all live `applied`/`deleted` rows have their Stripe id). **Requires re-running the
migration** (§3.2).

### Done in PRIOR sessions (context)
The whole engine refactor: declarative reconciler `PaymentSyncService`; the
`PaymentSyncBuilder` / `PaymentSyncDiscounts` / `PaymentSyncOnceDiscounts` / `PaymentSyncWriteback` /
`PaymentSyncFreeze` split; discounts ride the membership; `BillingParentResolver`; the DB-first caller
contract (pre-sync → write → verify `stripe_sync_status` → `sync_or_revert` on failure); the
`migrating`/`deleted` trigger design; explicit `proration_behavior`; `stripe_item_id` never nulled.

---

## 3. What's LEFT (in priority order)

### 3.1 🔴 Update the living docs (the skills) — DO FIRST
The skills are now stale relative to the code changed this session. Update (each is a living
document; per the repo rules, code + doc must agree):
- **`memberships-guide`** §6 + §8: the discount op is now **add_discounts / remove_discounts** (two
  ops, not one `apply_discounts`); endpoints are `POST /discounts/add` + `POST /discounts/remove`
  (drop `PUT /discounts` + `POST /discounts/preview`). Each takes a `preview` bool. (The §6 row was
  partly updated this session for Bug #1's one-time `applied` stamping — verify it's consistent.)
  Also **§4 `set_price` is wrong**: it says set_price archives the old Stripe price; the code
  **never archives** ("every Stripe price stays active forever" — `membership_plans_price.py`).
- **`discounts-guide`** §4: the **preview now stages** (`preview_add`/`preview_remove`) and reflects
  the proposed change — update the "preview does not attach coupons / reflects current state" wording.
  Note add/remove are separate ops.
- **`payments-guide`** §6: `invoice.paid` handler now also triggers the once-discount settle
  (`PaymentSyncService.settle_once_discounts`). (§4 `_map_subscription` / `get_subscription` were
  updated this session for Bug #2 — verify.)
- **`sync-guide`** §6 / §10: the webhook once-settle (§2.4) is now BUILT (`settle_once_discounts`);
  the discount preview staging (§2.5) is now BUILT. Update the "deferred" framing.
- **2 stale test docstrings** still say `apply_discounts`:
  `tests/member_memberships/mid_cycle/test_add_discount_mid_cycle.py` line ~4 and
  `test_remove_discount_mid_cycle.py` line ~4.
- **Diagrams:** `payment_sync.mermaid` (once-settle is now also webhook-triggered) and possibly
  `architecture.mermaid` (InvoicePaidHandler now depends on PaymentSyncService) + `README.md` if the
  endpoint surface matters. Validate with the `mermaid-creation` skill.
- `Database/openapi.json` is **gitignored / context-only** (regenerated at runtime); do NOT
  hand-update or flag it — but the discount endpoints changed, so regenerate it at runtime if you
  need an accurate contract for a caller.

### 3.2 🔴 Re-run the migration (USER action) — for §2.6
The §2.6 view + RLS change lives in the schema files; the user must regenerate + run the migration
for it to take effect on the live DB. (Dev DB — the user said don't worry about migration history;
just re-run.) Until then the live DB still has the old single-condition view/RLS (harmless — the
data already satisfies both conditions).

### 3.3 🟡 §2.2 — Per-parent concurrency lock (#25) — THE BIG REMAINING ONE (user wants it LAST)
**The need:** while one op syncs a family, no other op (admin, bulk job, second tab, a preview, or
the §2.4 webhook) may run a conflicting sync on the **same paying-parent family**. Today there is
**zero guard**: two concurrent `update_payments_recurring` on one family both read, both call Stripe,
both write back last-write-wins (the sync is a multi-transaction cascade with Stripe HTTP in the
middle). On billing code this mis-bills / desyncs. **It is now load-bearing for the §2.4 webhook
settle and the §2.5 discount preview staging** (the `preview_remove`-races-a-real-sync gotcha in §4).
- **Use a Postgres advisory lock:** `pg_try_advisory_lock(hashtext(parent_member_id::text))` acquired
  at the start of the op, held across the whole DB+Stripe sequence, released in `finally`. Per-parent,
  NOT one global lock. `SELECT … FOR UPDATE` is insufficient (one txn; the sync spans many txns + I/O).
- Attach via a shared decorator / context-manager around the lifecycle callers + the sync entry
  points (incl. `preview_*`, `settle_once_discounts`, and the webhook).
- **Open Qs for the user (ASK before building):** advisory-lock (backend serialization) vs. a
  `member_locks` UI edit-session table (TTL/heartbeat, "Bob is editing → read-only") vs. both;
  fail-fast 409 ("member is being updated, try again") vs. block-with-timeout. The user leaned "fix it
  properly"; flavor unconfirmed.

### 3.4 Open decisions + smaller items
- **Rewards `GET /rewards/{reward_id}` is unwired** — `RewardsService.get_reward` exists but no route;
  7 `TestGetReward` tests (in `tests/integration/test_rewards_integration.py`) expect it and 405.
  **Pre-existing, UNRELATED to this refactor** (since the base commit). User said leave it: decide to
  wire `GET /{reward_id} → get_reward` or delete the TestGetReward class.

> **Moved/resolved (no longer session TODOs):** the **preview due-now vs recurring split (#19)** is a
> future feature, now in `FastApiBackend/PaymentRefactor.md` §6 (the roadmap). The
> **`gyms_stripe_connect_service` direct-Stripe call** is **accepted as-is** — Connect onboarding talks
> to Stripe directly on purpose; not a TODO.

---

## 4. Gotchas still live (don't get surprised)
- **🔴 `preview_remove` races a real sync (closed ONLY by §2.2).** Staging `preview_remove` on a real
  `applied` row (the §2.5 remove-preview): the preview read excludes it (good), but a **concurrent
  real sync ALSO excludes `preview_remove`, so it drops the membership's live Stripe line → mis-bill.**
  `preview_add` (add-preview) is safe (a real sync ignores it). Same risk for the §2.4 webhook settle
  racing a caller's sync. Cleanup is `finally`-bounded, not race-safe.
- **Stripe coupon shape:** a subscription-item Discount exposes its coupon at
  **`discount.source.coupon`** (a coupon-id string); `discount.coupon` is null; a bare `di_…` is an
  unexpanded Discount. The retrieve must expand `items.data.discounts`. (Bug #2.)
- **The filtered view + RLS now gate on stripe-id AND sync_status** (§2.6) — a row must have both a
  Stripe id and a non-pending/non-preview status to be client-visible. Deleted rows keep their
  Stripe id, so they stay visible (status view derives `cancelled`/`ended` from dates).
- **Enum binds in SQL use `CAST(:p AS type)`**, never `:p::type` (asyncpg/text() breaks).
- **Idempotency keys are suffixed** per Stripe sub-op (`:sub_create`/`:sub_update`/`:sub_cancel`;
  `:freeze`/`:unfreeze`). Pre-sync, `bulk`, the webhook settle, and previews mint fresh `uuid4()`.
- **The webhook settle + the discount preview staging use their own db_pool sessions** (separate
  transactions from the webhook's / the caller's) — intended, but a reason the §2.2 lock matters.

---

## 5. Cardinal rules (repeat)
1. **One approved piece at a time. Never a big sweep.** Propose → wait → write (engine/callers).
2. **Never run migrations or seeds** — the user does. Tell them when a schema/seed file changes.
3. **Don't `git push` without asking.** Commit locally; ask before pushing.
4. **Never reshape a test to pass against a broken path** — fix the engine/caller, or surface the bug
   (this session found Bug #1 + Bug #2 that way).
5. **Update the living docs** (the 4 skills + both `.mermaid` diagrams) in the SAME change that
   changes the engine. (§3.1 is the catch-up for this session.)
6. **Verify every change:** py_compile + ruff + DI build, and run the affected tests against the live
   DB + Stripe; the math is billing — trace a concrete dollar example when in doubt.
