---
name: payments-guide
description: >-
  The single source of truth for the CombatDen Stripe integration layer — the
  primitive Stripe wrappers in `src/payments/` (a pure service layer with NO
  routers) and the inbound webhook mirror in `src/stripe_webhooks/`. Covers the
  CRM-owns-config / Stripe-owns-outcomes split, the Stripe Connect model
  (`gyms.stripe_account_id` + `stripe_onboarding_status`,
  `PaymentsStripeClient.connect_opts` / `connect_opts_readonly` account scoping +
  idempotency keys), the typed metadata models that pin each Stripe resource to a
  CRM row, the service primitives (members / membership-product / price / payment /
  low-level coupon find/create/delete I/O) and the subscription sub-services
  (`PaymentsStripeSubscriptionService` facade + create/update/cancel/freeze/
  migration/upcoming/retrieve/item delegates + `get_subscription` read primitive +
  `_map_subscription` / `_consolidate_items` / `_build_reconcile_items` base
  helpers), plus the webhook ingestion (`/api/v1/stripe/webhooks` → signature
  verify → `StripeWebhooksService.handle_event` → gym resolution → `event_log` +
  `stripe_webhook_events` dedup → the four handlers `invoice.paid` /
  `invoice.payment_failed` / `charge.refunded` / `account.updated`) and the
  invoice/charge data model (`member_invoices`, `member_charges`,
  `member_invoice_line_items`, `member_invoice_applied_discounts`). Trigger on
  "Stripe", "connect account", "stripe_account_id", "connect_opts", "idempotency
  key", "webhook", "invoice.paid", "charge.refunded", "account.updated",
  "subscription", "coupon CRUD", "Stripe customer / payment method", "refund row",
  "member_charges", "member_invoices", "onboarding status", "get_subscription", or
  any change to the Stripe wrapper services, the webhook handlers, or the
  invoice/charge tables.
---

# Payments — the Stripe integration layer

This is the deep domain knowledge for CombatDen's **Stripe integration layer**:
how the backend calls Stripe (the primitives in `src/payments/`) and how Stripe
outcomes flow back into the CRM (the webhook mirror in `src/stripe_webhooks/`).
It is the **source of truth** for this layer; CLAUDE.md holds only the "how to
work here" rules, and `FastApiBackend/PaymentRefactor.md` §3 + §1–§4 hold the
prose design rationale. When this layer changes, **update this skill in the same
change** (it is a living document — see the bottom).

This layer is a set of **primitives**, not a brain. It knows *how* to push a
desired state to Stripe and *how* to absorb a Stripe event — it does **not**
decide *what* the desired state should be. The engine that computes desired
subscription state and the sync-time coupon set is owned by `sync-guide`; the
discount system-of-record model is owned by `discounts-guide`; plan/membership
creation that *calls* these primitives is owned by `memberships-guide`. Stay
inside the seam: this guide stops at the Stripe boundary.

---

## 1. Role — config vs. outcomes, and a pure service layer

Two kinds of "truth" are split deliberately (`PaymentRefactor.md` §3):

- **CRM owns config / intent** — prices, plans, discounts, who is enrolled.
  These originate in the CRM and are *pushed* to Stripe. No member self-serves
  via a Stripe-hosted portal, so config never starts on Stripe's side.
- **Stripe owns outcomes** — did the invoice clear, card declines, refunds,
  actual billing dates, the dunning lifecycle, and connected-account onboarding
  state. These are *mirrored back* into the CRM via `src/stripe_webhooks/`.

`src/payments/` is a **pure service layer: it has no router** (verified — there
is no `*_router.py` under `src/payments/`). Its services are consumed by the
sync engine (`member_memberships/service/payment_sync/`) and by the
membership/members/plans services. The only HTTP surface this guide owns is the
**inbound webhook endpoint** (`src/stripe_webhooks/`) plus the two members-router
card endpoints that call these primitives (§9).

All services are registered in `core/dependencies.py`: `PaymentsStripeClient` is
a **Singleton**; every wrapper service and every webhook handler is a `Factory`.

---

## 2. Stripe Connect — account scoping, idempotency, metadata pinning

