# Payment Sync Refactor

> **Status:** Proposed — design/spec, not yet implemented. This doc describes the decided
> direction for the payment-sync engine and the discount model. The code it references is
> current as of this writing; the changes below are future work. When the refactor lands,
> update `README.md` + `architecture.mermaid` and the relevant CLAUDE.md sections in the same
> change (see §8).

## 1. Context — the fear that built the engine

`src/member_memberships/service/payment_sync/` recomputes the **full desired Stripe subscription
state from the CRM on every membership mutation** (start, cancel, freeze/unfreeze, price change,
discount change, link/unlink) and forces Stripe to match. It was built out of a fear of the CRM
and Stripe drifting out of sync: by re-deriving and converging on every request, any transient
drift self-heals the next time that member is touched.

This is a legitimate, named pattern — **reconciliation toward desired state** (the model behind
Kubernetes controllers, Terraform, declarative infra). The fear is also real: you cannot run a
transaction across your Postgres and Stripe's API, so partial failures, missed webhooks, retries,
and races genuinely cause drift in every Stripe integration.

The one gap in the current design: **it only self-heals when a member is actively touched.** Drift
on an idle member persists until the next operation on that member. A real reconciler needs a sweep
that runs on a clock, independent of user activity.

## 2. Decisions

1. **Keep the per-request full recompute.** Mirroring Stripe subscription state (cost + state) into
   the CRM stays — it's the write-time consistency guarantee. The only real cost is code
   complexity, which is acceptable at this volume (membership changes are human-initiated admin
   events, not high-QPS traffic, so latency/rate-limit concerns don't apply).
2. **Add a scheduled reconciler** (periodic sync, e.g. hourly/nightly) as the backstop for idle-member
   drift and missed webhooks. It reuses the existing recompute where it can (see §4).
3. **Make discounts immutable presets** (snapshot-on-apply) so editing a discount never retroactively
   re-bills existing members (see §5).
4. **Keep the source-of-truth split** explicit: CRM owns config/intent, Stripe owns billing
   outcomes (see §3).

## 3. Source of truth — config vs. outcomes

Two different kinds of "truth", split deliberately:

- **CRM owns config / intent** — prices, plans, discounts, who is enrolled. These *originate* in the
  CRM. No member self-serves via a Stripe-hosted Customer Portal, so config changes never start on
  Stripe's side. This is legitimate (and is the same carve-out Stripe documents for usage data:
  "Stripe should not be your source of truth for usage — your database is"). The per-request
  recompute is the mechanism that pushes this intent to Stripe.
- **Stripe owns outcomes** — did the invoice clear, card declines, refunds, actual billing dates, and
  the **dunning lifecycle**. These are mirrored back into the CRM via the existing Stripe webhooks
  (`src/stripe_webhooks/` — `invoice.paid`, `invoice.payment_failed`, `charge.refunded`,
  `account.updated`).

**Why this matters for the reconciler:** the real drift source is *not* someone editing Stripe by
hand (with Connect, nobody does). It's that **Stripe's billing engine autonomously changes
subscription state** — Smart Retries / dunning will move a subscription `past_due → unpaid →
canceled` on Stripe's own schedule, days after a card fails, with no CRM request. The CRM will still
say "active" until something tells it otherwise. That "something" is the webhook, and the reconciler
is the backstop for when the webhook is missed.

## 4. The scheduled reconciler

### What reuses cleanly
`MembershipPaymentSyncService.bulk_payment_sync` (`membership_payment_sync_service.py:227`) is
already the seed: it loops members, generates a fresh idempotency key per member (`uuid4()`), and
calls `update_payments_recurring` with empty add/cancel. A scheduled job is just a **third trigger**
for it, alongside the existing two (see §6). The **CRM→Stripe config push** (correct items,
quantities, discounts, price on the subscription) reuses with no rewrite.

### What does NOT reuse — and is the new work
`execute_sync` (`payment_sync_stripe.py:41`) only ever **pushes desired state** built from the CRM;
it **never reads the subscription's actual Stripe status**. `bucket.existing_sub_id` comes from the
CRM (`parent.stripe_sub_id_month`), and the method dispatches create/update/cancel off the CRM's
view of the world. Consequences for a naive sweep:

- It will **not** detect that Stripe's dunning engine cancelled a sub. On a Stripe-cancelled sub,
  `update_subscription` would just error (`PaymentsResourceNotFoundError`), get caught and logged by
  `bulk_payment_sync`, and **leave the CRM stuck on "active."** Drift persists.
- So the **Stripe→CRM outcome-absorption** half is genuinely new logic (or a re-verification of what
  the missed webhook should have done). The sweep must fetch the subscription's *actual* Stripe
  status and reconcile it into the CRM.

### Conflict-resolution rule (load-bearing)
When the sweep finds Stripe ≠ CRM, **the winner depends on the kind of difference**:

- **Config drift** — wrong items / quantities / discount / price on the sub → **CRM wins** → push to
  Stripe (reuse the recompute). This is config the CRM authored.
