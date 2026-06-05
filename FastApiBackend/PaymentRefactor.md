# Payment Sync Refactor

> **Status:** Discount model **implemented** — three tables: a discount IDENTITY
> (`gym_discounts`), versioned **truly immutable** VALUE rows (`gym_discount_values`, service-role
> only like `membership_plan_prices`), and slim applied snapshots pinned to a value version
> (`member_membership_applied_discounts`); linked/family discounts are real version-backed entries a
> plan references by id; coupons computed at sync and written back. **The `discounts-guide` skill is
> the source of truth for the model;** this section is the design rationale. The **scheduled reconciler
> (§4) is still future work** — and it is now *load-bearing*, not just a drift backstop: it
> enforces `end_date` cutoffs and finalizes `once`-discount consumption (see §4). §5 below is
> the final, shipped discount model. The per-request recompute, the source-of-truth split (§3),
> and the cascade removal (§6) are live. `README.md` + `architecture.mermaid` and the relevant
> CLAUDE.md sections were updated in the same change as the discount work.

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
2. **Add a scheduled reconciler** (periodic sync, e.g. hourly/nightly) — now **load-bearing**: it
   backstops idle-member drift and missed webhooks *and* enforces ongoing discounts' `end_date`
   cutoffs and finalizes `once`-discount consumption (see §4). It reuses the existing recompute.
3. **Make discounts immutable applied snapshots** (snapshot-on-apply, item-scoped) so editing a preset
   never retroactively re-bills existing members; **keep linked discounts as real version-backed entries** a plan references by id; **compute coupons at sync and write back `stripe_coupon_id`** (see §5).
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

> **Elevated from backstop to load-bearing.** With the discount model in §5 shipped, the
> scheduled reconciler is no longer *only* a consistency/drift safety net — it is **critical
> functionality two real features depend on**:
>
> 1. **Arbitrary `end_date` enforcement.** An ongoing discount's lifetime is an absolute
>    `end_date` we enforce ourselves (Stripe coupons only know `once`/`forever`; see §5). The
>    discount is dropped from the line *the first time a sync runs on or after that date*. On a
>    member who is actively billed every cycle, the end-of-cycle billing sync drops it on time.
>    On an **idle** member (no membership changes near the cutoff), nothing triggers a sync, so
>    the discount would keep applying past its `end_date` until the member is next touched. The
>    scheduled sweep is what runs the sync on the clock and drops it on schedule.
> 2. **`once`-discount consumption finalization.** A `once` discount is "consumed" when Stripe
>    invoices it; the sync detects this (its stored `stripe_coupon_id` is no longer present on
>    the subscription) and **stamps `end_date` = the consumption date** so it is never re-added.
>    That detection only happens when a sync runs after the invoice. The sweep guarantees the
>    consumption is finalized promptly instead of lingering as "still pending" until the next
>    manual operation on that member.
>
> So the reconciler is now a **functional dependency** of the discount system, not merely a
> healing mechanism for missed webhooks. Building it remains out of scope for the discount
> refactor — but its elevated importance is recorded here so it is scheduled as a real feature,
> not a nice-to-have. Everything below (reuse, the new outcome-absorption work, the
> conflict-resolution rule) is the same machine that also runs these two discount duties.

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

## 5. Discounts: immutable applied snapshots, coupons computed at sync

> **This is the shipped model.** The #1 goal is **predictability**: a member's billing changes
> **only** via an explicit add/remove on *that* member's specific membership, and everything that
> is discounted is visibly tied to one membership / Stripe item — you can see exactly what is and
> isn't discounted.

### 5.1 Three tables: identity, versioned values, applied snapshots
A discount is an IDENTITY (`gym_discounts`: name + `discount_type`) plus versioned, **immutable**
VALUE rows (`gym_discount_values`: percent/dollar + lifetime; editing mints a new active version,
mirroring `membership_plan_prices`). Applying one **writes a slim snapshot row** into
`member_membership_applied_discounts`, keyed to one membership (`item_id`), pinning it to the
discount's active **`value_id`**. **Remove = DELETE that row.** The user **never edits** a snapshot;
to change a discount they remove the row and add a different one. The `/discounts/preview` path
mirrors apply without mutating Stripe.

**Why this is predictable:** editing a discount mints a NEW version; existing snapshots stay pinned
to their old `value_id`, so they are untouched — an edit only affects *future* applications, and you
can prove which exact version a member is on. The thing we never want: an edit fanning out to
silently re-bill every holder.