Every gym is a Stripe **Express connected account**. Two columns on `gyms.sql`
carry the link (both `service_role`-write-only — `REVOKE UPDATE (gym_id,
stripe_account_id, stripe_onboarding_status)` in `access_rules/gyms.sql`):

| column | meaning |
| --- | --- |
| `stripe_account_id` | `TEXT UNIQUE` — the connected account id (`acct_…`); NULL until onboarded |
| `stripe_onboarding_status` | Postgres enum `stripe_onboarding_status` `NOT NULL DEFAULT 'not_started'` ∈ `not_started` / `pending` / `complete` / `disabled` (mirrored by the `StripeOnboardingStatus` `StrEnum` in `Database/python_data/schema/gym.py`) |

**Everything is connected-account scoped.** There are no platform-level Stripe
resources — every customer, product, price, coupon, subscription, and invoice
lives under a gym's connected account. That scoping is carried on every call as
`stripe.RequestOptions` built by `PaymentsStripeClient`
(`payments_stripe_client.py`):

- `connect_opts(stripe_account_id, *, idempotency_key=None)` — a **write** call.
  **Money-moving flows** (invoices, charges, subscription create/update/cancel/
  freeze, refunds) **must pass an idempotency key** so Stripe dedups retries at
  the protocol level. Non-money-moving writes (product / price / coupon /
  customer CRUD) may omit it.
- `connect_opts_readonly(stripe_account_id)` — a **read** call (retrieve / list /
  preview); no idempotency key is meaningful.

Every public service method takes `stripe_account_id` and threads it into the
opts. The `PaymentsStripeClient` itself is constructed from the platform secret
key (`stripe.StripeClient`) and is the single shared client.

### Metadata pinning — every Stripe resource carries its CRM id

Each Stripe resource we create is written with a **typed metadata envelope** so
an inbound event can be correlated back to CRM rows. All models subclass
`BaseStripeMetadata` (`schema/metadata/stripe_metadata_base.py`,
`extra="forbid"`): `to_stripe_metadata()` serializes to Stripe's `dict[str,str]`
(UUIDs → str, bools → `"true"`/`"false"`, `None` dropped) and
`from_stripe_metadata()` parses it back, coercing bools.

| model (file in `schema/metadata/`) | written on | pinned fields |
| --- | --- | --- |
| `StripeCustomerMetadata` | customer create/update | `member_id`, `gym_id` |
| `StripeProductMetadata` | membership product create/update | `plan_id`, `gym_id` |
| `StripePriceMetadata` | price create | `crm_price_id`, `plan_id`, `gym_id` |
| `StripeSubscriptionMetadata` | sub create/update/freeze/migration | `member_id`, `gym_id`, `crm_paid_with_cash` (default `False`) |
| `StripeMembershipOneTimeMetadata` | one-time membership invoice | `member_id`, `gym_id`, `plan_id`, `crm_one_time_payment=True`, `type="membership_one_time"`, `crm_paid_with_cash` |
| `StripeAdHocInvoiceMetadata` | ad-hoc charge-card invoice | `member_id`, `gym_id`, `crm_one_time_payment=True`, `crm_paid_with_cash` |

The metadata is the **write-side guard**; the webhook is a pure reader and pulls
only a small set of flow-control keys off the raw envelope (§6).

---

## 3. The non-subscription service primitives

Each is one focused wrapper class in `src/payments/service/`. All raise the
`payments_exceptions.py` hierarchy: `PaymentsStripeError` (base),
`PaymentsResourceNotFoundError` (carries `resource_id` + a `StripeResourceType`),
`PaymentsInvalidRequestError`, and `StripeOrphanError` (a Stripe resource was
created but the CRM writeback failed — surfaced loudly for operator cleanup).

**`PaymentsStripeMembersService`** (`payments_stripe_members_service.py`) — Stripe
**Customer + PaymentMethod**:

- `create_customer` — customer (optionally with a payment method set as the
  invoice-settings default).
- `update_customer` — updates details and **swaps the card**: attaches the new
  PaymentMethod, sets it default, then **detaches the old** one.
- `unlink_customer_card` — clears the default PaymentMethod and detaches it
  (no-op if the customer is gone).