- **Lifecycle / outcome drift** — Stripe shows `canceled` / `past_due` / `unpaid` from dunning →
  **Stripe wins** → absorb into the CRM (mark the member delinquent / cancelled). **Do NOT recreate
  the subscription or re-bill.** Blindly converging here would resurrect a delinquent member's
  subscription and fight Stripe's billing engine every run.

This split is the difference between a safe reconciler and one that undoes Stripe's dunning.

### Other requirements
- **No-op when already in sync.** `execute_sync` currently always issues a Stripe `update` for an
  existing sub with items (it does not diff). On a per-request change that's fine; on an hourly
  sweep it means pointless writes (and proration risk if anything is off). The scheduled path needs
  a **compare-desired-vs-actual, skip-if-equal** guard.
- **Fresh idempotency key per run/member** — already done in `bulk_payment_sync`.
- **What to compare:** subscription status (to catch dunning), items/quantities, discounts, and
  price/cost.
- **The sweep validates convergence-to-our-logic, not correctness.** A bug in the desired-state
  computation reproduces identically in both the per-request path and the sweep (same code). The
  independent correctness check on *outcomes* remains the webhook mirror + tests — not the sweep.

## 5. Discounts as immutable presets

### The change
Discounts become reusable **presets / templates**. Applying one **snapshots its values onto the
membership** as an independent instance, rather than holding a live reference to a mutable discount
definition. Editing or deleting a preset **never** changes what existing members pay; it only
affects *new* applications. This mirrors Stripe, where Coupons are immutable and an applied Discount
is attached to that subscription.

### Why
- **Kills the most dangerous cascade in the system.** Today, editing/deleting a discount fans out to
  every holder via `bulk_payment_sync` (see §6) — a gym owner tweaking a discount could silently
  re-bill dozens of members. Snapshot-on-apply makes that structurally impossible.
- **"What discount does this member have" becomes a local, history-accurate fact**, not a join to
  mutable state.

### Details
- **One Stripe coupon per value.** A "10% off" coupon is identical regardless of who holds it — keep
  one Stripe coupon per distinct value and reuse it; the *snapshot* is the local record. This avoids
  coupon explosion. The change is a local data-model change, not a Stripe-object-per-application
  change.
- **Orthogonal to linked/family discounts.** Linked discounts decide *which* preset a sibling gets;
  that per-request, family-scoped assignment (`LinkedMemberDiscountService`, invoked from
  `_build_sync_params`) stays. Presets only remove the *definition-edit* blast radius.
- **Open question:** is there an explicit "re-apply preset to existing holders" bulk action, or do
  preset edits *only ever* affect new applications? Default: immutable after apply (no automatic or
  manual retroactive change). Decide before implementing.
- **Migration:** a one-time backfill snapshotting each membership's current discount values onto the
  membership row.

## 6. What collapses

- **Discount cascade triggers removed.** `bulk_payment_sync` is currently called from three sites:
  - `src/discounts/service/discounts/discounts_update.py:170` → **removed** by §5 (preset edits don't cascade)
  - `src/discounts/service/discounts/discounts_delete.py:108` → **removed** by §5
  - `src/membership_plans/service/plans/membership_plans_price.py:287` → **stays** (a deliberate,
    intentional bulk price migration across a plan — not silent drift)
- **Per-request defensive logic becomes reducible.** Once the scheduled sweep + tests are the
  drift backstop, the per-request path no longer has to be the sole guarantee and can shed defensive
  scaffolding. (Kept by choice for write-time consistency — this is "can," not "must.")

## 7. Industry-standard validation

The approach lines up with documented standard practice:
- **Webhooks (fast path) + a periodic reconciliation poll (backstop)** is the mainstream
  recommendation, including from Stripe's own engineering blog series on database reconciliation.
- "Recompute full desired state on each write vs. targeted delta" is *not* a documented standard —
  it's an engineering judgment. At this volume the recompute cost is negligible, so the choice is
  about code complexity, not correctness or performance. Keeping it is a defensible
  consistency-first call.
- The source-of-truth split (app owns config, Stripe owns outcomes) matches Stripe's own
  documented carve-out for app-owned data (usage).

## 8. Open questions & follow-ups

- Reconciler **cadence and scope** — all active subs each run, or changed-since / per-gym batching?
- The **"re-apply preset to existing holders"** decision from §5.
- Exact **status-absorption mapping** — which Stripe statuses (`canceled`, `unpaid`, `past_due`) map
  to which CRM member/membership states, and how that interacts with the existing webhook handlers
  (to avoid double-applying).
- **Living-doc updates required when the refactor lands** (per `FastApiBackend/CLAUDE.md`):
  `FastApiBackend/README.md` + `architecture.mermaid` (the `MembershipPaymentSyncService` fan-in and
  any new scheduled-job node), and the relevant CLAUDE.md sections. Author the charts with the
  `mermaid-creation` skill.