### 5.2 Linked (family) discounts are real version-backed entries
A linked/family discount is a **real discount entry** like any other — a `gym_discounts` identity
tagged `discount_type = linked` with a versioned value on `gym_discount_values` — so it gets
versioning + a stable id to point to. A **membership plan references its family discounts by id**
(`membership_plans.linked_discount_ids` stores a discount id per family tier). Applying one is the
same as any discount: the membership/family flow passes its id, freezing a snapshot to the
discount's active value version; the sync divides it across the shared consolidated line (§5.4),
deterministically from that member's own memberships only. The `linked` tag keeps it out of the
regular per-membership discount picker; `members.account_linked_to_id` and family billing are
unchanged. The thing we never want: a cross-member recalculation that reshuffles who gets what.

### 5.3 Discount lifetime = `once` / `ongoing`, with a duration-span XOR an explicit `end_date`
Every discount has a `discount_mode` of `once` or `ongoing`. An `ongoing` discount's end is set by
**either** a `duration` span on the preset (`duration_amount` + `duration_unit` ∈ day / week /
month) **or** an explicit `end_date` — **exactly one, never both** (DB CHECK); **neither = forever**.
At apply-time the snapshot's absolute `end_date` is resolved (`apply_date + duration` via
`relativedelta`/`timedelta`, or copied from the explicit `end_date`). `once` discounts leave
`end_date` null until the sync stamps it on consumption (§5.5).

