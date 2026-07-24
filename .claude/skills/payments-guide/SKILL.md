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
  (`PaymentsStripeSubscriptionService` facade + create/update/cancel/migration/
  upcoming/retrieve/item delegates + `get_subscription` read primitive +
  `_map_subscription` / `_consolidate_items` / `_build_reconcile_items` base
  helpers), plus the webhook ingestion (`/api/v1/stripe/webhooks` → signature
  verify → `StripeWebhooksService.handle_event` → gym resolution → `event_log` +
  `stripe_webhook_events` dedup → the handlers `invoice.paid` /
  `invoice_payment.paid` / `invoice.payment_failed` / `refund.created`+`refund.updated`
  / `account.updated`) and the invoice/charge data model (`member_invoices`,
  `member_charges`, `member_invoice_line_items`, `member_invoice_applied_discounts`).
  Trigger on "Stripe", "connect account", "stripe_account_id", "connect_opts",
  "idempotency key", "webhook", "invoice.paid", "invoice_payment.paid", "refund",
  "charge.refunded", "account.updated",
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
work here" rules. The config-vs-outcomes split this layer rests on is documented
in §1 here and in the **`sync-guide`** skill; `FastApiBackend/PaymentRefactor.md`
is only the engine's remaining-work roadmap, not rationale. When this layer
changes, **update this skill in the same change** (it is a living document — see
the bottom).

This layer is a set of **primitives**, not a brain. It knows *how* to push a
desired state to Stripe and *how* to record a Stripe event — it does **not**
decide *what* the desired state should be. The engine that computes desired
subscription state and the sync-time coupon set is owned by `sync-guide`; the
discount system-of-record model is owned by `discounts-guide`; plan/membership
creation that *calls* these primitives is owned by `memberships-guide`. Stay
inside the seam: this guide stops at the Stripe boundary.

---

## 1. Role — config vs. outcomes, and a pure service layer

Two kinds of "truth" are split deliberately:

- **CRM owns config / intent** — prices, plans, discounts, who is enrolled.
  These originate in the CRM and are *pushed* to Stripe. No member self-serves
  via a Stripe-hosted portal, so config never starts on Stripe's side.
- **Stripe owns outcomes** — did the invoice clear, card declines, refunds,
  actual billing dates, the dunning lifecycle, and connected-account onboarding
  state. These are *mirrored back* into the CRM via `src/stripe_webhooks/`.

`src/payments/` is a **pure service layer: it has no router** (verified — there
is no `*_router.py` under `src/payments/`). Its services are consumed by the
sync engine (`src/sync/service/`) and by the
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
  **Money-moving flows** (invoices, charges, subscription create/update/cancel,
  refunds) **must pass an idempotency key** so Stripe dedups retries at
  the protocol level. Non-money-moving writes (product / price / coupon /
  customer CRUD) may omit it.
- `connect_opts_readonly(stripe_account_id)` — a **read** call (retrieve / list /
  preview); no idempotency key is meaningful.

Every public service method takes `stripe_account_id` and threads it into the
opts. The `PaymentsStripeClient` itself is constructed from the platform secret
key (`stripe.StripeClient`) and is the single shared client.

**The client tokenizes on the connected account too — because attach is
connected-account-scoped.** A member's card is attached to a customer that lives
on the gym's connected account (`create_customer` / `update_customer` /
`attach_payment_method` all use `connect_opts(stripe_account_id)`), so the
PaymentMethod the browser tokenizes must ALSO be minted on that connected
account — a platform-owned `pm_…` cannot attach to a connected-account customer
(Stripe raises `InvalidRequestError: … a platform-owned payment method ID`).
So the CRM/kiosk sets the Stripe.js connected-account context before any card
field mounts: `GET /api/v1/gyms/` exposes `stripe_account_id` on
`GymWithRoleResponse` (the authenticated staff read — the `acct_…` id is
client-safe, it rides in the browser in every Connect direct-charge
integration), and the client sets `Stripe.stripeAccountId` + `applySettings()`
from it when the active gym is established. The regression guard
`tests/members/test_members_card_platform_pm_guard.py` locks the attach-side
invariant (a platform-minted pm → `update_customer` raises). (Stripe's magic
`pm_card_visa` test token crosses accounts, which is why the seed never
surfaced this — a genuinely browser-tokenized card does not cross.)

### Metadata pinning — every Stripe resource carries its CRM id

Each Stripe resource we create is written with a **typed metadata envelope** so
an inbound event can be correlated back to CRM rows. All models subclass
`BaseStripeMetadata` (`schema/metadata/stripe_metadata_base.py`,
`extra="forbid"`): `to_stripe_metadata()` serializes to Stripe's `dict[str,str]`
(UUIDs → str, bools → `"true"`/`"false"`, **list fields → a JSON-array string**
so e.g. `paid_for` rides as `'["<uuid>", …]'`, `None` dropped) and
`from_stripe_metadata()` parses it back, coercing bools and JSON-decoding lists.