- `retrieve_customer` — raises `PaymentsResourceNotFoundError` if missing/deleted.
- `list_invoices` — paginates a customer's invoices (`starting_after`);
  `_extract_subscription_id` handles both legacy and new (`parent.
  subscription_details.subscription`) Stripe shapes.

**`PaymentsStripeMembershipService`** (`payments_stripe_membership_service.py`) —
a membership plan as a Stripe **Product + Prices**:

- `create_membership` — Product + each Price (delegates Price creation to the
  price service), sets `default_price`.
- `update_membership` — reconciles prices: re-activates an archived existing
  price + creates new ones. **It never deactivates a Stripe price** — the DB
  (`membership_plan_prices.is_active`) gates which price is current, so every
  Stripe price stays active forever (archiving the old price would break a
  subscription migration that's mid-flight). `deactivate_price` is therefore now
  **uncalled** (kept as a low-level primitive).
- `deactivate_membership` — archives the Product (`active=False`); does not
  cancel subscriptions.

**`PaymentsStripePriceService`** (`payments_stripe_price_service.py`) — Stripe
**Price** ops: `create_price` (recurring when `plan_type == PlanType.recurring`),
`get_price`, `deactivate_price` / `activate_price`, `set_product_default_price`
(must run before archiving the previous default — Stripe rejects archiving a
product's current `default_price`), and `validate_price_active` (retrieve the
price + its product and **reactivate either if archived** — the gym owner is
explicitly trying to use it).

**`PaymentsStripePaymentService`** (`payments_stripe_payment_service.py`) —
one-time charges, all money-moving (per-step idempotency keys
`{base}:invoice`/`:invoice_item`/`:finalize`/`:pay`):

- `create_invoice_payment` — invoice from a **Stripe Price**.
- `create_invoice_payment_by_amount` — **ad-hoc amount** invoice (no Price; late
  fees, pro-shop). `description` lands on both invoice and line item.
- `preview_invoice_payment` — dry-run preview (may defensively reactivate an
  archived price).
- `refund_payment` — refund a PaymentIntent (full or partial).
- `pay_open_subscription_invoice_out_of_band` — find the subscription's single
  open invoice, stamp `crm_paid_with_cash="true"` on it, and `invoices.pay` with
  `paid_out_of_band=True`. Stripe then fires the normal `invoice.paid` webhook,
  which does the CRM write. (Note: Stripe does not propagate subscription
  metadata to generated invoices, so the webhook recovers `member_id` via
  sub-item lookup; only the cash flag rides on the invoice itself.)

**`PaymentsStripeDiscountService`** (`payments_stripe_discount_service.py`) — the
**single owner of low-level Stripe Coupon I/O**: `find_discount(coupon_id,
account)` (retrieve-or-`None`, the non-raising lookup), `create_discount` (creates
under a **caller-supplied deterministic `coupon_id`**; idempotent — a create race
on the same id returns the existing coupon), `delete_discount`, and
`retrieve_discount` (raises; used by the subscription coupon-validation path).
Coupons carry **no CRM back-reference metadata** — a value-coupon is shared across
every discount at that value, so there is nothing to back-reference. The
**deterministic id scheme + validate-or-replace policy** (the
value signature `pct_<bps>_<mode>` / `amt_<cents>_<mode>`) lives in
`PaymentSyncCoupons` (`sync-guide`), which **delegates all coupon I/O here** — no
service outside this payments layer touches the Stripe SDK. The
`StripeCouponDuration` enum (`once` / `repeating` / `forever`) lives in
`schema/payments_enums.py`.

**`payments_stripe_mappers.py`** — a class-less concern module (free functions by
design): `map_invoice_preview`, `map_upcoming_invoice`, and the line-item helpers
(`_post_discount_amount` computes `subtotal − Σ discount_amounts` itself rather
than trusting `line.amount`; `_extract_subscription_item_id` / `_is_proration`
handle legacy vs. `parent`-nested Stripe shapes).

---

## 4. The subscription sub-services (facade + delegates + read primitive)

Subscriptions are split across `src/payments/service/subscription/`. The public
API is the **facade** `PaymentsStripeSubscriptionService`
(`payments_subscription_facade.py`), which constructs each delegate from the same
four deps (`stripe_client`, `members_service`, `price_service`,
`discount_service`) and forwards every public method. All delegates extend
`PaymentsSubscriptionBase` (`payments_subscription_base.py`), which holds the
shared deps and the static/instance helpers.

| facade method | delegate (file) | does |
| --- | --- | --- |
| `create_subscription` / `preview_create_subscription` | `PaymentsSubscriptionCreate` (`_create`) | new sub (flexible billing mode), monthly/weekday anchor, optional first-invoice out-of-band |
| `update_subscription` / `preview_update_subscription` | `PaymentsSubscriptionUpdate` (`_update`) | reconcile a sub to a desired item/discount set |
| `cancel_subscription` | `PaymentsSubscriptionCancel` (`_cancel`) | cancel now or at period end; no-op if already `canceled` |
| `freeze_subscription` / `unfreeze_subscription` | `PaymentsSubscriptionFreeze` (`_freeze`) | `pause_collection` (`behavior="void"`, optional `resumes_at`) / resume with `billing_cycle_anchor="unchanged"` |
| `migrate_subscriptions_to_price` | `PaymentsSubscriptionMigration` (`_migration`) | sequential price migration across subs |
| `fetch_upcoming_invoice` | `PaymentsSubscriptionUpcoming` (`_upcoming`) | next-invoice preview via `invoices.create_preview(subscription=…)` |
| `get_subscription` | `PaymentsSubscriptionRetrieve` (`_retrieve`) | **read current items + discounts** (the sync's read primitive) |
| `get_subscription_item` | `PaymentsSubscriptionItem` (`_item`) | retrieve one sub-item (validates its parent isn't canceled) |

### `get_subscription` — the read-current-coupons primitive

`get_subscription` (`payments_subscription_retrieve.py`) is **read-only** and is
the new path the sync depends on. The old push path only ever *wrote* desired
state to Stripe; this reads it back. **The retrieve expands
`items.data.discounts`** so each item discount comes back as a `Discount` object
(not a bare `di_…` id), and the mapped response carries each item's
currently-attached coupon ids (`items[*].discounts`) **and** the
subscription-level coupon ids (`discounts`). `sync-guide` reads these to run the
`once`-consumption gate (a stored coupon still present = pending; absent = Stripe
already invoiced it). Do not duplicate that gate logic here — this guide only
exposes the read.

### Base helpers (the load-bearing primitives)

`PaymentsSubscriptionBase` (`payments_subscription_base.py`):

- `_map_subscription(sub)` → `PaymentsSubscriptionResponse` — exposes **both**
  item-level coupon ids (`PaymentsSubscriptionItemResponse.discounts`) **and**
  sub-level coupon ids (from `sub.discounts`), via the `_coupon_id_from_discount`
  helper. A subscription-item `Discount` exposes its coupon at
  **`discount.source.coupon`** (a coupon-id string) in the current Stripe shape —
  `discount.coupon` is null — so the helper reads `source.coupon` first, falling
  back to the legacy `discount.coupon` object; a bare unexpanded `di_…` string is
  skipped (the retrieve expands the discounts so this doesn't happen on the read
  path). This is what surfaces the live coupon set the sync unions.
- `_consolidate_items(items)` — Stripe allows one item per price, so duplicate
  price ids are merged: quantities summed, coupon ids de-duplicated.
- `_build_create_items` / `_build_reconcile_items` / `_build_reconcile_entry` —
  turn desired items into Stripe item dicts. Reconcile matches desired items to
  current Stripe items by `stripe_item_id`; an unmatched id raises
  `PaymentsResourceNotFoundError` (`subscription_item`, "Stripe may be out of
  sync"); current items not referenced are emitted as `{"id": …, "deleted": True}`.
- `_retrieve_subscription` — raises `PaymentsResourceNotFoundError` if missing
  **or `status == "canceled"`**.
- `_validate_subscription_request` / `_validate_coupon_ids` — pre-validate all
  prices (single shared recurring interval) and coupons exist before writing.

---

## 5. Webhooks — ingestion, signature, dedup, dispatch

The inbound mirror is `src/stripe_webhooks/`.

**Router** (`stripe_webhooks_router.py`): `POST /api/v1/stripe/webhooks`
(prefix `/api/v1/stripe`, response `StripeWebhookAck`). The endpoint is
**unauthenticated at the HTTP layer** — Stripe is authenticated by verifying the
`Stripe-Signature` header against `settings.stripe_connect_webhook_secret` via
`stripe.Webhook.construct_event`. Missing/invalid signature or bad payload → **400**.
The verified event is `to_dict()`'d and dispatched to
`StripeWebhooksService.handle_event`. On `SubscriptionItemPendingError` the router
returns **200** and schedules `service.retry_pending_event` as a FastAPI
background task; on any other handler exception it returns **500** so Stripe
retries.

**Service** (`stripe_webhooks_service.py`): `StripeWebhooksService.handle_event`:

1. Pulls `event.id` / `event.type` / `event.account` (the connected account id).
   No `account` → platform-level event → logged + ignored.
2. **Resolves the gym** from the account (`gym_by_stripe_account.sql` →
   `gyms.stripe_account_id`); unknown account → logged + ignored.
3. Opens **one transaction** (`session.begin()`) and records the event via
   `StripeWebhookEventLog.record` → `stripe_webhook_events_insert.sql`
   (`INSERT … ON CONFLICT (event_id) DO NOTHING RETURNING event_id`). A duplicate
   returns no row → `is_new = False` → **skip** (idempotent). The event-log insert
   and every handler write **commit or roll back together**, so a Stripe retry
   after a handler failure re-runs the whole thing cleanly.
4. `_dispatch` routes by `event.type` to one of the four handlers; unknown types
   return silently.

`retry_pending_event` re-runs `handle_event` up to 3 times with a 10s delay (used
for the sub-item race below).

---

## 6. The four handlers — exactly what each writes

Only **four** event types are registered (constants in
`stripe_webhooks_service.py`). Each handler is a `Factory` in the DI container.
Shared helpers: `dump_stripe_payload` (`stripe_json.py`, JSON with a `Decimal→
float` fallback so an audit write can never crash a webhook) and `stripe_time.py`
(`stripe_ts_to_datetime` / `stripe_ts_to_date`). The raw Stripe payload is stored
into the `stripe_event_payload JSONB` column on every invoice/charge write.

**`invoice.paid` → `InvoicePaidHandler`** (`invoice_paid_handler.py`) writes:

- **`member_invoices`** — upsert to `status='paid'` (`member_invoice_upsert.sql`,
  `ON CONFLICT (stripe_invoice_id) DO UPDATE`), returning `invoice_id`.
- **`member_memberships`** — for each billed sub-item, updates `last_paid_date` +
  `next_due_date` (`member_memberships_update_payment_dates.sql`, writes to
  `member_memberships_unfiltered`). **Skipped for one-time invoices.**
- **`member_charges`** — one `kind='payment'`, `status='succeeded'` row
  (`member_charge_insert.sql`).

Member resolution: one-time invoices carry `member_id` directly in metadata
(gated on `crm_one_time_payment="true"`); subscription invoices resolve by
matching a line's `subscription_item` against `member_memberships`
(`membership_by_stripe_item.sql`). If no member resolves **and** lines reference
sub-items, it raises **`SubscriptionItemPendingError`** (the create-flow hasn't
committed `stripe_item_id` yet) → 200 + background retry. The cash path
(`crm_paid_with_cash="true"`) sets `payment_method_type='cash'` and bypasses the
`stripe_charge_id IS NOT NULL` charge guard; a zero-amount paid invoice with no
charge id simply skips the charge insert.

> **Not written here.** This handler does **not** populate
> `member_invoice_line_items` or `member_invoice_applied_discounts` — those tables
> exist (§7) but the current handlers only write invoices / charges / membership
> dates. Do not assert a line-item or applied-discount writeback from the webhook;
> there is none in source today.

**`invoice.payment_failed` → `InvoicePaymentFailedHandler`**
(`invoice_payment_failed_handler.py`) writes:

- **`member_invoices`** — upsert to `status='open'`.
- **`member_charges`** — one `kind='payment'`, `status='failed'` row with
  `stripe_charge_id=NULL` (so retries of the same attempt don't collide on the
  UNIQUE constraint; the outer event-log dedup prevents double inserts).

Nothing on the membership row is mutated — Stripe owns dunning; the CRM surfaces
failures by querying `member_charges WHERE status='failed'`. Same
`SubscriptionItemPendingError` race handling as above.

**`charge.refunded` → `ChargeRefundedHandler`** (`charge_refunded_handler.py`)
writes:

- **`member_charges`** — one `kind='refund'`, `status='succeeded'`,
  **negative** amount row **per refund in `refunds.data`**, linked to its parent
  payment via `refunds_charge_id` (looked up by `stripe_charge_id` +
  `kind='payment'` via `member_charge_by_stripe_charge_id.sql`).

If no parent payment row exists it **logs an error and acks** (can't insert a
refund — `invoice_id` is NOT NULL — needs manual reconciliation, not a retry).

**`account.updated` → `AccountUpdatedHandler`** (`account_updated_handler.py`)
writes:

- **`gyms.stripe_onboarding_status`** (`gyms_set_onboarding_status.sql`; does not
  touch `stripe_account_id`).

It delegates to the single canonical mapper `map_account_to_snapshot`
(`gyms/service/gyms_status_mapping.py`) — the same one the gyms status-refresh
endpoint uses, returning a Pydantic `GymStripeAccountSnapshot`
(`gyms/schema/gyms_schema.py`). Precedence: `requirements.disabled_reason` set →
`disabled`; `details_submitted && charges_enabled && payouts_enabled` →
`complete`; else `pending`. `disabled` is a real value of the
`stripe_onboarding_status` enum, so it persists to the column; the CRM gym-setup
flow renders a dedicated disabled step from it. The mapper normalizes a
`stripe.Account` to a plain dict via `.to_dict()` at the boundary, so the webhook
(dict payload) and the refresh path (SDK object) share one code path.

---

## 7. The invoice / charge data model

Five `service_role`-write-only billing tables in
`Database/supabase/schemas/`. All `REVOKE INSERT, UPDATE … FROM authenticated`;
SELECT is allowed via an RLS policy (member sees own, gym staff see their gym's).
Their `immutable_columns.py` frozensets exist
(`MEMBER_INVOICES`, `MEMBER_CHARGES`, `MEMBER_INVOICE_LINE_ITEMS`,
`MEMBER_INVOICE_APPLIED_DISCOUNTS`, `STRIPE_WEBHOOK_EVENTS`, `GYMS`).

**`member_invoices`** — the bill, one row per Stripe invoice (or a manual cash
invoice). Column `status` (enum `invoice_status`) ∈ `open` / `paid`. `total_amount INTEGER CHECK
(>= 0)`. `stripe_invoice_id` / `stripe_payment_intent_id` are `UNIQUE` and
nullable (cash). `stripe_event_payload JSONB`. Composite `UNIQUE (invoice_id,
gym_id)` is the FK target for children; member FK is composite `(member_id,
gym_id)`.

**`member_charges`** — money movement (payments **and** refunds). Column `kind`
(enum `charge_kind`) ∈ `payment` / `refund`; column `status` (enum
`charge_status`) ∈ `pending` / `succeeded` / `failed`.
`amount INTEGER` is **signed**. `stripe_charge_id` / `stripe_refund_id` both
`UNIQUE`; `refunds_charge_id` is a self-FK to the refunded payment row. The CHECK
constraints (the contract):

| constraint | rule |
| --- | --- |
| `payment_amount_nonneg` | payment → `amount >= 0` |
| `payment_has_charge_id` | payment → `stripe_charge_id IS NOT NULL` **OR** `payment_method_type = 'cash'` |
| `payment_has_no_refund_id` | payment → `stripe_refund_id IS NULL` |
| `payment_has_no_parent` | payment → `refunds_charge_id IS NULL` |
| `refund_amount_nonpos` | refund → `amount <= 0` |
| `refund_has_refund_id` | refund → `stripe_refund_id IS NOT NULL` |
| `refund_has_parent` | refund → `refunds_charge_id IS NOT NULL` |
| `refund_has_no_charge_id` | refund → `stripe_charge_id IS NULL` |

`member_charge_insert.sql` is `ON CONFLICT DO NOTHING RETURNING charge_id`.

**`member_invoice_line_items`** — what's on the bill. PK `line_item_id VARCHAR`
**reuses the Stripe line-item id (`il_…`)** directly — line items always
originate from Stripe, so reusing the id gives free idempotency with no mapping
layer. Column `item_type` (enum `line_item_type`) ∈ `membership` / `custom`. `name CHECK (<> '')` is a
frozen historical label; `amount CHECK (>= 0)`. `item_id` (→
`member_memberships_unfiltered`) is set **only** for membership lines
(`membership_line_has_item_id` / `custom_line_has_no_item_id`).

**`member_invoice_applied_discounts`** — a **billing AUDIT trail**, not a
system-of-record. One row = a discount applied to one invoice: `discount_id` (FK
→ `gym_discounts_unfiltered`), `amount_off INTEGER CHECK (>= 0)` (the **dollar
value snapshotted at invoice time** — the underlying discount may change later),
and `stripe_coupon_id`. **This is explicitly distinct from
`member_membership_applied_discounts`** (the slim, versioned snapshot that pins a
membership to a discount *value version* — owned by `discounts-guide`). This
audit table records *what a specific invoice actually charged*; that snapshot
table records *what a membership is currently entitled to*. Do not conflate them.

**`stripe_webhook_events`** — the idempotency log. PK `event_id VARCHAR`;
`gym_id`, `event_type`, `processed_at`. `REVOKE ALL … FROM authenticated`
(service-role only, no SELECT policy). `ON CONFLICT (event_id) DO NOTHING` is the
dedup primitive (§5).

---

## 8. The Stripe-gated completion pattern (where it does and doesn't apply)

The codebase has a `hide_incomplete_stripe_records` pattern: an unfiltered base
table + a `security_invoker` filtered view that exposes only rows whose Stripe id
is set, so records that start *incomplete* (created with a NULL Stripe id, later
completed by the sync or a webhook) are never surfaced to clients while pending.

**That `_unfiltered`/filtered-view pattern is used by the *sibling*-owned tables**
— `member_memberships`, `member_membership_applied_discounts`,
`membership_plans`, `membership_plan_prices` (`memberships-guide` /
`discounts-guide`) and `gym_discounts` / `gym_discount_values`
(`discounts-guide`).

**The invoice/charge billing tables this guide owns do NOT use it.**
`member_invoices`, `member_charges`, `member_invoice_line_items`,
`member_invoice_applied_discounts`, and `stripe_webhook_events` are gated by
`REVOKE INSERT, UPDATE` (or `REVOKE ALL`) plus a direct SELECT RLS policy on the
base table — there is no `_unfiltered` base + filtered view for them (verified: no
`hide_incomplete_stripe_records` and no `*_unfiltered` view in their
`access_rules/`). They don't need it: a row is only inserted by a handler **after**
Stripe has already produced the outcome, so it is never in a half-written
Stripe-incomplete state. Don't claim these tables hide incomplete records.

---

## 9. Endpoints that touch payments

This guide owns the inbound webhook endpoint plus the two members-router card
endpoints that call the §3 primitives (the members router otherwise belongs to
its own domain):

| method + path | calls into |
| --- | --- |
| `POST /api/v1/stripe/webhooks` | the webhook ingestion (§5–§6) |
| `PUT /api/v1/members/{member_id}/card` | `update_card` → `PaymentsStripeMembersService.update_customer` (card swap only; raises if the member has no Stripe customer — `create_customer` runs once at member creation, never here) |
| `DELETE /api/v1/members/{member_id}/payment` | `unlink_payment` → `unlink_customer_card` + cancel recurring subs (Stripe customer link preserved) |

The subscription / invoice / refund primitives have **no direct endpoint** — they
are called by the sync engine and the membership/members/plans services
(`sync-guide` / `memberships-guide` own those call sites).

---

## Key files (where the layer actually lives)

- **Client + opts:** `FastApiBackend/src/payments/service/payments_stripe_client.py`
  (`PaymentsStripeClient`, `connect_opts` / `connect_opts_readonly`).
- **Exceptions / enums:** `payments/payments_exceptions.py`,
  `payments/schema/payments_enums.py` (`StripeCouponDuration`,
  `StripeResourceType`).
- **Metadata models:** `payments/schema/metadata/` (`stripe_metadata_base.py` +
  the six per-resource models). Coupons have no metadata model — a value-coupon
  is shared across every discount at that value, so it carries no CRM
  back-reference.
- **Non-subscription services:** `payments/service/payments_stripe_members_service.py`,
  `payments_stripe_membership_service.py`, `payments_stripe_price_service.py`,
  `payments_stripe_payment_service.py`, `payments_stripe_discount_service.py`
  (the single owner of low-level coupon find/create/delete — sync delegates here),
  `payments_stripe_mappers.py`.
- **Subscription sub-services:** `payments/service/subscription/`
  (`payments_subscription_facade.py` = `PaymentsStripeSubscriptionService`,
  `payments_subscription_base.py`, and the create/update/cancel/freeze/migration/
  upcoming/retrieve/item delegates). `payments_subscription_retrieve.py` holds
  `get_subscription`.
- **Webhook router:** `payments/`… no router — the only router is
  `src/stripe_webhooks/stripe_webhooks_router.py` (`POST /api/v1/stripe/webhooks`).
- **Webhook service + handlers:** `src/stripe_webhooks/service/`
  (`stripe_webhooks_service.py`, `event_log.py`, `invoice_paid_handler.py`,
  `invoice_payment_failed_handler.py`, `charge_refunded_handler.py`,
  `account_updated_handler.py`, `stripe_json.py`, `stripe_time.py`);
  exceptions in `stripe_webhooks_exceptions.py` (`SubscriptionItemPendingError`).
- **Webhook SQL:** `src/stripe_webhooks/sql/` (`gym_by_stripe_account.sql`,
  `stripe_webhook_events_insert.sql`, `member_invoice_upsert.sql`,
  `member_charge_insert.sql`, `member_charge_by_stripe_charge_id.sql`,
  `membership_by_stripe_item.sql`, `member_memberships_update_payment_dates.sql`,
  `gyms_set_onboarding_status.sql`).
- **Schema:** `Database/supabase/schemas/member_invoices.sql`,
  `member_charges.sql`, `member_invoice_line_items.sql`,
  `member_invoice_applied_discounts.sql`, `stripe_webhook_events.sql`, `gyms.sql`
  (the `stripe_account_id` / `stripe_onboarding_status` columns). Access rules in
  the parallel `access_rules/` files.
- **DI wiring:** `src/core/dependencies.py` (`stripe_client` Singleton; all
  wrapper services + webhook handlers as Factories; `stripe_webhooks_service`).
- **Members card endpoints:** `src/members/members_router.py`
  (`PUT /{member_id}/card`, `DELETE /{member_id}/payment`).
- **Design rationale (prose):** `FastApiBackend/PaymentRefactor.md` §1–§4.

### Seams to sibling skills (reference, don't duplicate)

- **`sync-guide`** — owns the engine that computes desired subscription state and
  the sync-time coupon find-or-create (`PaymentSyncCoupons`,
  `payment_sync_builder`); it *consumes* `get_subscription` (§4) and the §3/§4
  write primitives.
- **`discounts-guide`** — owns the discount system-of-record
  (`gym_discounts` / `gym_discount_values` / `member_membership_applied_discounts`)
  and coupon semantics. Distinct from the §7 invoice audit table.
- **`memberships-guide`** — owns plan/membership creation that *calls* the §3/§4
  primitives (Stripe Product/Price/subscription creation paths).

---

## This is a living document

This skill is the single source of truth for the Stripe integration layer.
Whenever it genuinely changes — a new webhook event type or handler, a new
service primitive or method, a new metadata model, a changed CHECK constraint or
column on the invoice/charge tables, a new endpoint that calls these primitives,
the `disabled` status mismatch getting resolved, or a renamed service/SQL file —
**update this skill in the same change** so it never goes stale.