**Why absolute `end_date`, not a relative month-count (the coupon-swap-invariance rationale):** the
sync **swaps a percentage's Stripe coupon whenever the consolidated quantity changes** — adding or
removing a family member on the shared line shifts the `÷ quantity` split, producing a *different*
effective percent and therefore a different coupon (§5.4). A relative "N months from start" would
**reset its clock on every swap** and overrun its intended lifetime. An **absolute `end_date` is
invariant under coupon swaps** — the swap changes the coupon's value but never its end. Stripe has no
native arbitrary end date, so **we enforce the cutoff ourselves** by dropping the discount from the
line on/after the date (which is why days/weeks/months all work, not just Stripe's month-count). The
mid-cycle enforcement of that cutoff on an idle member is exactly what makes the scheduled reconciler
load-bearing (§4).

### 5.4 Coupons are computed at sync, then written back (per-line aggregation)
Presets and snapshots store **intent**; **no Stripe coupon is pre-baked** at preset creation or even
at apply (except the `once` attach in §5.5). For each consolidated line (price `P`, quantity `N`,
with the snapshots of the memberships on it), the sync:

1. **Reads the subscription's current Stripe discounts first** — `PaymentSyncCoupons` +
   `PaymentsStripeSubscriptionService.get_subscription` (a genuinely new read; the old `execute_sync`
   only ever *pushed* desired state, the §4 read-half gap).
2. **Excludes any snapshot past its `end_date`** — this is how we enforce arbitrary end dates.
3. **Applies the `once` consumption gate** (§5.5).
4. **Aggregates per line, grouped by `discount_mode`** (so `once` and `ongoing` never mix):
   `line_percent = (Σ per-unit percents) ÷ N`; `line_amount = Σ per-unit dollar_offs`. This **fixes
   the percent × quantity bug** — a 10% discount on 1 of 2 units becomes 5% on the quantity-2 line —
   and is computed from the member's *own* memberships only, with no cross-member reshuffle.
5. **Find-or-creates the coupon** on the gym's Connect account using a **deterministic per-account
   coupon ID** from the value signature (`pct_<bps>_<mode>`, `amt_<cents>_<mode>`), so creation is
   idempotent and one coupon per value is reused (no coupon registry table). `once` → a Stripe `once`
   coupon, `ongoing` → a Stripe `forever` coupon (the `end_date` cutoff is enforced by *us* dropping
   the discount, never by Stripe).
6. **Writes the resolved `stripe_coupon_id` back onto each contributing snapshot** (a system
   writeback, at service-role) and attaches the coupon to the line. For `once` snapshots this stored
   coupon is the presence handle used by the consumption gate.

### 5.5 `once` consumption is tracked via Stripe (the written-back coupon is the handle)
A `once` discount is **attached to Stripe at apply-time** so the sync can write its
`stripe_coupon_id` back onto the snapshot and later read its absence as "consumed" (Stripe owns
outcomes; §3). On each sync, reading the subscription's **current** discounts:

- **coupon present** → still **pending** → it participates in the aggregation like any other; **if
  the count changed its computed value the sync swaps the coupon** (re-add), writing back the new
  `stripe_coupon_id`. While pending, only consumption freezes it.
- **coupon absent** → Stripe already invoiced it → **done** → the sync **stamps `end_date` = today**
  (recording the consumption date) and never re-adds it. From then on the `end_date` exclusion (step
  2 above) handles it, so we stop querying Stripe for it.

### 5.6 Seeding the model
There is no data-migration step. The model is created fresh by the schema reset + the seed
(`Database/python_data/main.py`): discounts (identity + first active value), plans that reference
real `linked` discount entries by id, and applied-discount snapshots on members — including a linked
(family) discount applied to members on the linked plan, so the full path is exercised end-to-end.

### 5.7 Deferred (open questions — recorded, not built)
- **Automatic propagation of a preset/plan edit to existing snapshot holders.** Today a preset edit
  affects only *new* applications (the predictability guarantee). The **provenance fields**
  (`source_discount_id`, `linked_discount_planid` + `linked_discount_num`) exist precisely so a
  future "re-apply this preset to its existing holders" bulk action *can* find and update the
  snapshots that derive from a given preset. Default until then: immutable after apply.
- **A possible "same membership type" constraint** to make that auto-update edge-case-free — if every
  snapshot deriving from a preset is guaranteed to sit on the same plan/quantity shape, re-applying a
  changed value is unambiguous. Not decided.
- **Mixed-mode aggregation edge cases on a single consolidated line** (e.g. both a percent and a
  dollar value of the same mode on one line) are not fully specified; the common case (one value per
  mode) is exact.

## 6. What collapsed

- **Discount cascade triggers removed (done).** `bulk_payment_sync` was called from three sites; the
  two discount cascades are **gone**:
  - `discounts/service/discounts/discounts_update.py` → **removed** — preset edits affect only future
    applications; existing snapshots are untouched (the §5 predictability guarantee). The Stripe
    coupon create/swap + old-coupon delete left this path too (presets are coupon-free now).
  - `discounts/service/discounts/discounts_delete.py` → **removed** — delete is now **archive only**
    (`is_deleted = true`); existing holders keep their snapshot, no "strip from every membership" step.
  - `membership_plans/service/plans/membership_plans_price.py` → **stays** (a deliberate, intentional
    bulk price migration across a plan — not silent drift).
- **The linked-discount recalc machinery is gone (done).** `LinkedMemberDiscountService`, its SQL, the
  `payment_sync_discount_allocator`, the `_build_sync_params` call sites, and the DI provider were
  deleted (§5.2). `MembershipPaymentSyncService` no longer takes a `_linked_discounts` arg; it now
  takes a `stripe_client` and owns `PaymentSyncCoupons` (the sync-time coupon compute) instead.
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

- **Build the scheduled reconciler.** Now load-bearing (§4): it enforces ongoing discounts'
  `end_date` cutoffs and finalizes `once`-discount consumption on idle members, on top of its
  drift-backstop role. Open: **cadence and scope** — all active subs each run, or changed-since /
  per-gym batching?
- **Multi-interval recurring (weekly / yearly) + a paid-time-preserving freeze (§9).** Deferred
  post-MVP, required long-term. Adds week/year billing intervals (one Stripe sub per interval) and a
  freeze that recalculates the next pay date to preserve the member's remaining paid time — the part
  that was too complex for the MVP window and was the reason simple freezing shipped instead.
- **Configurable billing anchor (§9.5).** Recurring subs are currently forced to anchor on the 1st
  (`MONTHLY_BILLING_ANCHOR_DAY`). The anchor date should be optional (chosen at create), generalizing
  to day-of-week / date for weekly/yearly — settable only at create, locked once a sub is active.
- Exact **status-absorption mapping** — which Stripe statuses (`canceled`, `unpaid`, `past_due`) map
  to which CRM member/membership states, and how that interacts with the existing webhook handlers
  (to avoid double-applying).
- **Discount auto-update (deferred, §5.7):** an explicit "re-apply a changed preset to its existing
  snapshot holders" bulk action — enabled by the provenance fields but intentionally not built; and a
  possible "same membership type" constraint to make it edge-case-free.
- **Living-doc updates — done in this change** (per `FastApiBackend/CLAUDE.md`):
  `FastApiBackend/README.md` + `architecture.mermaid` (removed `LinkedMemberDiscountService`; added the
  `member_membership_applied_discounts` snapshot table + the sync-time coupon computation /
  `PaymentSyncCoupons` step) and the relevant CLAUDE.md sections. The deep discount domain knowledge
  lives in the ``discounts-guide`` skill (Phase 5). Charts authored with the `mermaid-creation` skill.

## 9. Future: multi-interval recurring (weekly / yearly) + a freeze that preserves paid time

> **Deferred post-MVP, recorded as a real feature to build — not a nice-to-have.** Recurring is
> monthly-only today; **weekly and yearly are needed.** The blocker that pushed this past MVP was
> **freezing done correctly**: a true freeze has to recalculate the next billing date so the member
> keeps exactly the paid time they had left, and that interval math + Stripe billing-anchor work was
> too much for the MVP window — so a simple pause shipped instead. It is required long-term, so the
> design is captured here.

### 9.1 Current state — monthly only, one bucket, one sub
Recurring plans are constrained to monthly: the DB `recurring_must_be_monthly` CHECK, the engine's
single monthly `IntervalBucket` ("exactly one bucket"), and the interval-named
`members.stripe_sub_id_month` column all assume one interval. The `IntervalBucket.interval` field and
the `_month` suffix were left in deliberately — they anticipate this extension.

### 9.2 Multi-interval support
- **Lift `recurring_must_be_monthly`** — allow recurring `duration_unit ∈ week / month / year`.
- **One Stripe subscription per interval.** Stripe cannot mix billing intervals on a single
  subscription, so a family with weekly + monthly + yearly memberships needs up to **three
  subscriptions**. `members` gains `stripe_sub_id_week` / `stripe_sub_id_year` alongside the existing
  `stripe_sub_id_month`.
- **One bucket per interval present.** The read path groups the family's active recurring memberships
  by `duration_unit`; `build_subscription_bucket` produces a bucket per interval instead of forcing a
  single month bucket; `execute_sync` runs per bucket (create/update/cancel its own sub); the
  writeback fans per sub. Per-line consolidation and the §5 discount/coupon logic are unchanged
  *within* each bucket.

### 9.3 The custom freeze — recalculate the next pay date to preserve remaining paid time
**Why the current freeze is insufficient.** Today freeze = Stripe `pause_collection` + a resume date.
Pausing collection does **not** give the member back the time they were frozen — it doesn't shift the
renewal so they resume with exactly the remaining interval they had paid for; the billing clock keeps
ticking through the pause. For monthly that was "close enough" to ship; for **weekly** (day/week
precision) and **yearly** (a few frozen months is real money against a year) it is not.

**What a correct freeze does:**
1. **On freeze**, capture the **remaining time** until `next_due_date` — the credit the member has
   already paid for (e.g. "11 days left in the cycle", "4 months left in the year").
2. **On unfreeze**, set the **next billing date = unfreeze_date + that remaining credit**, so the
   member resumes with exactly the interval they had left and the whole cadence shifts forward by the
   freeze duration. This is the "recalculate `next_due_date` to match what it was before the freeze" —
   the billing clock effectively *stops* during the freeze instead of continuing to tick.
3. **In Stripe**, this means shifting the subscription's **billing anchor** (e.g.
   `billing_cycle_anchor` / `trial_end` / proration controls) so the next invoice lands on the
   recomputed date — not merely pausing and resuming collection.
