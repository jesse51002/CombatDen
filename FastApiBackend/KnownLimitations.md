# Billing Engine — Known Limitations

> **Scope:** known bugs / limitations / gaps in **existing** billing functionality
> that are *not yet fixed* — the residue from the billing-engine review. This is
> the forward record of "what's still imperfect about what we already have."
>
> **Not** for new features — those live in `PaymentRefactor.md`. When one of these
> is fixed, **remove it** here (don't annotate "done").

Each item is documented with its impact, why it was deferred, and the fix.

---

## Correctness & robustness

### 1. Duplicate subscription from a lost `sub_id` writeback (C-012)
- **What / impact:** Of the best-effort writeback steps, the payer `sub_id` write is the only one with no caller verify-or-revert backstop. If it's swallowed while the membership row stamps land, the next `PaymentPushSweep` reads `sub_id = NULL` and **creates a second subscription**; the immutable `stripe_item_id` trigger then orphans the tracked sub, the orphan sweep reaps it, and a later sweep cancels a paying member while the original sub keeps billing — a transient **double-bill + membership loss**. Narrow trigger (a partial writeback failure), but real money/data risk; the backstops (`PaymentPushSweep`/`StaleTaskSweep`) don't cover it and are themselves untested.
- **Why deferred:** The DB write is always *post*-Stripe-mutation, so it's inherently best-effort — the proper fix is structural and out of MVP scope.
- **Fix:** A durable failed-writes store (transactional **outbox**) recording any swallowed writeback step, drained by a reconciler that retries across crashes — the general fix for *all* best-effort writeback steps. **Cheap interim mitigation:** co-write `sub_id` + the row stamps in one transaction so the dangerous precondition ("rows stamped but `sub_id` NULL") can't arise; a crash then degrades to the benign "fresh sub + orphan reaped."

### 2. Stripe retrieve runs inside the webhook / reconciler DB transaction (C-053)
- **What / impact:** `InvoicePaymentPaidHandler.resolve_charge()` (a live `payment_intents.retrieve`) still runs inside the open DB transaction on both call paths (the webhook dispatcher and the reconciler invoice-fetch). Under concurrent webhook load a Stripe latency spike holds a pooled DB connection. Low severity (webhook/reconciler volume is modest, Stripe has its own timeout).
- **Why deferred:** The pre-transaction seam (`charge_details=` on `record()` + the public `resolve_charge`) is in place, but wiring it cleanly is non-trivial: the reconciler's `_run_record` is a **generic runner** shared across invoice/payment/refund records, so moving the Stripe call out of the txn means restructuring it or duplicating its per-record error isolation; the webhook dispatcher path needs the generic dispatch to special-case pre-resolution.
- **Fix:** Pre-resolve via `resolve_charge()` before opening the transaction and pass the result as `charge_details=`, in both `stripe_webhooks_service.py` and `memberships_invoice_fetch.py`.

### 3. `set_price` holds a pooled DB connection across the Stripe call (C-058)
- **What / impact:** `set_price` runs deactivate-old + insert-new + `create_price` + commit in one transaction, so a pooled asyncpg connection is held during the Stripe network call. Under concurrent admin repricing this can pressure a small pool.
- **Why deferred:** The `idx_max_one_active_price_per_plan` constraint forbids two active prices, so deactivate + insert must be atomic, and keeping rollback-on-Stripe-failure forces the Stripe call inside that txn (the obvious "deactivate→commit→Stripe" alternative reintroduces the original strand bug). `set_price` is a rare admin op.
- **Fix (future — the opposite of today's single-txn approach):** Create the Stripe price *first* (outside any txn) with a **client-generated `price_id`** threaded into the metadata, then one short txn for deactivate-old + insert-new. Needs an insert-SQL change to accept a provided `price_id`.

### 4. Freeze trusts the client-supplied `gym_id` (C-070)
- **What / impact:** The freeze endpoint passes the client's `gym_id` into the freeze/payer lookups; `verify_can_view_member` never validates it. The **interim fix shipped** (a rowcount guard so a mismatch fails loudly instead of silently freezing 0 rows).
- **Why deferred:** The cleaner remedy touches `memberships_service.py` (the payer-lookup path) beyond the freeze group's scope.
- **Fix:** Derive `gym_id` from the member's own row server-side; drop the client-supplied field from the freeze/payer lookups.

### 5. Retried one-time start returns 500 instead of a graceful 409 (C-086)
- **What / impact:** A client retrying a *succeeded* one-time start now correctly avoids double-granting, but surfaces as an HTTP **500** (a `RuntimeError` from the replay-detected insert shortfall) rather than an idempotent 201 or a retryable 409. Correctness is right; the response is just not graceful.
- **Fix:** Map the replay `RuntimeError` to a 409 (or re-fetch the original rows and return 201).

### 6. One-time writeback line-count mismatch is best-effort, not loud-fail
- **What / impact:** On a line-count mismatch in the one-time writeback, `_writeback_membership_rows` logs an ERROR and stamps the overlap (`zip(strict=False)`), so a tail member could be left `not_added` (looks unpaid). The mismatch is **impossible by construction** (`_order_lines` returns exactly one line per item or raises during `_execute`, before the charge writeback).
- **Why deferred:** `strict=True` would raise straight into the start op's cleanup/delete branch — **reintroducing C-025** (un-billing a successful charge), which is strictly worse. The ERROR log flags the impossible case for manual reconciliation.
- **Fix:** If this ever fires, reconcile manually; a clean fix would re-derive the affected rows from the paid invoice rather than positional zip.

## Data-quality (audit / reporting only — no money impact)

### 7. Invoice discount-audit capture truncates at 10 lines
- **What / impact:** The `invoice.paid` discount-audit capture reads only Stripe's embedded first page (10 lines), so a >10-line family invoice undercounts the `member_invoice_applied_discounts` rows — the same truncation class C-026 fixed for charging. Audit/reporting only; no money mischarged.
- **Why deferred:** Fixing it adds a Stripe API call into the webhook path.
- **Fix:** Paginate the lines (follow `has_more`) in the capture, mirroring `_all_invoice_lines`.

## UX & product (frontend)

### 8. Cash-settling a consolidated invoice forgives the whole family (C-078)
- **What / impact:** `mark_paid_cash` settles the *whole* consolidated subscription invoice out-of-band (Stripe offers no per-line out-of-band settle), so recording one member's cash forgives every co-billed line. An operator could unintentionally forgive a whole family's invoice.
- **Why deferred:** Inherent to consolidated invoicing at the engine level; the mitigation is UX.
- **Fix:** A **CRM warning** before a cash-settle (frontend), and/or track cash at the membership-row level so only fully-cash invoices settle out-of-band.

## Code quality / convention (cosmetic)

### 9. `_revert_db_phase` inlines `_delete_pending`'s SQL
- The atomic transition revert re-loads and fires `member_memberships_delete_pending.sql` on the shared session instead of calling `_delete_pending` (which opens its own session). Intentional, for the single-transaction revert.
- **Fix:** Extract a session-accepting `_delete_pending(session, item_ids)` on `MemberMembershipsBase`, called by both paths.

### 10. Page-limit constants could live in `config.py`
- `INVOICE_LINE_ITEMS_PAGE_LIMIT` / `SUBSCRIPTION_OPEN_INVOICE_LIMIT` are module-level `UPPER_CASE` constants (CLAUDE.md-compliant), but moving them to `config.py` `Settings` fields would make them env-overridable in tests. Optional.

### 11. `member_memberships.idempotency_key` has no immutability trigger
- It's listed immutable in `immutable_columns.py` (protecting client paths), but unlike `price_id` / `stripe_item_id` etc. on the same table it has no `prevent_idempotency_key_overwrite` trigger, so a service-role UPDATE isn't DB-blocked. Low risk (service-role-managed, set once at INSERT).
- **Fix:** Add a `trg_prevent_idempotency_key_overwrite` trigger in `member_memberships.sql` (+ migration), matching the other immutable columns.

### 12. `_insert_line_items` doesn't skip proration lines
- `_capture_discounts` and `_update_memberships` skip proration lines; `_insert_line_items` doesn't. Negative proration credits are already filtered by the `member_invoice_line_items.amount >= 0` CHECK, so a **zero-dollar** proration line is the only edge that would record a stray line item.
- **Fix:** Mirror `if self._is_proration(line): continue` in `_insert_line_items`.
