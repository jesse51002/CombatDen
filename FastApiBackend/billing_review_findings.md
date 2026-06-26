# Billing Engine — Review Findings (backend)

**Scope:** FastApiBackend billing engine only — `src/{memberships, sync, payments, discounts, stripe_webhooks, tasks, plans}` + billing-critical `src/shared/*`, `src/reconciler/`, and the billing tables in `Database/supabase/schemas/`. No frontend/CRM.
**Date:** 2026-06-26
**Bar:** material only — real bugs, logic errors, bad-but-as-designed decisions, money/security risk, and meaningful test gaps. Pure style/lint nits excluded.

**How this was produced:** a one-pass adversarial sweep — **30 Opus hunters** (3 batches of 10, exhaustive "list it even if maybe") → code dedup + Sonnet semantic cluster → **1 Opus skeptic** (keep/drop) → **1 Opus referee** (final verdict). Funnel: **291 raw findings → 89 clusters → skeptic kept 19 → referee surfaced 20**. Every one of the 20 was **independently re-verified against the code** (4 adversarial validators + direct reading of the high-severity items) — all held up. Then, to guard against false *negatives*, the **69 rejected candidates were re-audited** by 6 adversarial "re-opener" agents (Opus): **62 dismissals stood, 7 were reopened** as real (folded in below, marked **⟲**). **Final total: 26.** IDs are the cluster ids from the run.

> This is a problems list for *existing* functionality — not a feature backlog. **NEEDS DECISION** = a product/runtime call, not a clear-cut bug. **⟲** = recovered from the rejection-audit (originally dismissed, then proven real).

---

## Summary