4. **Across every interval sub** — each interval subscription's anchor is recomputed independently;
   remaining time uses `relativedelta` for month/year and `timedelta` for week.

This is the piece that was too complex for the MVP and is explicitly deferred — but required for
weekly/yearly to be correct. It builds on the **dedicated freeze action** (split out of
`update_payments_recurring` so the freeze path can own this anchor math without running a full sync).

### 9.4 Open questions
- **Exact Stripe mechanism** for the anchor shift (`billing_cycle_anchor` reset vs `trial_end` vs
  pause + manual anchor) and its proration / invoice-timing implications per interval.
- **Freeze input shape** — an explicit end-date vs a span — and how partial-cycle remaining time is
  computed and stored per interval.
- **Discount-lifetime interaction** — an absolute discount `end_date` (§5.3) does *not* move with a
  freeze, so a member loses discount time while frozen; confirm that's intended or whether a freeze
  should extend it.
- **Per-interval sub-id storage + read/writeback fan-out**, and the **scheduled reconciler** (§4)
  handling multiple subscriptions per member.

### 9.5 Configurable billing anchor (create-only; locked once a sub is active)
**Current state — forced to the 1st.** Every recurring subscription is pinned to one fixed anchor
day: `payments_subscription_create.py` sets `billing_cycle_anchor` from `MONTHLY_BILLING_ANCHOR_DAY`
via `_next_monthly_anchor_timestamp`, so all members bill on the 1st.

**Needed — optional anchor date.** The anchor should be **configurable** — the member/gym chooses
what date to bill on, not hard-coded to the 1st. This matters more with multi-interval (§9.2): the
anchor generalizes to a **day-of-week** for weekly and a **date** for yearly, and the
paid-time-preserving freeze (§9.3) already manipulates the anchor.

**Constraint — create-only, then locked.** The anchor is settable **only at subscription create**
(when there is no active sub). **Once a sub is active the anchor is locked down** — re-anchoring a
live subscription mid-life disrupts billing/proration, so it must be immutable after create. Changing
it would mean cancel + recreate, never an in-place re-anchor.

**Open questions:** where the chosen anchor lives (per member? per membership? gym default +
override?); how it interacts with first-invoice proration; and the per-interval anchor shape
(day-of-month vs day-of-week vs date) under §9.2.