| model (file in `schema/metadata/`) | written on | pinned fields |
| --- | --- | --- |
| `StripeCustomerMetadata` | customer create/update | `member_id`, `gym_id` |
| `StripeProductMetadata` | membership product create/update | `plan_id`, `gym_id` |
| `StripePriceMetadata` | price create | `crm_price_id`, `plan_id`, `gym_id` |
| `StripeSubscriptionMetadata` | sub create/update/migration | `member_id`, `gym_id`, `crm_paid_with_cash` (default `False`) |
| `StripeMembershipOneTimeMetadata` | one-time membership invoice (invoice-level) | `member_id` (bill owner / payer), `gym_id`, `plan_id` (**optional** — `None` on a consolidated multi-plan invoice), `crm_one_time_payment=True`, `type="membership_one_time"`, `crm_paid_with_cash` |
| `StripeAdHocInvoiceMetadata` | ad-hoc charge-card invoice | `paid_by_member_id` (payer), `paid_for` (beneficiary list, JSON-array string), `gym_id`, `crm_one_time_payment=True`, `crm_paid_with_cash` |

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
- `attach_payment_method` / `detach_payment_method` — attach a PaymentMethod to a
  customer **without** making it default, and detach one (both idempotency-keyed).
  Used by the one-off-card charge path (`create_invoice_payment` with a
  `payment_method_id`): a card the member entered for this purchase only is
  attached, charged, then detached — the saved default is untouched. Attach is a
  no-op when the method is already attached (so a retry is safe); a detached
  method can **never** be re-attached, so the charge path detaches only AFTER a
  successful pay.
- `has_attached_payment_method` — the read-only existence probe: lists the
  customer's attached PaymentMethods (**all types**, no `type` filter, `limit=1`
  since only existence is asked) and returns whether that list is non-empty. It
  is the LIVE Stripe answer, deliberately not `members.stripe_payment_method_id`
  (which records only the CRM's last saved default, so a method attached out of
  band would leave it NULL). **A Stripe failure propagates — callers gate on
  this, so an error must never degrade to "no card".** Called by
  `MembersManagementPaymentMethods` behind
  `GET /api/v1/members/{member_id}/payment-method-status`.
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
  subscription migration that's mid-flight). The thing we never want here: our
  own code archiving a price — so there is deliberately **no `deactivate_price`**;
  the only direction is reactivation.
- `deactivate_membership` — archives the Product (`active=False`); does not
  cancel subscriptions.