| ID | Sev | Type | Area | Title |
|------|--------|----------|---------------|-------|
| C-025 | **High** | bug | sync/one-time | Post-charge writeback failure deletes already-billed membership rows |
| C-035 | **High** | security | discounts/auth | Discount update is not gym-scoped — cross-gym billing-config tampering |
| C-079 | **High** | security | memberships/auth | `mark-paid-cash` / `refund` / `charge-card` / `freeze` let a member self-settle |
| C-058 | **High** | bug | plans | `set_price` deactivates the old price before the Stripe create — failure leaves the plan with no active price |
| C-026 | Med | bug | sync/one-time | One-time invoice line matching only reads the first 10-line page |
| C-059 | Med | bug | plans | `update_plan` discards the new `stripe_product_id` from the recreate branch |
| C-081 | Med | bug | memberships/refund | Cash refund has no lock — concurrent requests record an over-refund |
| C-083 | Med | bug | webhooks/reconciler | Cash charges have no idempotency key — reconciler re-record duplicates cash rows |
| C-085 | Med | bug | memberships/transition | Transition revert uses 3 separate transactions while the write is atomic |
| C-086 | Med | bug | memberships/start | One-time start is not idempotent on the DB insert — retries stack duplicate pass rows |
| C-066 | Med · **⟲** | bug | memberships/cancel | `_mark_deleted` loads a non-existent SQL path — cancelling an already-gone Stripe line crashes |
| C-012 | Med · **⟲** · **DEFERRED** | bug | sync/writeback | Failed `sub_id` writeback → duplicate subscription → double-bill + membership loss |
| C-064 | Med | bug | memberships/reprice | Reprice uses a fresh `uuid4` idempotency key per attempt (cancel uses a deterministic key) |
| C-078 | Med · **ACCEPTED** | design | memberships/cash | `mark_paid_cash` settles the whole consolidated invoice, forgiving co-billed family members |
| C-042 | Low | bug | payments/stripe | `update_customer` unconditionally detaches the old default — can strip the just-set card |
| C-048 | Low | bug | webhooks | `stripe_payment_intent_id` always NULL after the dahlia API change |
| C-049 | Low | bug | webhooks | Invoice discount audit undercounts when one shared coupon hits multiple lines |
| C-050 | Low | bug | webhooks | `next_due_date` can be taken from a proration line's `period.end` |
| C-053 | Low | bug | webhooks | PaymentIntent retrieve runs inside the open webhook DB transaction |
| C-082 | Low | bug | memberships/refund | Card refund crashes (500) on an unmodeled Stripe refund status |
| C-070 | Low · **⟲** | bug | memberships/freeze | Freeze trusts client `gym_id` → silent 0-row no-op |
| C-075 | Low · **⟲** | bug | memberships/lock | `LockBusyError` returns 500, not the documented 409 |
| C-088 | Low · **⟲** · **ACCEPTED** | design | memberships/start | Saved default card not reverted on a failed start (affects all the payer's memberships) |
| C-004 | Low · **⟲** | bug | sync/discounts | A discount that rounds to 0.00% is sent to Stripe as `pct_0` → sync crash (no floor) |
| C-009 | Low | bug | docs/skills | `sync-guide` SKILL.md documents a stale `resolve()` signature |
| C-089 | Low | test-gap | tests | Confirmed billing bugs lack regression tests |

**Counts:** 4 high · 10 medium · 12 low (= 26). **⟲** = 7 recovered from the rejection-audit (C-066, C-012, C-070, C-075, C-088, C-004, + the C-079 freeze extension). **Decisions (2026-06-26):** C-064 → fix (Stripe-confirmed); C-078 & C-088 → accepted by design; C-012 → deferred to `PaymentRefactor.md` §7.

---

## Fix status (2026-06-26)

**22 fixed** (each ships a unit regression test; 84 fix/regression tests pass, app imports, ruff clean). **3 require a DB migration** (schema edited, migration not generated). 1 deferred, 2 accepted, 1 addressed-via-tests.

| ID | Status | Notes |
|------|--------|-------|
| C-025 | ✅ fixed | one-time post-charge writeback now best-effort — never deletes a billed row |
| C-026 | ✅ fixed | paginate all invoice lines (no 10-line truncation) |
| C-035 | ✅ fixed | discount lookup gym-scoped (`AND gym_id = :gym_id`) → 404 cross-gym |
| C-042 | ✅ fixed | skip detach when new PM == current default |
| C-048 | ✅ fixed | read `payment_intent` from dahlia `parent…` path + fallback |
| C-049 | ✅ fixed · **⚠ MIGRATION** | discount-audit uniqueness gains `line_item_id` |
| C-050 | ✅ fixed | `next_due_date` skips proration lines / uses period end correctly |
| C-053 | ✅ fixed | Stripe PI retrieve moved out of the open webhook txn |
| C-058 | ✅ fixed | Stripe price created/verified **before** the DB deactivate, one txn *(reviewer note: holds a pooled conn across the Stripe call)* |
| C-059 | ✅ fixed | recreated `stripe_product_id` now persisted |
| C-064 | ✅ fixed | stable reprice idempotency key (derived once, reused on retry) |
| C-066 | ✅ fixed | `_mark_deleted` points at the real `src/sync/sql/…` path |
| C-070 | ✅ fixed *(interim)* | rowcount guard → loud failure on gym_id mismatch *(deeper "derive gym_id server-side" remedy needs `memberships_service.py`, not done)* |
| C-075 | ✅ fixed | `LockBusyError` → **409** via global handler |
| C-079 | ✅ fixed | staff-only `verify_gym_employee_for_member` on freeze/unfreeze/mark-paid-cash/charge-card/refund |
| C-081 | ✅ fixed | `SELECT … FOR UPDATE` re-check before recording a refund (+ existing tests updated) |
| C-082 | ✅ fixed | unmodeled Stripe refund status → recorded `pending`, no 500 |
| C-083 | ✅ fixed · **⚠ MIGRATION** | partial unique index dedups cash charges *(migration must dedupe existing rows first)* |
| C-085 | ✅ fixed | transition revert wrapped in a single transaction |
| C-086 | ✅ fixed · **⚠ MIGRATION** | `idempotency_key` column + `ON CONFLICT` — a retried one-time start now fails loudly instead of double-granting *(a graceful 409 replay is a flagged follow-up; today it 500s)* |
| C-004 | ✅ fixed | floor: a sub-0.01% discount is dropped, never sent to Stripe as `pct_0` |
| C-009 | ✅ fixed | `sync-guide` SKILL.md → 2-arg `resolve()` (3 mentions) |
| C-089 | ✅ addressed | each confirmed fix now has a regression test |
| C-012 | ⏸ deferred | → `PaymentRefactor.md` §7 (durable failed-writes outbox + cheap co-write mitigation) |
| C-078 | ☑ accepted | by design — consolidated-invoice settle; CRM warning is a separate frontend item |
| C-088 | ☑ accepted | by design — card-first ordering is intentional |

**Migration authored — `Database/supabase/migrations/20260626130000_billing_review_schema_fixes.sql`** (one hand-written file, 3 sections: C-049 widened unique + `line_item_id`, C-083 cash dedup-then-partial-index, C-086 `idempotency_key` column + partial index). `immutable_columns.py` and `schema_db_diagram.io` synced in the same change. Per `Database/CLAUDE.md` it is **NOT applied** — you reset the DB and apply it yourself; that's also what unblocks the integration tests.

**Cross-file follow-ups still open:** `memberships-guide` §6 should mention the one-time-start dedup (living-doc sync); C-070 deeper "derive gym_id server-side" remedy; C-086 graceful 409 replay (today a retried one-time start 500s).

---

## High

### C-025 · bug · One-time post-charge writeback failure deletes already-billed membership rows
**Location:** `src/sync/service/sync_one_time.py:106` (`charge_one_time`: `_execute` then unguarded `_writeback`) → `src/memberships/service/memberships_start.py:278-282` (`_charge_one_time_group` → `_fail_group(cleanup=True)`)
**What's wrong:** `charge_one_time` charges Stripe in `_execute`, then runs `_writeback` with **no guard** (line 106). Unlike the recurring `PaymentSyncWriteback` (best-effort, never raises), this one-time `_writeback` *can* raise — its DB writes can fail, and the `>10-line` case (C-026) raises here too. `_charge_one_time_group` catches **any** exception and calls `_fail_group(..., cleanup=True)` → `_cleanup_states` → `_delete_pending`, **deleting the rows whose invoice was already charged.** The "keep unverified" safe path only runs if `charge_one_time` *returns*, which a raising writeback bypasses.
**Why it matters:** Violates the documented invariant "a successful charge is NEVER un-billed." The member is charged, the rows vanish, no refund fires — silent revenue with no DB record and no membership.
**Fix:** Make the one-time post-charge writeback best-effort like the recurring path (or mark rows failed-but-kept and alert for reconciliation). Never route a post-charge failure into the delete branch.
**Validation:** Confirmed by direct reading + 2 independent validators (the rejection-audit re-confirmed it from a third angle). The `zip(strict=True)` is *not* the primary trigger (lengths match by construction); the realistic triggers are a DB write error in `_writeback` and the C-026 raise. Compounds with **C-026**.

### C-035 · security · Discount update is not gym-scoped (cross-gym tampering)
**Location:** `src/discounts/discounts_router.py:167` (gate) + `src/discounts/service/discounts_base.py:37-52` (`_get_discount`) + `src/discounts/sql/discounts_get_by_id.sql:21-22` + `discounts_update.sql:8`
**What's wrong:** The router authorizes with `verify_gym_employee(request.gym_id)` — the **requester's own** gym — but the target is identified solely by `request.discount_id`. `discounts_get_by_id.sql` filters on `discount_id` with **no `gym_id` predicate**, `_get_discount` binds only `{discount_id}`, the identity UPDATE is likewise gym-free, and `_new_version` writes under `existing["gym_id"]` (the victim's). Queries run as service-role, so RLS does not backstop. An employee of gym A can send `gym_id=A` (passes the check) + a gym-B `discount_id` and rename/re-version gym B's discount.
**Why it matters:** Cross-tenant tampering on billing config — a malicious/buggy operator can change what another gym's members are billed. (Practical exploit needs the victim's discount UUID, which isn't enumerable, but the authorization gap is real.)
**Fix:** Scope the lookup to the requester's gym — `WHERE gym_id = :gym_id` in `discounts_get_by_id.sql` (pass `request.gym_id`), 404 when the discount isn't theirs, before any write.
**Validation:** Confirmed by direct reading + adversarial validator (and re-confirmed during the rejection-audit's auth pass).

### C-079 · security · `mark-paid-cash` / `refund` / `charge-card` / `freeze` let a member self-settle
**Location:** `src/memberships/memberships_router.py:1155` (mark-paid-cash), `:1232` (charge-card), `:1296` (refund), `:246` (freeze) + `src/shared/auth.py:168` (`verify_can_view_member`)
**What's wrong:** These money/billing endpoints are gated **only** by `verify_can_view_member`, which returns success when `member.user_id == auth_user_id` — i.e. the member themselves (auth.py:168). So a member with a valid token can: mark their own invoice paid-by-cash (free service), record a cash refund on their own charges, invoke charge-card, or **freeze their own membership to $0** (the rejection-audit added freeze — it rides the sync as a synthetic 100%-off). A stricter helper, `verify_gym_employee_for_member` (auth.py:193-229), already exists and explicitly excludes self-access "for staff-managed billing writes" — but it isn't used on these endpoints.
**Why it matters:** A member can waive their own payment obligation, self-refund, or zero out their bill — an unguarded revenue-loss / financial-control gap across four endpoints.
**Fix:** Gate mark-paid-cash, refund, charge-card, and freeze/unfreeze with `verify_gym_employee_for_member` (staff-only). Reserve `verify_can_view_member` for read/self-view endpoints.
**Validation:** Confirmed by direct reading + adversarial validator; the freeze endpoint was added during the rejection-audit and confirmed by direct reading (router:246). See also **C-070** (same freeze endpoint also trusts a client `gym_id`).

### C-058 · bug · `set_price` deactivates the old price before the Stripe create — failure leaves the plan with no active price
**Location:** `src/plans/service/plans_price.py:86-136`
**What's wrong:** Step 1 (86-102) flips the old price `is_active=false` + inserts the new pending price, and **commits at line 102** — before the Stripe `create_price` in Step 2 (111). On a Stripe failure the except (127) deletes only the **new** row; the old price's deactivation is already committed → zero active DB prices → new signups fail ("no active price") until manual intervention. (The "keep the old ACTIVE" comment at 158-163 is about not archiving the *Stripe* price.)
**Why it matters:** A transient Stripe error during a routine price change silently takes the plan offline for new subscriptions.
**Fix:** Create and verify the new Stripe price **first**, then do deactivate-old + insert-new + set-stripe-id in one transaction.
**Validation:** Confirmed by direct reading + adversarial validator.

---

## Medium

### C-026 · bug · One-time invoice line matching only reads the first 10-line page
**Location:** `src/payments/service/payments_stripe_payment_service.py:283` (`_order_lines` iterates `invoice.lines.data`)
**What's wrong:** `_order_lines` builds its line-by-item map from the embedded `invoice.lines.data`, whose Stripe default page size is **10**. A one-time invoice with >10 membership lines (large family / class-pack order) has items beyond page 1 with no matching line, so `_order_lines` raises — **after** the invoice is charged, feeding the C-025 deletion path.
**Why it matters:** Larger family/pack purchases crash post-charge, and via C-025 the billed rows are then deleted.
**Fix:** Match against the auto-paginated line list (`auto_paging_iter` / `has_more`, or `list_invoice_line_items`) before building the map.
**Validation:** Confirmed by adversarial validator. Compounds with **C-025**.

### C-059 · bug · `update_plan` discards the new `stripe_product_id` from the recreate branch
**Location:** `src/plans/service/plans_update.py:91` (call) + `:202` (recreate returns new id)
**What's wrong:** When the Stripe product is missing, `_update_or_recreate_product` creates a new one and returns its id (line 202). `update_plan` assigns it locally but the CRM UPDATE persists only user-provided `changes` columns — `stripe_product_id` is never written back. The DB keeps pointing at the dead product; the new one is orphaned, and later `set_price` reads the dead id.
**Fix:** When the recreate branch returns a new id, include `stripe_product_id` in the same UPDATE.
**Validation:** Confirmed by adversarial validator.

### C-081 · bug · Cash refund has no lock — concurrent requests record an over-refund
**Location:** `src/memberships/service/memberships_refund.py:104-117` + `:153-164`; `member_refund_insert.sql` / `member_charges.sql:35`
**What's wrong:** `refund_charge` reads `already_refunded` then inserts the negative row with **no row lock**. Card refunds are capped by Stripe, but a **cash** refund makes no Stripe call and writes `stripe_refund_id = NULL`, so the UNIQUE provides no guard (NULLs unconstrained). Two concurrent cash-refund requests both read the same balance and both insert full-refund rows.
**Why it matters:** The books record more cash refunded than was charged, with no external backstop.
**Fix:** `SELECT FOR UPDATE` the parent charge and re-check the remaining balance under the lock before inserting.
**Validation:** Confirmed by adversarial validator.

### C-083 · bug · Cash charges have no idempotency key — reconciler re-record duplicates cash rows
**Location:** `Database/supabase/schemas/member_charges.sql:34-35` + `src/stripe_webhooks/service/invoice_payment_paid_handler.py:171` + `src/reconciler/.../reconciler_invoice_fetch_sweep.py:51`
**What's wrong:** Cash payments store `stripe_charge_id = NULL`, and the only succeeded-payment idempotency is the `stripe_charge_id` UNIQUE — which doesn't constrain NULLs (`ON CONFLICT DO NOTHING` never fires). The twice-daily `InvoiceFetchSweep` re-fetches every invoice in its lookback window and re-inserts the cash charge with `stripe_charge_id=None` → a **new** cash row each run.
**Why it matters:** Cash receipts double-/triple-counted in revenue reporting, proportional to lookback × sweep frequency.
**Fix:** Add a dedup key for cash charges — a synthetic placeholder id, or a partial unique index keyed on `(invoice_id, payer, period)` where `stripe_charge_id IS NULL`.
**Validation:** Originally needs-human; **upgraded to confirmed** after the validator traced the full reconciler re-record path.

### C-085 · bug · Transition revert uses 3 separate transactions while the write is atomic
**Location:** `src/memberships/service/memberships_transition_base.py:163-176` (used by reprice + cross-plan upgrade)
**What's wrong:** `_write_db_phase` commits in one transaction, but `_revert_db_phase` runs **three independent** ones: delete-copied-discounts+commit, `_delete_pending` in its own session, then uncancel-old+commit. A crash between them leaves a half-reverted membership (successor deleted but old row still cancelled → membership lost; or a stranded `not_added` successor a sync could bill). The "already-applied" guard doesn't cover a crash mid-revert.
**Why it matters:** Error recovery can produce a state worse than the original failure. The forward path is atomic; the revert is not.
**Fix:** Wrap the three revert writes in one transaction, matching `_write_db_phase`.
**Validation:** Confirmed by adversarial validator.

### C-086 · bug · One-time start is not idempotent on the DB insert — retries stack duplicate pass rows
**Location:** `src/memberships/service/memberships_start.py:194-240` (`_insert_all`); one-time/trial stacking allowed (the existing-row guard scopes to recurring only)
**What's wrong:** The start idempotency key (uuid5) keys only the Stripe charges. `_insert_all` inserts pending rows with no existing-row guard, and one-time/trial rows are intentionally allowed to stack. On a client retry after a lost response: the charge dedups to the original invoice, but the DB carries **duplicate** one-time rows, and `_writeback` stamps the new rows `applied` against the same Stripe lines → 2N applied rows for one payment.
**Why it matters:** Members get double the passes/credits for a single charge; the orphan sweep can't cleanly resolve duplicate same-key rows.
**Fix:** Make the one-time DB insert idempotent — check existing rows for the key / `(member, plan, charge)` before inserting, or `ON CONFLICT DO NOTHING`.
**Validation:** Confirmed by adversarial validator (full duplicate-stamp trace).

### C-066 · bug · **⟲** · `_mark_deleted` loads a non-existent SQL path — cancelling an already-gone Stripe line crashes
**Location:** `src/memberships/service/memberships_cancel.py:516-523` (`_mark_deleted`), reached from `:195-205` (`_converge_cancellations._sync`)
**What's wrong:** `_mark_deleted` loads `SQL_DIR / "payment_sync" / "mark_membership_deleted.sql"`, where `SQL_DIR = src/memberships/sql` — resolving to `src/memberships/sql/payment_sync/mark_membership_deleted.sql`, which **does not exist** (the only such file is `src/sync/sql/mark_membership_deleted.sql`). `load_sql` → `read_text()` → **`FileNotFoundError`**. The branch is reached when `update_payments_recurring` raises `PaymentsResourceNotFoundError` (Stripe line/sub already gone — out-of-band Stripe cancel, dunning, prior partial sync): the handler loops `_mark_deleted(item_id)` to stamp the rows deleted so the verify passes. Instead it throws, `sync_or_revert` reverts (uncancels), and the cancel fails with a **500**.
**Why it matters:** A membership whose Stripe line is already gone **cannot be cancelled** through the normal path — a real operational scenario, and the exact case this branch exists to handle.
**Fix:** Point the path at the existing `src/sync/sql/mark_membership_deleted.sql` (or create the missing file); add a regression test for the line-already-gone cancel branch.
**Validation:** **⟲ Recovered from the rejection-audit** — originally dismissed because the referee checked the *other* `_mark_deleted` (`sync_cancel.py`, which is fine). **Confirmed by direct reading + `ls`**: `src/memberships/sql/payment_sync/` does not exist. Zero test coverage.

### C-012 · bug · **⟲** · **NEEDS DECISION** · Failed `sub_id` writeback → duplicate subscription → double-bill + membership loss
**Location:** `src/sync/service/sync_writeback.py:91-94` (best-effort `update_profile_sub_id`, no caller verify) + `sync_stripe.py:71-90` (create branches only on `bucket.existing_sub_id`) + `sync_service.py:270` (bulk uses a fresh `uuid4`)
**What's wrong:** Of all the best-effort writeback steps, the payer `sub_id` write is the **only one with no caller verify-or-revert backstop** (the contract verifies only the per-membership `stripe_sync_status` stamp). If `update_profile_sub_id` is swallowed *after* the row stamps succeed, `payer.sub_id` stays NULL; the next converge (`PaymentPushSweep`, which uses a fresh `uuid4` so create is **not** deduped, and has **zero tests**) reads NULL → **creates a second subscription**. The immutable `stripe_item_id` trigger then blocks re-stamping the rows, so the *tracked* sub links to nothing → `SubscriptionOrphanSweep` reaps it → a later push-sweep hits the now-cancelled sub → `_handle_lost_subscription` → `cancel_dead_subscription` **cancels the paying member's memberships**, while the original sub keeps billing.
**Why it matters / NEEDS DECISION:** A transient double-bill window plus eventual membership loss, all resting on the untested reconciler. The triggering partial-failure (sub_id write fails while row stamps land) is narrow, so the fix is a judgment call: a pre-create existence/idempotency guard, persisting `sub_id` atomically with the item stamps, or making the orphan sweep prefer the *tracked* sub.
**Validation:** **⟲ Recovered from the rejection-audit.** Originally dismissed as "self-heals at next converge" — which is **false** for the sub_id (NULL → create, not restore). Mechanism confirmed against the writeback/create/sweep code.
**Decision (2026-06-26):** **Deferred** — out of MVP scope. The durable failed-writes outbox + the cheap co-write mitigation are written up in `PaymentRefactor.md` §7. No code change this round.

### C-064 · bug · Reprice uses a fresh `uuid4` idempotency key per attempt
**Location:** `src/memberships/service/memberships_reprice.py:120-121` vs `memberships_cancel.py:137`
**What's wrong:** `reprice` passes `idempotency_key=uuid4()` (generated fresh inside the `sync_fn` lambda, so every retry re-keys), whereas `cancel` derives a deterministic `uuid5(key, payer)`. On a verify-failed-but-Stripe-succeeded path, the DB reverts and a task retry re-runs reprice with a new uuid4.
**Why it matters / NEEDS DECISION:** The key inconsistency is a real defensive gap worth closing regardless. Whether it actually **double-charges** can't be confirmed from code alone — after the revert, the retry re-derives desired state from the DB and Stripe likely won't re-prorate an item already at the target price. **Action:** apply the deterministic key (`member_membership_id + old_price_id + new_price_id`); have a human confirm the Stripe converge on the retry path.
**Validation:** Inconsistency confirmed; double-charge is a runtime/Stripe question.
**Decision (2026-06-26):** **Fix** — Stripe's own guidance confirms reusing one stable idempotency key across retries; regenerating per attempt is the documented anti-pattern. Included in the fix round.

### C-078 · design · **ACCEPTED (by design)** · `mark_paid_cash` settles the whole consolidated invoice
**Location:** `src/memberships/service/memberships_mark_paid_cash.py:96-112` + `src/payments/service/payments_stripe_payment_service.py:420`
**What's wrong:** A payer's family bills on one consolidated subscription → one open invoice. `mark_paid_cash` pays that invoice out-of-band by subscription, not by item, so recording one membership's cash payment settles **every** line — all co-billed memberships marked paid as if cash were received for all.
**Why it matters / NEEDS DECISION:** An operator settling one member's cash can unintentionally forgive the whole family's invoice (real revenue loss). At the engine level this is inherent to consolidated invoicing (Stripe offers no per-line out-of-band settle) — a **product/UX decision**. **Options:** warn in the CRM, and/or track cash at the membership-row level so only fully-cash invoices settle out-of-band.
**Validation:** Mechanism confirmed by adversarial validator (referee overruled the skeptic's drop).
**Decision (2026-06-26):** **Accepted by design** — inherent to consolidated invoicing (Stripe has no per-line out-of-band settle). No backend change; a CRM warning is a separate frontend item.

---

## Low

### C-042 · bug · `update_customer` unconditionally detaches the old default — can strip the just-set card
**Location:** `src/payments/service/payments_stripe_members_service.py:164-168`
**What's wrong:** `update_customer` attaches the new PM, sets it default, then detaches `old_pm_id` guarded only by truthiness — no `old_pm_id != request.payment_method_id` check. If a caller passes the current default as the "new" PM, the detach removes the card just set as default, leaving none. Narrow trigger (the normal swap always uses a fresh token).
**Fix:** Skip the detach when `old_pm_id == request.payment_method_id` (ideally also on shared fingerprint).
**Validation:** Confirmed by adversarial validator.

### C-048 · bug · `stripe_payment_intent_id` always NULL after the dahlia API change
**Location:** `src/stripe_webhooks/service/invoice_paid_handler.py:236`
**What's wrong:** `_upsert_invoice` stores `stripe_payment_intent_id = invoice.get("payment_intent")`, but dahlia removed `invoice.payment_intent`, so the column is always NULL for subscription invoices. (Refunds key off the charge id and still work; the column just silently always-nulls.)
**Fix:** Read from `invoice.parent.payment_intent_details.payment_intent` (with a pre-dahlia fallback) or drop the column; add the live-Stripe shape guard.
**Validation:** Confirmed by adversarial validator. Dahlia field-shape class — see also C-049/C-050.

### C-049 · bug · Invoice discount audit undercounts when one shared coupon hits multiple lines
**Location:** `src/stripe_webhooks/service/invoice_paid_handler.py:395-437`; `member_invoice_applied_discounts.sql:24` (`UNIQUE(invoice_id, stripe_coupon_id)`)
**What's wrong:** Coupons are shared by value, so a family invoice where two members carry the same value produces two `di_` entries mapping to one coupon id; the second insert conflicts and is dropped, recording one member's discount instead of the sum. **Reporting only — no money mischarged.**
**Fix:** Add the line item id to the uniqueness key.
**Validation:** Confirmed by adversarial validator.

### C-050 · bug · `next_due_date` can be taken from a proration line's `period.end`
**Location:** `src/stripe_webhooks/service/invoice_paid_handler.py:366-382`
**What's wrong:** `next_due_date` is derived from each line's `period.end` with no proration-line exclusion. On a mid-cycle upgrade invoice carrying both a proration line (`period.end` = change date) and a recurring line, the stored date can land on the near/past proration date. Self-heals on the next invoice.
**Fix:** Prefer the subscription's `current_period_end`; skip proration lines.
**Validation:** Confirmed by adversarial validator.

### C-053 · bug · PaymentIntent retrieve runs inside the open webhook DB transaction
**Location:** `src/stripe_webhooks/service/invoice_payment_paid_handler.py:179` (`_resolve_charge`), within the `session.begin()` at `stripe_webhooks_service.py:113`
**What's wrong:** `_resolve_charge` does a live Stripe `payment_intents.retrieve` while the webhook DB transaction is open (its own docstring acknowledges it). A Stripe latency spike holds a pooled DB connection; under concurrent load this adds pool pressure.
**Fix:** Collect Stripe data before opening the DB transaction; scope it to DB writes only.
**Validation:** Confirmed by adversarial validator.

### C-082 · bug · Card refund crashes (500) on an unmodeled Stripe refund status
**Location:** `src/memberships/service/memberships_refund.py:150` (`ChargeStatus(refund.status)`)
**What's wrong:** `_refund_card` builds the response with `ChargeStatus(refund.status)` unconditionally. `ChargeStatus` models only `pending/succeeded/failed`; a status outside that set (`requires_action`, `canceled`) raises `ValueError` → 500, and no DB row is written for a refund Stripe may already have processed (the `refund.*` webhook is the only backstop).
**Fix:** Map unknown statuses to a default branch recording the refund as `pending_review` instead of raising.
**Validation:** Confirmed by adversarial validator.

### C-070 · bug · **⟲** · Freeze trusts client `gym_id` → silent 0-row no-op
**Location:** `src/memberships/memberships_router.py:246-253` + `member_memberships_freeze_profile.sql` + `memberships_freeze.py` (no rowcount check)
**What's wrong:** The freeze handler validates only `request.member_id` (`verify_can_view_member`, which reads the gym from the DB and never checks `request.gym_id`), then passes the **client-supplied** `request.gym_id` into `freeze(...)`. The freeze SQL keys `WHERE member_id = :member_id AND gym_id = :gym_id`, `_crm_freeze_profile` doesn't check rowcount, and the payer lookup is also gym-filtered. So a freeze/unfreeze whose `gym_id` doesn't match the member's real gym **silently updates 0 rows, converges nothing, and returns 204 success** — nothing frozen.
**Why it matters:** Low in practice (the trusted CRM sends the real gym_id), but a latent footgun — the dismissal assumed the gym_id was validated; it isn't.
**Fix:** Derive `gym_id` from the member row (don't trust the client field) and/or assert `rowcount == 1` on the freeze write.
**Validation:** **⟲ Recovered from the rejection-audit**; premise confirmed by direct reading. Same endpoint as the **C-079** self-freeze gap.

### C-075 · bug · **⟲** · `LockBusyError` returns 500, not the documented 409
**Location:** `src/shared/paying_member_lock.py:38` + `src/memberships/memberships_router.py` (exception handlers) + `src/core/config.py:101` (stale comment)
**What's wrong:** `LockBusyError` (a plain `Exception`) isn't caught by any endpoint handler or an app-wide handler, so a busy per-payer lock surfaces as a generic **500** — but `config.py:101` documents the contract as `LockBusyError -> 409`. (The original dismissal — "the client still gets a retryable 5xx" — is itself wrong: a 500 is not a retry signal; 409/429/503 are.)
**Why it matters:** Low (API-contract/UX, not money), but a concurrent op that should say "busy, retry" looks like a crash; plus a stale comment that will read as a false violation later.
**Fix:** Map `LockBusyError` to 409 (per the documented contract); keep the comment in sync.
**Validation:** **⟲ Recovered from the rejection-audit**; behavior + stale comment confirmed.

### C-088 · design · **⟲** · **ACCEPTED (by design)** · Saved default card not reverted on a failed start
**Location:** `src/memberships/service/memberships_start.py:153-157` (`_set_default_card` runs first, never reverted)
**What's wrong:** `start()` promotes the entered card to the payer's saved default **first**; if a later phase (`_pre_sync_payments`, `_insert_all`, the charge) fails, that change isn't rolled back. For a payer funding **multiple** memberships (a parent paying for several kids), a failed start silently changes the card that bills *all* of them at the next renewal.
**Why it matters / NEEDS DECISION:** Defensible for a single membership (the user intended that card), but the multi-membership cross-effect is a real surprise — a product/UX call. (The "old card detached" half is covered by **C-042**.)
**Validation:** **⟲ Recovered from the rejection-audit**; the dismissal was incomplete (missed the multi-membership payer).
**Decision (2026-06-26):** **Accepted by design** — the card-first ordering is intentional (a card failure aborts the start cleanly rather than billing a succeeded membership on the wrong card); the multi-membership residual is accepted as the lesser evil.

### C-004 · bug · **⟲** · A discount that rounds to 0.00% is sent to Stripe as `pct_0` → sync crash
**Location:** `src/payments/service/payments_stripe_discount_service.py:137` (+ `:148-154`, `:192`); `sync_discounts.py:261` (no floor)
**What's wrong:** The `> 0` emit guards and the `gt=0` schema bound only block a *literal* zero. A tiny positive `line_percent` (e.g. a sub-0.015% admin discount, or one averaged across ≥2 members) passes them, then `_create_coupon` sends `percent_off = round(value, 2) = 0.0` to Stripe under id `pct_0`. Stripe rejects a 0% coupon → `InvalidRequestError` → the un-guarded retrieve of the nonexistent `pct_0` re-raises → the sync crashes. No floor exists before create.
**Why it matters:** Low — realistic discounts are ≥1% so it's practically unreachable, and it fails loud rather than mis-billing. But the original dismissal ("a zero value never reaches Stripe") is factually wrong.
**Fix:** Floor at create — skip/clamp when `round(line_percent, 2) < 0.01`.
**Validation:** **⟲ Recovered from the rejection-audit**; the no-floor gap confirmed against the code.

### C-009 · bug · `sync-guide` SKILL.md documents a stale `resolve()` signature
**Location:** `FastApiBackend/.claude/skills/sync-guide/SKILL.md:440-441` and `:457` (stale 3-arg `resolve(groups, account, today)`) vs live 2-arg `resolve(groups, stripe_account_id)` (`sync_discounts.py:75`, call site `sync_one_time.py:196`)
**What's wrong:** The `today` parameter was removed when date filtering moved into the SQL read path, but two SKILL.md sections still show the old 3-arg form (others were updated). Per repo rules, a stale skill produces false review violations and misleads contributors.
**Fix:** Update the two stale `resolve()` references to drop `today`; re-check other documented call sites in the same edit.
**Validation:** Confirmed by adversarial validator (exact stale lines identified).

### C-089 · test-gap · Confirmed billing bugs lack regression tests
**Location:** `FastApiBackend/tests/`
**What's wrong:** The bugs confirmed here have no regression guards. Spot-checked: C-025 (`test_writeback_resilience.py` covers the *recurring* writeback, not the one-time delete-after-charge path), C-035 (CRUD tests stay within one gym), C-058 (set_price happy-path only), C-059 (recreate branch untested), C-079 (`test_mark_paid_cash_no_auth` covers the 401, not the member-self-grant bypass), C-081 (over-refund *amount* validation only, not the concurrent race), C-085/C-086 (untested), C-048 (dahlia readers tested, not that the column is populated). The reopened C-066 (cancel of an already-gone line) and C-012 (duplicate-sub) are likewise untested.
**Why it matters:** Once fixed, these can silently regress; several touch real money. **Not** a claim of zero coverage in the surrounding areas — the suite is otherwise strong and clean of bug-workarounds; the gap is specific to these failure modes.
**Fix:** Add targeted integration tests scoped to the confirmed findings, using the shared Stripe test-mode + local Supabase fixtures.
**Validation:** Confirmed by adversarial validator (per-bug precision).

---

## Investigated & dismissed (audited — do not re-litigate)

The funnel evaluated **89 candidate clusters**; 69 were rejected as non-material. To guard against false negatives, all 69 were **re-audited** by 6 adversarial re-openers reading the code — **62 dismissals held, 7 were reopened** (now in the findings above, marked ⟲). The 62 that stood cluster into well-grounded categories:

- **Intended by design / documented** — best-effort `sync_writeback.write()` never raising (caller verifies the load-bearing status and reverts); freeze-as-100%-off; one-time stacking allowed; discounts item-scoped (no "payer's discount"); recurring-always-monthly DB constraint (validated trigger); lost-sub cancel cascading a payer's whole consolidated subscription ("Stripe wins"); subject-keyed freeze.
- **Mechanism can't actually trigger** — zero-value coupon (guarded by `>0`, *except* the rounds-to-0.00% edge, which became **C-004**); divergent `stripe_item_id` for one price slot (consolidated by construction); `zip(strict=True)` mismatch (lengths equal by construction); reprice double-proration on retry (`_validate_reprice` rejects the re-read cancelled row — verified across orderings).
- **Self-heals via the reconciler / sweeps** — *these were the audit's priority, since `PaymentPushSweep`/`StaleTaskSweep` have no tests.* The survivors were re-verified against the **actual sweep code** and hold: webhook retry lost on restart (C-055, re-recorded by `InvoiceFetchSweep`), `subscription.deleted` prompt failure (C-056, the failed case stays `active` so it stays swept), non-atomic cancel writes (C-065, safe because `get_active_recurring.sql` filters `cancel_date IS NULL`). The one self-heal claim that did **not** hold — the payer `sub_id` writeback — became **C-012/C-015**.
- **Already gym-scoped / not user-supplied** — refund charge lookup IS gym-scoped (`member_charge_by_id.sql`); `task_items.target_price_id` is server-discovered and validated, never client-supplied.
- **Cosmetic / immaterial** — NULL `next_due_date` display-only; `paid_for` 500-char overflow yields a loud Stripe 400, not silent truncation.

**One explicit false positive caught during validation:** the early "🔴 import-breaking SyntaxError / Python-2 `except`" claim about `payments_stripe_members_service.py:329` is **wrong** — on **Python 3.14** (this project's runtime) `except KeyError, TypeError:` is valid (PEP 758) and catches both. *Open follow-up:* if the supported Python floor is ever pinned **below 3.14**, that line becomes a real (low-sev) portability issue.

---

## Provenance & next steps

- **Run:** workflow `billing-deep-review` (run id `wf_19f4e476-1ac`) + a 6-agent rejection-audit. Raw stage outputs (`referee_result.json`, full rejected list) saved under the job tmp `review/` dir; per-agent transcripts in the workflow record.
- **Confidence:** every confirmed finding was re-verified against the code; the high-severity items and the two reopened mediums (C-066, C-079-freeze) were read directly. The 69 rejections were audited for false negatives (62 held).
- **Suggested triage order:** the 4 highs first (C-079 and C-025 are sharpest — a member self-settle/self-freeze hole and silent revenue loss), then the medium money/idempotency/correctness cluster (C-026, C-066, C-081, C-083, C-086, C-012), then the NEEDS DECISION items (C-012, C-064, C-078, C-088), then the lows. C-089 (regression tests) rides along with each fix.
- **Process note:** per repo rules, the payment-sync / memberships engine is edited **one approved piece at a time** — triage and fix these individually, not as a batch.
