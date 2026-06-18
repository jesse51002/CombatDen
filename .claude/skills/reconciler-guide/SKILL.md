---
name: reconciler-guide
description: >-
  The single source of truth for the CombatDen scheduled RECONCILER — the
  router-less `reconciler` domain in FastApiBackend/src/reconciler/ that runs the
  billing engine on a clock (twice daily, APScheduler in the app lifespan) so
  drift on IDLE members self-heals. Covers ReconcilerService (the thin
  orchestrator running the five step-services in order; the generic ResourceLock
  the orphan cleanup uses), the five modular step-services run in order —
  InvoiceFetchSweep (missed-webhook backfill that reuses the webhook handler
  record() seam), StaleTaskSweep (re-runs unfinished tracked tasks whose
  in-process run died — the tasks domain's crash recovery, moved here),
  OrphanCleanupSweep (lock-guarded delete of stranded not_added
  rows), PaymentPushSweep (CRM→Stripe converge via the existing bulk_payment_sync,
  whose sync now self-heals a gone subscription natively), SubscriptionOrphanSweep
  (the reverse direction — cancels live Stripe subs whose items map to no live
  membership row, item-id linkage + an age guard) — how a gone sub is
  cancelled inside the sync (PaymentSyncCancel, owned by sync-guide), the
  customer.subscription.deleted webhook as a thin bulk_payment_sync trigger, the
  synthetic per-attempt failed-charge key, and the conflict-resolution rule
  (config drift → CRM wins / push; lifecycle/dunning drift → Stripe wins / the
  sync cancels a gone sub, never re-bill). Load this whenever you touch the
  reconciler sweep, the scheduler, the subscription-deleted webhook, the invoice
  fetcher / the webhook handle→record seam, the synthetic failed-charge key, or
  ask how/when the reconciler runs. Trigger on "reconciler", "scheduled sweep",
  "twice daily", "APScheduler", "ResourceLock", "OrphanCleanupSweep",
  "PaymentPushSweep", "InvoiceFetchSweep", "StaleTaskSweep",
  "stale-task recovery", "SubscriptionOrphanSweep", "orphan subscription",
  "cancel unlinked sub", "customer.subscription.deleted",
  "record seam", "synthetic charge key", "self-heal a gone sub", "dunning",
  "skip-if-equal", or any change to src/reconciler/. The payment-sync ENGINE the
  push step calls — including the gone-sub cancel (PaymentSyncCancel) — lives in
  `sync-guide`; the webhook handlers it reuses live in `payments-guide`.
---

# Scheduled Reconciler — the on-a-clock billing safety net

> ⚠️ **Billing-adjacent infrastructure — human in the loop.** The reconciler
> drives how real members are billed (it pushes Stripe subscriptions, records
> charges, and triggers the sync that cancels memberships off a gone sub). It does
> **not** own the payment-sync engine (that's `sync-guide`) — it *drives* it — but
> it is edited under the same stricter rule: **propose → wait → write, one piece
> at a time.** A mistake here mis-cancels or mis-bills real customers.

This skill is the deep domain knowledge for the **`reconciler` domain**
(`FastApiBackend/src/reconciler/`). It owns the **orchestration / sweep
mechanics**. It does **not** own:

- **The payment-sync engine** (`update_payments_recurring`, `bulk_payment_sync`,
  the builder/discount math/writeback, **and the gone-sub cancel `PaymentSyncCancel`**)
  → `sync-guide`. The push sweep *calls* `bulk_payment_sync`; it does not
  redocument it.
- **The Stripe webhook handlers** (invoice paid/payment/failed/refund) and the
  Stripe primitives → `payments-guide`. The invoice fetcher *reuses* their
  `record()` methods; it does not redocument them.
- **The membership lifecycle / cancel path** → `memberships-guide`.

---

## 1. What it is — run the engine on a clock

The engine self-heals drift **only when a member is actively touched**. Drift on
an **idle** member persists until the next manual op. The reconciler is the
periodic sweep that runs the engine on a clock, independent of user activity,
closing that gap. It is **load-bearing**, not just a backstop, for two shipped
discount features on idle members (both owned by `discounts-guide`):

1. **Ongoing-discount `end_date` enforcement** — an ongoing discount drops off
   the line only the first time a sync runs on/after its cutoff; an idle member
   triggers no sync, so the push sweep is what runs it on schedule.
2. **`once`-consumption finalization** — the `invoice.paid` webhook settles a
   consumed `once` promptly; the sweep is the backstop for a **missed** webhook.

It is a **safety net**: simple, idempotent, no manual controls. It invents no
billing logic — every step reuses existing services.

---

## 2. The orchestrator + scheduler

- **Scheduler** — `reconciler_scheduler.build_scheduler(container)` builds an
  `AsyncIOScheduler` (UTC) with one cron job (`settings.reconciler_cron_hours`,
  default `[2, 14]` → twice daily), `max_instances=1` + `coalesce=True`. The app
  **lifespan** (`src/main.py`) starts it (gated by `settings.reconciler_enabled`)
  and `shutdown(wait=False)` on stop. The root test conftest sets
  `reconciler_enabled=False` so booting the app in a test never starts it.
- **Orchestrator** — `ReconcilerService.run() -> ReconcilerRunResult` runs the
  five steps in order and returns each one's `SweepResult`
  (`processed / changed / skipped / errors`).
- **No reconciler-wide lock.** Safety is the per-paying-family `PayingMemberLock`
  that **every payment op already holds** (and that the orphan cleanup checks
  before deleting, §3) — the reconciler never mutates a family's Stripe state
  except through `bulk_payment_sync`, which is itself family-locked + idempotent.
  So two concurrent sweeps (e.g. two app instances) are **safe**: at worst they
  repeat idempotent work; they cannot corrupt state. `max_instances=1` is only the
  in-process guard against an overlapping cron tick.
- **`ResourceLock`** (`src/shared/resource_lock.py`) is the generic, key-agnostic,
  **non-blocking** TTL accessor over the existing `resource_locks` table (reusing
  `acquire_resource_lock.sql` / `release_resource_lock.sql`): `acquire_once`,
  `release` (token-fenced), `try_lock` (context manager yielding the bool). The
  reconciler uses it for **one thing**: the orphan cleanup's non-blocking check of
  the per-family `PayingMemberLock` key (§3). `PayingMemberLock` stays on its own
  copy of the mechanics (the critical billing path); both write the same table
  with compatible keys, so a `try_lock` on a family key correctly contends with a
  blocking `PayingMemberLock.lock` on that family.

---

## 3. The five step-services — run order

Each step is its **own service**; the orchestrator is thin. The order is
deliberate:

1. **`InvoiceFetchSweep`** (§5) — refresh dates/charges first, so the
   date-derived "overdue" view is current before anything reads it.
2. **`StaleTaskSweep`** — re-run unfinished tracked tasks (`src/tasks/`) whose
   in-process run died, advancing their state + converging before the push.
3. **`OrphanCleanupSweep`** — remove stranded `not_added` rows.
4. **`PaymentPushSweep`** — final CRM→Stripe converge over the now-clean set;
   this is also what cancels a gone sub (§4).
5. **`SubscriptionOrphanSweep`** — the reverse cleanup: cancel live Stripe subs
   with no live DB link. Runs **last** so the push has re-linked any real sub
   (re-stamped its `stripe_item_id`) before we judge what's an orphan.

- **`StaleTaskSweep`** (`reconciler_stale_task_sweep.py`) — tracked-task crash
  recovery, **moved out of `src/tasks/` into the reconciler** (the tasks domain
  no longer has its own scheduler). Lists every unfinished task
  (`tasks_list_unfinished.sql`, pending/running) and calls
  `TasksExecutor.run_task(id)` on each; the executor's atomic claims decide what
  is actually runnable (a `pending` item, or a `running` claim older than
  `TASK_STALE_RUNNING_SECONDS` left by a dead process), so a still-live
  in-process run is never disturbed. A genuinely `failed` task (out of attempts)
  is no longer "unfinished" → not re-run here; the push step converges whatever
  it left. The recovery loop lives in the reconciler; the tasks engine only owns
  running ONE task.
- **`OrphanCleanupSweep`** — lists orphaned `not_added` rows
  (`stripe_item_id IS NULL`, from `reconciler_orphan_memberships.sql`). Per row:
  resolve the paying parent, **non-blocking** `ResourceLock.try_lock` on the
  family key `paying_member_lock:{parent}` → if free, delete (reusing the guarded
  `member_memberships_delete_pending.sql`) and count `changed`; if held, an op is
  in flight → `skipped`. The delete's own `stripe_item_id IS NULL` guard means a
  row confirmed in the gap is never removed. The reprice's in-flight successor
  is covered by the same lock check — the reprice holds the family lock across
  its DB phase + converge and **reverts the successor itself on failure**, so a
  lock-free pending successor only exists after a process crash: a genuine
  orphan, reaped like any other.
- **`PaymentPushSweep`** — lists the active billing members
  (`reconciler_active_billing_members.sql` → distinct paying parents with an
  active recurring membership, `member_id` only) and calls the existing
  `PaymentSyncService.bulk_payment_sync(ids)` (proration `none` → **billing
  none**, no charge). This is the "touch on a clock": it enforces ongoing-discount
  `end_date`, backstops a missed `once` settle, **and** — because the sync now
  self-heals a gone sub (§4) — cancels memberships whose Stripe sub is gone, with
  no separate status pass.
- **`SubscriptionOrphanSweep`** — the reverse of `OrphanCleanupSweep` (which deletes
  DB rows with no Stripe line): cancels live Stripe subscriptions whose items map to
  **no live membership row**. Per Connect account
  (`reconciler_gyms_with_connect.sql`, deduped) it lists non-cancelled subs directly
  off the Stripe client (mirroring `InvoiceFetchSweep` + its `_iter` pagination) and,
  for each, **skips** any younger than `settings.reconciler_orphan_min_age_seconds`
  (the age guard — without metadata we can't lock an unlinked sub to its family, so a
  sub a live op just created must age past any in-flight op) or whose items don't fit
  one page (can't enumerate all items → can't safely judge), then checks the sub's
  `si_…` item ids against `reconciler_linked_item_ids.sql`. That read hits the
  **unfiltered** base with `stripe_sync_status IN ('applied','migrating')` — a
  `deleted` row is **not** a live link (and the filtered view does **not** hide
  `deleted`). No live link → cancel the whole subscription via the payments
  `cancel_subscription` primitive (immediate, fresh idempotency key; idempotent — a
  no-op for an already-cancelled sub). Each cancel is isolated in its own `try` so
  one failure can't abort the sweep.

Cancelling a gone sub (a sub Stripe itself ended) is **not** a separate reconciler
step — it happens **inside the sync** (§4), so the push sweep handles it as part of
the converge. `SubscriptionOrphanSweep` is the **opposite** case: a sub Stripe still
holds but the CRM no longer links to (a reverted/deleted membership) — config drift
in the Stripe→CRM direction, so the CRM wins and the sub is cancelled.

---

## 4. How a gone subscription is cancelled — inside the sync

This mechanic is owned by **`sync-guide`** (`PaymentSyncCancel` +
`update_payments_recurring`); summarized here because it's *why* the reconciler has
no status step — the sync cancels a gone sub itself.

When the converge reads/updates the family's monthly sub and Stripe reports it
**gone** — `PaymentsResourceNotFoundError` with `resource_type == subscription`
(a `canceled` status or a not-found id, surfaced by the once-settle live read or
by `execute_sync`'s update/cancel) — the sync does **not** recreate it (that would
re-bill a member Stripe already let go). Instead it records the cancellation
(`PaymentSyncCancel`, **CRM-only, no Stripe call**): mark every live recurring
membership across the family cancelled (`cancel_date` + `stripe_sync_status='deleted'`)
and **null the parent's `stripe_sub_id_month`**, then **re-raises** (the requested
converge didn't happen — the family was cancelled instead). The gate matters: only
`resource_type == subscription` cancels; an item-level drift / missing price /
coupon re-raises untouched (a stale item id must never cancel a live family). It
runs on **preview too** (a gone sub is settled reality, like the once-settle that
already writes during preview).

**How callers see the re-raise:** `bulk_payment_sync` (the push sweep, and the
webhook below) catches it and **retries**; the retry finds the family already
cancelled → empty bucket → syncs to nothing → success. Mutation callers
(`start` / `update_price` / `update_discounts`) revert their pending write (via
`sync_or_revert`) and propagate it to their router → a clean HTTP error. `cancel()`
catches it → `_mark_deleted` (idempotent).

**Two things trigger it:**
- **The reconciler poll** (the push sweep) — `bulk_payment_sync` over idle billing
  families; any whose sub is gone gets cancelled.
- **The `customer.subscription.deleted` webhook** (the **prompt path**,
  `stripe_webhooks/service/customer_subscription_deleted_handler.py`) — reads
  `member_id` from the cancelled sub's `StripeSubscriptionMetadata` and calls
  `bulk_payment_sync([member_id])` (which locks the family, runs the sync, and
  swallows its own per-member failures). Without it, a dunning/out-of-band
  cancellation would only be caught on the next twice-daily sweep. On a real
  dead-sub event the sync cancels on the first attempt, then `bulk` retries once
  to converge to empty, so the webhook acks Stripe after ~one retry delay.

**Operational:** the Stripe Connect webhook endpoint must subscribe to
`customer.subscription.deleted` for the prompt path to fire (the sweep is the
backstop regardless).

---

## 5. The invoice fetcher + the record seam + the synthetic failed-charge key

**`InvoiceFetchSweep`** is a missed-webhook backstop. Per gym Connect account
(`reconciler_gyms_with_connect.sql`) it lists the last
`settings.reconciler_invoice_lookback_days` of invoices / payments / refunds (paginated)
and re-records each through the SAME webhook handler logic — but driven by listed
**objects** instead of events, so it **cannot** use the webhook event-log dedup.

**The handle→record seam.** Each of the 4 webhook handlers
(`invoice_paid`, `invoice_payment_paid`, `invoice_payment_failed`, `refund`) is
split: `handle(session, event, gym_id)` is a thin adapter that unwraps the event
envelope and calls `record(session, obj, gym_id, …)` carrying the body. The
dispatcher still calls `handle` (webhook behavior unchanged); the fetcher calls
`record` with listed objects. Routing: invoice `status='paid'` →
`invoice_paid.record` (bill + line items + `next_due_date`, which is what clears a
falsely-overdue member) then its succeeded `invoice_payments` →
`invoice_payment_paid.record`; `status='open'` with `attempt_count>0` →
`invoice_payment_failed.record`; refunds → `refund.record`. Each object is
recorded in **its own DB transaction** (`_run_record`) so one bad object can't
roll back the rest; `SubscriptionItemPendingError` / `InvoiceNotYetRecordedError`
are caught per object (the next sweep retries once the prerequisite row exists).

**Idempotency at the DB layer** (no event-log): invoice upsert on
`stripe_invoice_id`; succeeded-charge `stripe_charge_id` UNIQUE; refund
`stripe_refund_id` UNIQUE; and the **synthetic per-attempt failed-charge key**
`failed_attempt:<invoice>:<attempt_count>`, stored in `stripe_charge_id` and
shared by **both** the webhook failed handler and the fetcher, so a single
in-window failure records exactly once and a *new* attempt (Stripe increments
`attempt_count`) gets its own row. It never collides with a real `ch_…` id.

---

## 6. Conflict-resolution rule (load-bearing)

When a sync finds Stripe ≠ CRM, the winner depends on the kind of difference:

- **Config drift** (wrong items / quantities / discount / price) → **CRM wins**
  → push to Stripe (the CRM authored the config, nothing self-serves on Stripe's
  side).
- **Lifecycle / outcome drift** (Stripe `canceled` / `past_due` / `unpaid` from
  dunning) → **Stripe wins** → **never recreate or re-bill**. Blindly converging
  here would resurrect a delinquent member's sub and fight Stripe's dunning.
  - `canceled` / not-found → the sync **cancels** the family + nulls the sub id
    (§4).
  - `past_due` / `unpaid` → the sub is still **live** (Stripe is dunning it); the
    sync's update **succeeds** and just converges it — no cancel. "Overdue" is
    **date-derived** (`next_due_date < today`), not Stripe-derived, and the
    failed-charge row + fresh dates come from the invoice fetcher.

**How long `past_due` lasts before Stripe cancels.** Stripe runs its
**dunning/retry window** and then auto-cancels the delinquent sub (firing
`customer.subscription.deleted` → the cancel path above). **On the current
configuration that window is ~1 month**, so a member who never pays flips to
`canceled` roughly a month after the first failed renewal — only then does the
cancel-sync null the sub id, the membership read `cancelled`, and the
canceled-membership rules engage (`mark_paid_cash` rejects it; `list_invoices`
stops surfacing its now-stale invoice). The window is **day-based and a
per-connected-account Dashboard setting** (Settings → Billing → Revenue
recovery — Dashboard-only, **no API**), not a literal calendar month, so
changing it is a Stripe config change, never code.

---

## 7. Idempotency & safety properties

- **Whole sweep is idempotent + safe to re-run.** Every step reuses idempotent
  primitives (`bulk_payment_sync`, the gone-sub cancel, the DB-layer dedup above).
  A crashed sweep just re-runs next cycle.
- **`member_charge_insert.sql` uses a *targetless* `ON CONFLICT DO NOTHING` on
  purpose** — that insert is shared across payments (`stripe_charge_id` UNIQUE),
  refunds (`stripe_refund_id` UNIQUE), and the synthetic failed key. A targetless
  `DO NOTHING` skips on **any** of those unique constraints; pinning a single
  `ON CONFLICT (stripe_charge_id)` would make a duplicate **refund** event raise
  instead of dedupe. Do not "fix" it to a single target.
- **The subscription-deleted webhook runs the sync on its own DB pool**, not the
  dispatcher's `session` (`bulk_payment_sync` owns its pool + family lock). So the
  event-log insert and the sync's writes are **not one transaction**. This is
  eventually-correct: the sync is idempotent, and a crash rolls back the event-log
  → Stripe retries → the sync re-runs and converges.
- **Overdue is date-derived, never Stripe-derived.** `is_membership_overdue`
  (`members/service/members_status_mapping.py`) reads `next_due_date < today`. The
  reconciler never writes an "overdue" state — the fetcher keeps the dates fresh,
  which is what makes overdue correct.

---

## 8. What is deferred (not built)

The one deferred optimization (tracked in `PaymentRefactor.md` §1): a
**compare-desired-vs-actual, skip-if-equal** guard on the push sweep. Today
`execute_sync` issues a Stripe `update` for an in-sync sub every run — harmless
at `proration_behavior="none"` (no charge), but wasteful. This guard is purely a
write-reduction.

---

## Key files (where the reconciler actually lives)

- **Orchestrator:** `src/reconciler/service/reconciler/reconciler_service.py`
- **Sweeps:** `reconciler_invoice_fetch_sweep.py`,
  `reconciler_orphan_cleanup_sweep.py`, `reconciler_payment_push_sweep.py`,
  `reconciler_subscription_orphan_sweep.py` — same folder
- **Result models:** `reconciler_result.py`
- **Scheduler:** `src/reconciler/reconciler_scheduler.py` (+ lifespan in `src/main.py`)
- **SQL:** `src/reconciler/sql/` (`reconciler_orphan_memberships.sql`,
  `reconciler_active_billing_members.sql`, `reconciler_gyms_with_connect.sql`,
  `reconciler_linked_item_ids.sql` — the subscription-orphan linkage read)
- **Shared lock:** `src/shared/resource_lock.py`
- **Gone-sub cancel (in the sync, see `sync-guide`):**
  `src/sync/service/sync_cancel.py`
  (+ `memberships/sql/member_memberships_family_cancellable.sql`)
- **Prompt webhook:** `src/stripe_webhooks/service/customer_subscription_deleted_handler.py`
  (registered in `stripe_webhooks_service.py`)
- **The record seam:** `src/stripe_webhooks/service/{invoice_paid,invoice_payment_paid,invoice_payment_failed,refund}_handler.py`
- **Config:** `src/core/config.py` (`reconciler_enabled`, `reconciler_cron_hours`,
  `reconciler_invoice_lookback_days`, `reconciler_stripe_page_size`,
  `reconciler_orphan_min_age_seconds` — all `Settings` fields)
- **DI:** `src/core/dependencies.py` · **Tests:** `tests/reconciler/test_reconciler.py`
  (+ the gone-sub cancel in `tests/memberships/test_payment_sync_cancel.py`)

## Diagram

`FastApiBackend/reconciler.mermaid` is the step-by-step flow (scheduler →
invoice-fetch → stale-task recovery → orphan-cleanup → push, with the record
seam and the external actors). Keep it in sync with this skill (same `mermaid-creation` rules: TB,
sibling-only edges, fixed palette, `check_siblings.py` validation). The engine the
push step calls — including the gone-sub cancel — is in `payment_sync.mermaid` /
`sync-guide`; the whole-backend graph is `architecture.mermaid`.

---

## This skill is a living document

When the reconciler changes — a new/removed step, a different order, a changed
lock or schedule, the seam, the synthetic key, or the deferred skip-if-equal guard
landing — **update this skill and `reconciler.mermaid` in the same change**, and
the cross-references in `sync-guide` (the gone-sub cancel + §10) /
`PaymentRefactor.md` §1 if they drift. Never leave it stale: a stale rule produces
false "violation" findings in review and misleads the next contributor.