**`PaymentsStripePriceService`** (`payments_stripe_price_service.py`) — Stripe
**Price** ops: `create_price` (recurring when `plan_type == PlanType.recurring`),
`get_price`, `set_product_default_price` (must run before archiving the previous
default — Stripe rejects archiving a product's current `default_price`), and the
two **reactivation** guards — `activate_price` (used by the plan reconcile) and
`validate_price_active` (retrieve the price + its product and **reactivate either
if archived**; called on the charge / subscription-create / migration paths right
before price-attach). These defend against a price archived *out of band* —
manually in the Stripe Dashboard, or a legacy price: our code never archives one,
but Stripe rejects attaching an archived price to a subscription, so they flip it
back to active because the DB says it's current.

**`PaymentsStripePaymentService`** (`payments_stripe_payment_service.py`) —
**itemized** invoice charges, all money-moving (per-step idempotency keys
`{base}:invoice`/`:invoice_item:{i}`/`:finalize`/`:pay`):

- `create_invoice_payment` / `preview_invoice_payment` — **itemized**: ONE invoice
  from a **list of items** (`PaymentsInvoiceItemSpec`), each a **Stripe price XOR
  an ad-hoc amount** (late fees, pro-shop — exactly one set, model-validated) plus
  its own **item-level** discount coupons (`InvoiceItem.discounts`, not
  invoice-level — so each line is discounted independently). A **price** line may
  carry a **`quantity`** (a stacked one_time / trial pack billed as one line of N
  units — quantity multiplies the unit price, so a fixed-$ coupon applies once to
  the line; model-validated to stay 1 on an `amount` line, whose amount is already
  the total). A single charge is
  just a one-item list. The create response carries **`line_item_ids` AND
  `line_amounts`** in **request order** (each line mapped from its
  `parent.invoice_item_details.invoice_item`), so a caller maps each item → its
  Stripe line id (e.g. a membership → `stripe_item_id`) **and** its
  **post-discount** charged amount in cents (e.g. a membership's `total_price`) —
  no client math. The create request also takes an optional **invoice-level
  `description`** (the header line on the hosted invoice/receipt) — **distinct**
  from each item's per-line `description` (charge_card passes its `reason` here).
  Invoice-level `metadata` is any `BaseStripeMetadata` (membership-one-time or
  ad-hoc); a consolidated multi-plan invoice's
  `StripeMembershipOneTimeMetadata.plan_id` is `None`. **No price-active check** —
  prices are never deactivated. An optional **`payment_method_id`** charges a
  SPECIFIC one-off card (entered at checkout) instead of the customer's
  default: the `_pay_invoice` helper attaches it (`{base}:attach`), pays with it
  (`pay_params["payment_method"]`), then **always** detaches it (`{base}:detach`),
  never touching `invoice_settings.default_payment_method`. (Saving a card as the
  default is a separate up-front `update_customer` step, never this path — so a
  card passed here is always a one-off and always detached; there is no
  keep-attached option.) The detach runs ONLY after a successful pay (a declined
  pay leaves the card attached-but-non-default so a retry can reuse it) and is
  **best-effort** (a detach failure is logged, not raised — the invoice is
  already paid, so raising would wrongly read as a charge failure).
  `payment_method_id` is mutually exclusive with `paid_out_of_band`
  (model-validated). A `$0` invoice auto-pays at finalize and skips the pay step
  entirely, so a one-off card is never attached for a zero-total charge.
- `refund_payment` — refund a **charge** (full or partial), by the original
  `stripe_charge_id` (what `member_charges` stores and what the `refund.*`
  webhook keys on — no PaymentIntent lookup). The response carries the refund's
  `status` / `currency` / `created` so a caller can record the row without a
  second Stripe read.
- `pay_open_subscription_invoice_out_of_band` — find the subscription's single
  open invoice, stamp `crm_paid_with_cash="true"` on it, and `invoices.pay` with
  `paid_out_of_band=True`. Stripe then fires the normal `invoice.paid` webhook,
  which does the CRM write. (Note: Stripe does not propagate subscription
  metadata to generated invoices, so the webhook recovers `member_id` via
  sub-item lookup; only the cash flag rides on the invoice itself.)
- **Paginated list read-primitives** — `list_invoices(account_id, *, created_gte,
  limit, customer=None)`, `list_refunds(account_id, *, created_gte, limit)`,
  `list_invoice_payments(account_id, invoice_id, *, limit)`,
  `list_invoice_line_items(account_id, invoice_id, *, limit)`. Each auto-paginates
  (`_paginate`: loop `starting_after` / `has_more` under `connect_opts_readonly`)
  and returns a **list of plain nested dicts** — `json.loads(str(stripe_obj))`,
  the same shape the webhook event JSON has, since a listed `StripeObject` has no
  dict `.get`. These are the ONLY Stripe-list path: the on-demand / reconciler
  invoice fetch (`MemberMembershipsInvoiceFetch`, see `memberships-guide` /
  `reconciler-guide`) consumes them and never touches the Stripe client itself —
  keeping all raw Stripe I/O inside this layer.

**`PaymentsStripeDiscountService`** (`payments_stripe_discount_service.py`) — the
**single owner of Stripe Coupon I/O AND the deterministic value→coupon
find-or-create**. Low-level I/O: `find_discount(coupon_id, account)`
(retrieve-or-`None`, the non-raising lookup), `delete_discount`,
`retrieve_discount` (raises; used by the subscription coupon-validation path).
Coupon **creation has no public raw path** — it is the private
`_create_coupon(coupon_id, value)` owned by `find_or_create_for_value` (a coupon's
value *is* its deterministic id, so a coupon is only ever made through the
find-or-create; idempotent — a create race on the same id returns the existing
coupon). Coupons carry **no CRM
back-reference metadata** — a value-coupon is shared across every discount at that
value. The **deterministic-id + validate-or-replace policy** lives here too, in
**`find_or_create_for_value(PaymentsCouponValue, account) -> coupon_id`** (+ the
static `coupon_id_for_value`): the id is the value signature
`pct_<bps>` / `amt_<cents>` (`bps = round(percentage_off*100)`,
`cents = int(dollar_off)`), so the same value always resolves to one shared
coupon. An existing coupon is **validated** against the value (`_matches_value` on
amount + duration — Stripe coupons are immutable) and a mismatch is **deleted +
recreated** under the same id. All Stripe coupons are created as `forever` — the
arbitrary `end_date` cutoff is enforced by the applied-discount read, not by
Stripe. **This is shared infrastructure** — `PaymentSyncDiscounts.resolve`
(`sync-guide`) calls it for **both** the recurring sync **and** the one-time
engine `PaymentSyncOneTime` (which feeds it per-membership groups for the one-time
invoice), one value→coupon mechanism; nothing under `src/sync/` reimplements it.
The `StripeCouponDuration` enum (`once` / `repeating` / `forever`) lives in
`schema/payments_enums.py`.

**`payments_stripe_mappers.py`** — a class-less concern module (free functions by
design): the **single** preview mapper `map_preview_invoice` plus the line-item
helpers. **`post_discount_amount(line)` is public** (no underscore — the payment
service imports it to compute each itemized line's post-discount charged amount
for `line_amounts`); it computes `subtotal − Σ discount_amounts` itself rather
than trusting `line.amount`. `_extract_subscription_item_id` / `_is_proration`
(private) handle legacy vs. `parent`-nested Stripe shapes. It maps **any**
`create_preview` result (the proposed-change previews **and** the existing-sub
upcoming invoice — there is no separate `map_upcoming_invoice`) to one
**`PreviewInvoice`** of **`PreviewInvoiceLine`**, returning **every** line; a
consumer wanting only the steady-state recurring view filters on `is_proration`
/ `stripe_subscription_item_id` (the upcoming read does this in
`PaymentsSubscriptionUpcoming.fetch_upcoming`). Each line carries Stripe's **raw
`amount`** (`line.amount` — *pre*-discount on a subscription preview, not
repurposed) **and** the computed post-discount **`discounted_amount`**
(`post_discount_amount`), so a consumer reads the net directly with no client
math.

> **The mapper stays generic; the one-time preview filters its own lines.**
> `preview_invoice_payment` runs `invoices.create_preview` at the **customer
> level**, so for a payer with a live subscription Stripe previews the customer's
> *next* invoice — the staged ad-hoc invoice items **plus** the subscription's
> upcoming recurring lines — and the mapper (correctly) returns all of them. Its
> **sole** caller, `PaymentSyncOneTime.preview_one_time` (`sync-guide`), is a
> one-time-purchase preview, so it post-filters to **only** the pure
> invoice-item lines (those with `stripe_subscription_item_id is None` **and**
> `is_proration is False`) and **recomputes** `subtotal` / `total` /
> `amount_due` from the kept lines before returning. The filter lives in that
> caller, not here — the mapper is shared with the subscription/upcoming previews
> and must keep returning every line.

The one finalized-invoice model `PaymentsInvoiceResponse` (§7) is separate
and unchanged.

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
| `create_subscription` / `preview_create_subscription` | `PaymentsSubscriptionCreate` (`_create`) | new sub (flexible billing mode), monthly/weekday anchor, first charge verified synchronously (card → `error_if_incomplete`; cash → `default_incomplete` + first-invoice out-of-band) |
| `update_subscription` / `preview_update_subscription` | `PaymentsSubscriptionUpdate` (`_update`) | reconcile a sub to a desired item/discount set; card path sends `error_if_incomplete` so a declined proration 402s + rolls back |
| `cancel_subscription` | `PaymentsSubscriptionCancel` (`_cancel`) | cancel now or at period end; no-op if already `canceled` |
| `migrate_subscriptions_to_price` | `PaymentsSubscriptionMigration` (`_migration`) | sequential price migration across subs |
| `fetch_upcoming_invoice` | `PaymentsSubscriptionUpcoming` (`_upcoming`) | next-invoice preview via `invoices.create_preview(subscription=…)` |
| `get_subscription` | `PaymentsSubscriptionRetrieve` (`_retrieve`) | **read current items + discounts** (the sync's read primitive) |
| `get_subscription_item` | `PaymentsSubscriptionItem` (`_item`) | retrieve one sub-item (validates its parent isn't canceled) |

### Synchronous first-charge — `payment_behavior` (card vs. cash)

The at-the-desk charge a create / add produces is **verified synchronously**, so
a declining card **fails the operation** rather than reporting success while
Stripe silently dunns. The split is keyed on `pay_first_invoice_out_of_band`
(the cash flag the sync threads through, §sync-guide):

- **Create, card path** (`pay_first_invoice_out_of_band` False) →
  `payment_behavior="error_if_incomplete"`: Stripe 402s the create when the
  first invoice can't be paid and creates **no subscription** (verified: a
  declined create leaves zero subs + zero invoices on the customer). A
  `$0`/no-immediate-charge first invoice has nothing to collect, so it's a no-op
  there.
- **Create, cash path** (`pay_first_invoice_out_of_band` +
  `proration_behavior=prorate_to_anchor`) → `payment_behavior="default_incomplete"`
  + the existing `_pay_first_invoice_out_of_band` (mark the open first invoice
  paid out of band, no card charge). Unchanged.
- **Update, card path** (`pay_first_invoice_out_of_band` False) →
  `payment_behavior="error_if_incomplete"`: a proration charge the card can't
  cover 402s the update, and Stripe **rolls the item change back** (verified: the
  live sub keeps exactly its prior items) — so an add fails + reverts instead of
  leaving the member added behind an open unpaid proration invoice. The cash path
  (`pay_first_invoice_out_of_band` True) is **excluded**: its open proration
  invoice is settled later via `mark_paid_cash`, so it must not error. A
  `proration_behavior=no_charge` update generates no invoice → no-op.

> The `proration_behavior` on the subscription request schemas is the
> `ProrationBehavior` enum (`prorate_to_anchor` / `no_charge`) — the single
> vocabulary the request layer + sync engine speak. It is converted to Stripe's
> own `proration_behavior` string (`always_invoice` / `none`) ONLY at the SDK
> boundary, by `proration_behavior_to_stripe` in `payments_stripe_mappers.py`.

Only the monthly **renewals** after the first charge stay asynchronous (Stripe
dunning → the `invoice.payment_failed` webhook). The preview paths don't read
`payment_behavior` (they call `invoices.create_preview`), so setting it is inert
for previews.

### `get_subscription` — the read-current-coupons primitive

`get_subscription` (`payments_subscription_retrieve.py`) is **read-only** and is
the new path the sync depends on. The old push path only ever *wrote* desired
state to Stripe; this reads it back. **The retrieve expands
`items.data.discounts`** so each item discount comes back as a `Discount` object
(not a bare `di_…` id), and the mapped response carries each item's
currently-attached coupon ids (`items[*].discounts`) **and** the
subscription-level coupon ids (`discounts`). `sync-guide` uses these to verify
the live coupon state during convergence. Do not duplicate that logic here — this
guide only exposes the read.

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
  **Called on the create path only** (it returns the recurring interval, which
  create uses for the monthly `billing_cycle_anchor`). The **update** path no
  longer calls it: its return was discarded there and it looped a price+product
  retrieve over every item on the sub (2N wasted Stripe round-trips that grew
  with family size on each re-sync). On update the items are already-live or
  freshly added from already-validated memberships and the coupons were just
  find-or-created by the same sync; `_build_reconcile_items` still detects an
  out-of-sync `stripe_item_id`, and a genuinely bad price surfaces as a Stripe
  error on the update call. (Trade-off: the update path no longer
  auto-reactivates an archived price — create still does.)

---

## 5. Webhooks — ingestion, signature, dedup, dispatch

The inbound mirror is `src/stripe_webhooks/`.

**Router** (`stripe_webhooks_router.py`): `POST /api/v1/stripe/webhooks`
(prefix `/api/v1/stripe`, response `StripeWebhookAck`). The endpoint is
**unauthenticated at the HTTP layer** — Stripe is authenticated by verifying the
`Stripe-Signature` header against `settings.stripe_connect_webhook_secret` via
`stripe.Webhook.construct_event`. Missing/invalid signature or bad payload → **400**.
The verified event is `to_dict()`'d and dispatched to
`StripeWebhooksService.handle_event`. On a **`WebhookRetryableError`** (its
subclasses `SubscriptionItemPendingError` and `InvoiceNotYetRecordedError`) the
router returns **200** and schedules `service.retry_pending_event` as a FastAPI
background task; on any other handler exception it returns **500** so Stripe
retries.

**Stripe "dahlia" field locations.** The 2026 API generation nests invoice
fields under a typed `parent`: a line's subscription item is at
`line.parent.subscription_item_details.subscription_item`, the invoice's
subscription + metadata at `invoice.parent.subscription_details.*`, and
`invoice.charge` / `invoice.payment_intent` are **gone** (the charge arrives on
the separate `invoice_payment.paid` event). The handlers never read these
inline — they go through the version-tolerant readers in
`stripe_invoice_fields.py` (`line_subscription_item`, `invoice_metadata`), which
read the nested location first and fall back to the old flat field.

**The `handle/record` seam.** Each of the 4 invoice/payment/refund handlers
(`InvoicePaidHandler`, `InvoicePaymentPaidHandler`, `InvoicePaymentFailedHandler`,
`RefundHandler`) is split: `handle(session, event, gym_id)` unwraps the event
envelope and calls `record(session, obj, gym_id, …)` with the plain body. The
dispatcher calls `handle` (webhook behavior unchanged); the **on-demand post-op
invoice fetch** (`MemberMembershipsInvoiceFetch` — `memberships-guide`) and the
**reconciler backstop** (`InvoiceFetchSweep` — `reconciler-guide`) both call
`record` directly with listed Stripe objects so they can apply invoices
idempotently without a webhook event. Deep detail lives in those two skills;
this section only documents what each handler writes.

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
4. `_dispatch` routes by `event.type` to the matching handler; unknown types
   return silently.

`retry_pending_event` re-runs `handle_event` up to 3 times with a 10s delay (it
catches `WebhookRetryableError`, used for both the sub-item race and the
invoice-not-yet-recorded race below).

---

## 6. The handlers — exactly what each writes

The registered event types (constants in `stripe_webhooks_service.py`):
`invoice.paid`, `invoice_payment.paid`, `invoice.payment_failed`,
`refund.created` + `refund.updated` (both → the same `RefundHandler`), and
`account.updated`. Each handler is a `Factory` in the DI container.
Shared helpers: `dump_stripe_payload` (`stripe_json.py`, JSON with a `Decimal→
float` fallback so an audit write can never crash a webhook) and `stripe_time.py`
(`stripe_ts_to_datetime` / `stripe_ts_to_date`). The raw Stripe payload is stored
into the `stripe_event_payload JSONB` column on every invoice/charge write.

**`invoice.paid` → `InvoicePaidHandler`** (`invoice_paid_handler.py`) writes:

- **`member_invoices`** — upsert to `status='paid'` (`member_invoice_upsert.sql`,
  `ON CONFLICT (stripe_invoice_id) DO UPDATE`), returning `invoice_id`. The
  `paid_by_member_id` (payer) + `paid_for` (beneficiary list) come from the
  resolution below and are **insert-only** (set once by the first writer, not
  updated on conflict — mirroring the old `member_id`).
- **`member_invoice_line_items`** — one row per Stripe invoice line
  (`member_invoice_line_item_insert.sql`, idempotent `ON CONFLICT (line_item_id)`,
  PK = the Stripe line id): `name` (the line description), `amount` (line total),
  `quantity`, and `stripe_product_id`. A line whose `subscription_item` resolves to
  a membership is stored `item_type='membership'` with that `item_id`; everything
  else is `custom`. Negative (proration-credit) lines are skipped (`amount >= 0`).
- **`member_memberships`** — for each billed sub-item, updates `last_paid_date` +
  `next_due_date` (`member_memberships_update_payment_dates.sql`, writes to
  `member_memberships_unfiltered`) on **every** membership the item bills — a
  consolidated item (quantity > 1) maps to several co-owners, all advanced.
  **Skipped for one-time invoices.**

It does **not** write `member_charges` — the succeeded charge is recorded by the
`invoice_payment.paid` handler (below). This handler owns the bill; that one owns
the money movement.

Attribution resolution (`_resolve_attribution` → `(paid_by_member_id, paid_for,
settle_payer)`): **one-time** invoices read it straight from metadata —
`paid_by_member_id` + `paid_for` (the ad-hoc charge-card shape), falling back to
the legacy single `member_id` (the bill owner, with `paid_for=[owner]`) when those
keys are absent, so a one-time **membership** invoice still attributes to its bill
owner until that build path stamps the split. **Subscription** invoices resolve by
matching each line's `subscription_item` (`line_subscription_item` →
`memberships_by_stripe_item.sql`) against `member_memberships`: the payer is the
membership's `paid_by_member_id` (one Stripe sub = one payer) and `paid_for` is the
**distinct set of owners** billed on the invoice — gathering **all** memberships
per item (a consolidated quantity>1 item is shared by several co-owners; the SQL
is intentionally **un-`LIMIT`ed** so the second person isn't dropped). This resolves the
subscription invoice's payer (`paid_by_member_id`, via `_resolve_attribution`); a one-time
invoice reads its payer from the invoice metadata (`_attribution_from_metadata`) instead. If
no payer resolves **and** lines reference sub-items, it raises
**`SubscriptionItemPendingError`** (the create-flow hasn't committed
`stripe_item_id` yet) → 200 + background retry.

**`invoice_payment.paid` → `InvoicePaymentPaidHandler`**
(`invoice_payment_paid_handler.py`) — the **charge recorder**. Stripe fires one
`invoice_payment.paid` per payment (partial **or** full; a $0 invoice fires none,
so it gets no charge — correct). Writes one **`member_charges`** `kind='payment'`,
`status='succeeded'` row (`member_charge_insert.sql`):

- Resolves the invoice + its `paid_by_member_id` (payer) from the already-recorded
  `member_invoices` row (`member_invoice_by_stripe_id.sql`) and writes the charge
  attributed to that payer. If the row isn't there yet (the `invoice.paid` event
  lost the race), it raises **`InvoiceNotYetRecordedError`** → 200 + retry until it
  lands.
- The `ch_…` id comes from the InvoicePayment's `payment.payment_intent` →
  retrieves the PaymentIntent (read-only, on the connected account) and reads
  `latest_charge`. An `out_of_band` payment is recorded as cash
  (`payment_method_type='cash'`, no charge id). DI injects `stripe_client` for the
  retrieve.

DI injects `payment_sync_service` into `InvoicePaidHandler` if it is needed by
any post-payment sync steps.

> **Per-invoice discount audit.** After the invoice + line items are written,
> `_capture_discounts` captures the invoice's discounts into
> `member_invoice_applied_discounts` (§7). The webhook payload carries only
> opaque `di_` Discount ids, so it **retrieves the invoice** with
> `expand=["discounts", "lines.data.discounts"]` to resolve each `di_ → coupon`
> from **both** the invoice-level discounts **and each line's** discounts
> (item-level coupons — a consolidated one-time invoice discounts each membership
> line independently — live on the lines, not the invoice), then stores
> `{amount_off, stripe_coupon_id}` per discount — **coupon-only, not linked to a
> CRM discount** (the value-signature coupon is shared across discounts, so the
> link is ambiguous; we deliberately don't resolve it). It is **SAVEPOINT-isolated
> best-effort** (`begin_nested` + try/except — a capture failure never rolls back
> the invoice/charge), a no-op (no Stripe call) when the invoice has no discounts,
> and idempotent via the row's `UNIQUE (invoice_id, stripe_coupon_id)`. DI injects
> `stripe_client` into `InvoicePaidHandler` for the retrieve.

**`invoice.payment_failed` → `InvoicePaymentFailedHandler`**
(`invoice_payment_failed_handler.py`) writes:

- **`member_invoices`** — upsert to `status='open'`.
- **`member_charges`** — one `kind='payment'`, `status='failed'` row with
  `stripe_charge_id=NULL` (so retries of the same attempt don't collide on the
  UNIQUE constraint; the outer event-log dedup prevents double inserts).

Nothing on the membership row is mutated — Stripe owns dunning; the CRM surfaces
failures by querying `member_charges WHERE status='failed'`. Same
`SubscriptionItemPendingError` race handling as above.

**`refund.created` / `refund.updated` → `RefundHandler`** (`refund_handler.py`)
writes:

- **`member_charges`** — one `kind='refund'`, `status='succeeded'`, **negative**
  amount row per refund, linked to its parent payment via `refunds_charge_id`
  (the parent is looked up by `refund.charge` → `stripe_charge_id` +
  `kind='payment'` via `member_charge_by_stripe_charge_id.sql`).

In dahlia the charge object no longer carries its refunds, so refunds arrive as
their own `refund.*` events (the event's data object **is** the Refund). Both
`refund.created` and `refund.updated` route here; the handler records only when
`status='succeeded'` (a card refund is born succeeded; an async refund succeeds on
a later update). The `stripe_refund_id` UNIQUE constraint + `ON CONFLICT DO NOTHING`
makes the create/update overlap and any replay idempotent. If no parent payment
row exists it **logs an error and acks** (can't insert a refund — `invoice_id` is
NOT NULL — needs manual reconciliation, not a retry).

> **The refund endpoint already writes the row; the webhook is the residual
> catch-all.** A staff-initiated refund (`POST /api/v1/member_memberships/refund`,
> §9, `MemberMembershipsRefund`) calls `refund_payment` and, when the returned
> refund is `succeeded`, writes the negative `member_charges` row **itself** in
> the request (its own `member_refund_insert.sql`, also `ON CONFLICT DO NOTHING`
> on `stripe_refund_id`). So this handler is a no-op for that common case. It
> still earns its keep for the two cases the endpoint can't see synchronously: an
> **async refund** that comes back `pending` (the endpoint writes nothing; the
> later `refund.updated` records it on success) and a refund **initiated from the
> Stripe Dashboard** (no endpoint call at all). A **cash** refund never produces
> a Stripe event, so only the endpoint writes it (negative cash row, no
> `stripe_refund_id`).

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
gym_id)` is the FK target for children. **Payer vs. beneficiaries are two
separate columns** (there is no single `member_id`): `paid_by_member_id` — the one
member whose Stripe customer/card was billed (composite FK `(paid_by_member_id,
gym_id)` → `members`, indexed `(paid_by_member_id, gym_id, invoice_time DESC)`) —
and `paid_for JSONB NOT NULL DEFAULT '[]'` — the list of beneficiary member_id
strings this bill was FOR (usually just `[payer]`; a parent paying for a child
lists the child; a consolidated family invoice lists every owner; GIN-indexed).
So a payment surfaces on the payer's page (`paid_by_member_id`) AND every
beneficiary's page (`paid_for ? member_id`); the member-sees-own RLS and the
payment-history query both read it that way.

**`member_charges`** — money movement (payments **and** refunds). Column `kind`
(enum `charge_kind`) ∈ `payment` / `refund`; column `status` (enum
`charge_status`) ∈ `pending` / `succeeded` / `failed`.
`amount INTEGER` is **signed**. `stripe_charge_id` / `stripe_refund_id` both
`UNIQUE`; `refunds_charge_id` is a self-FK to the refunded payment row. It carries
the payer as `paid_by_member_id` (composite FK + index, mirroring the invoice; a
refund row copies its parent payment's payer) — the beneficiary set lives on the
invoice (`paid_for`), not here. The CHECK constraints (the contract):

| constraint | rule |
| --- | --- |
| `payment_amount_nonneg` | payment → `amount >= 0` |
| `payment_has_charge_id` | payment → `stripe_charge_id IS NOT NULL` **OR** `payment_method_type = 'cash'` |
| `payment_has_no_refund_id` | payment → `stripe_refund_id IS NULL` |
| `payment_has_no_parent` | payment → `refunds_charge_id IS NULL` |
| `refund_amount_nonpos` | refund → `amount <= 0` |
| `refund_has_refund_id` | refund → `stripe_refund_id IS NOT NULL` **OR** `payment_method_type = 'cash'` (a cash refund carries no Stripe id, mirroring `payment_has_charge_id`) |
| `refund_has_parent` | refund → `refunds_charge_id IS NOT NULL` |
| `refund_has_no_charge_id` | refund → `stripe_charge_id IS NULL` |

`member_charge_insert.sql` is `ON CONFLICT DO NOTHING RETURNING charge_id`. Cash charges (`stripe_charge_id IS NULL`) also have a partial unique index on `(invoice_id) WHERE stripe_charge_id IS NULL AND kind='payment' AND status='succeeded' AND payment_method_type='cash'` — the reconciler's `record()` re-sweep hits `ON CONFLICT DO NOTHING` instead of double-counting cash revenue.

**`member_invoice_line_items`** — what's on the bill. PK `line_item_id VARCHAR`
**reuses the Stripe line-item id (`il_…`)** directly — line items always
originate from Stripe, so reusing the id gives free idempotency with no mapping
layer. Column `item_type` (enum `line_item_type`) ∈ `membership` / `custom`. `name CHECK (<> '')` is a
frozen historical label; `amount CHECK (>= 0)` is the line total; `quantity CHECK (> 0)`
(default 1) is the billed count. `item_id` (→
`member_memberships_unfiltered`) is set **only** for membership lines
(`membership_line_has_item_id` / `custom_line_has_no_item_id`).

**`member_invoice_applied_discounts`** — a **billing AUDIT trail**, not a
system-of-record. One row = one Stripe coupon that discounted an invoice, written
by the `invoice.paid` capture (above): `stripe_coupon_id NOT NULL` (the
identifier), `amount_off INTEGER CHECK (>= 0)` (the **dollars it took off this
invoice**, captured as-of-invoice), and `discount_id` (**nullable, left NULL** — we
deliberately do **not** resolve back to a CRM `gym_discount`, since the
value-signature coupon is shared across discounts; the FK is kept only for a
possible future link). `line_item_id` (`VARCHAR NOT NULL`, the Stripe `il_` invoice-line id — an audit value, not FK-enforced, since proration-credit lines aren't persisted as line-item rows) ties each discount row to a specific invoice line. `UNIQUE (invoice_id, stripe_coupon_id, line_item_id)` makes the capture idempotent; the `invoice.paid` capture reads per-line `line.discount_amounts` (with the line id), so a coupon shared across sibling family lines records one row per line instead of collapsing to one. **This is explicitly distinct from
`member_membership_applied_discounts`** (the slim, versioned applied-discount row
that pins a membership to a discount *value version* — owned by `discounts-guide`).
This audit table records *what a specific invoice actually discounted (by coupon)*;
the applied-discount table records *what a membership is currently entitled to*. Do
not conflate them.

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

This guide owns the inbound webhook endpoint plus the members-router card
endpoints and the member_memberships refund endpoint that call the §3 primitives
(those routers otherwise belong to their own domains):

| method + path | calls into |
| --- | --- |
| `POST /api/v1/stripe/webhooks` | the webhook ingestion (§5–§6) |
| `PUT /api/v1/members/{member_id}/card` | `update_card` → `PaymentsStripeMembersService.update_customer` (card swap only; raises if the member has no Stripe customer — `create_customer` runs once at member creation, never here) |
| `DELETE /api/v1/members/{member_id}/payment` | `unlink_payment` → `unlink_customer_card` + cancel recurring subs (Stripe customer link preserved) |
| `GET /api/v1/members/{member_id}/payment-method-status` | `has_payment_method` → `MembersManagementPaymentMethods` → `has_attached_payment_method` (live Stripe read; no Stripe customer ⇒ `false`; any Stripe failure ⇒ **500, never `false`**) |
| `POST /api/v1/member_memberships/refund` | `MemberMembershipsRefund.refund_charge` (sibling of charge-card; standalone, not on the `MemberMembershipsService` facade) → loads the charge by PK (gym-scoped, `memberships/sql/member_charge_by_id.sql`), validates the refundable balance, then for a card charge calls `refund_payment` and records the succeeded negative row (`memberships/sql/member_refund_insert.sql`); a cash charge records a negative cash row with no Stripe call (§6) |

> **⚠️ Refund assumes ONE succeeded charge per invoice — it would break down with
> multiple.** The refund operates at the **charge** level: it loads a single
> `member_charges` row by PK and computes the refundable balance as *that
> charge's* `amount` minus the refunds linked to *that charge*
> (`refunds_charge_id`). The CRM, by contrast, surfaces payment history **one row
> per invoice** — the invoice total as the row amount, `refunded_amount` summed
> across the invoice's charges, picking a representative *succeeded* charge for
> the row's `charge_id`. These two only line up **because each invoice is paid by
> exactly one succeeded charge today** (Stripe invoice → one PaymentIntent → one
> charge; failed retries carry `status='failed'` and aren't refundable, so the
> representative succeeded charge's `amount` *equals* the invoice total). The day
> we allow **multiple succeeded charges on one invoice** (split / partial
> payments), this breaks: the UI would offer an invoice-total refund the single
> representative charge can't satisfy, and the backend's per-charge
> `already_refunded` would disagree with the CRM's per-invoice `refunded_amount`.
> Before supporting multi-charge invoices, rework the refund to aggregate across
> the invoice's charges (refund at invoice granularity), not the lone charge PK.

The subscription / invoice primitives have **no direct endpoint** — they are
called by the sync engine and the membership/members/plans services
(`sync-guide` / `memberships-guide` own those call sites). The refund primitive
is the exception: the refund endpoint above is its one caller.

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
  `payments_subscription_base.py`, and the create/update/cancel/migration/
  upcoming/retrieve/item delegates). `payments_subscription_retrieve.py` holds
  `get_subscription`.
- **Webhook router:** `payments/`… no router — the only router is
  `src/stripe_webhooks/stripe_webhooks_router.py` (`POST /api/v1/stripe/webhooks`).
- **Webhook service + handlers:** `src/stripe_webhooks/service/`
  (`stripe_webhooks_service.py`, `event_log.py`, `invoice_paid_handler.py`,
  `invoice_payment_paid_handler.py`, `invoice_payment_failed_handler.py`,
  `refund_handler.py`, `account_updated_handler.py`, `stripe_json.py`,
  `stripe_time.py`, `stripe_invoice_fields.py` — the dahlia field readers);
  exceptions in `stripe_webhooks_exceptions.py` (`WebhookRetryableError` base,
  `SubscriptionItemPendingError`, `InvoiceNotYetRecordedError`).
- **Webhook SQL:** `src/stripe_webhooks/sql/` (`gym_by_stripe_account.sql`,
  `stripe_webhook_events_insert.sql`, `member_invoice_upsert.sql`,
  `member_charge_insert.sql`, `member_charge_by_stripe_charge_id.sql`,
  `member_invoice_by_stripe_id.sql`, `memberships_by_stripe_item.sql`,
  `member_memberships_update_payment_dates.sql`, `gyms_set_onboarding_status.sql`).
- **Schema:** `Database/supabase/schemas/member_invoices.sql`,
  `member_charges.sql`, `member_invoice_line_items.sql`,
  `member_invoice_applied_discounts.sql`, `stripe_webhook_events.sql`, `gyms.sql`
  (the `stripe_account_id` / `stripe_onboarding_status` columns). Access rules in
  the parallel `access_rules/` files.
- **DI wiring:** `src/core/dependencies.py` (`stripe_client` Singleton; all
  wrapper services + webhook handlers as Factories; `stripe_webhooks_service`).
- **Members card endpoints:** `src/members/members_router.py`
  (`PUT /{member_id}/card`, `DELETE /{member_id}/payment`).
- **Engine roadmap (prose):** `FastApiBackend/PaymentRefactor.md` (remaining-work
  only). The config-vs-outcomes rationale is §1 here + the `sync-guide` skill.

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
