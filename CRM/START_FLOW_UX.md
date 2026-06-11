# Start-Memberships Flow — UX Spec (dev placeholder stage)

> **Status: approved UX, ready to build.** This is the CRM's new
> start-memberships wizard, replacing the single-membership start dialog. The
> backend it targets is SHIPPED: one list-based start op (`POST
> /api/v1/member_memberships/`) that creates a payer's family memberships in
> one request, discounts applied before the first charge, at most two charges
> (one consolidated one-time invoice + one recurring converge), returning a
> per-membership breakdown. Read
> `FastApiBackend/src/memberships/memberships_schema.py` for the authoritative
> request/response shapes (regenerate `Database/openapi.json` from a running
> backend before writing Dart models).

## The wizard

**Persistent context header on EVERY screen:** who is PAYING and (from step 3
on) which MEMBER is currently being configured. Never let the user wonder
whose card is charged or whose membership they're editing.

### 1. Who pays
Pick the paying account. **Only a top-level paying account is selectable**
(today that means "the parent"); everyone else is shown grayed out with the
reason. (When per-membership payers ship — `PaymentRefactor.md` §7 — the
grayed options unlock; the screen layout should anticipate that, not assume
one option forever.)

### 2. Who's getting memberships (multi-select)
List = the payer themselves + members **already linked to this payer**, only.
The backend hard-rejects unlinked members ("link them first — the start op
never links"). Unlinked family candidates appear grayed out with a **"Link
first"** affordance that jumps to the existing link flow, then returns here.

### 3. Per member — pick memberships (one screen per selected member)
Checkbox list of the gym's plans. Per plan show the class allowance:
- **recurring** → "N classes / month" (or "Unlimited / month")
- **one_time / trial** → "N classes"

**Count stepper (one_time / trial ONLY):** when a one-time or trial plan is
checked, a quantity stepper appears (default 1). Increasing the count
**multiplies the displayed classes** (2 × a 5-class pack → "10 classes").
Recurring plans never show a stepper.

> ⚠️ Count is **UI-only for now** — the backend rejects duplicate
> (member, price) items until `PaymentRefactor.md` §10 ships. Cap the
> stepper at 1 for submission (render it, disable increment with a
> "coming soon" hint, or block at submit — pick one, but the REQUEST must
> never contain duplicates yet). When §10 lands, count N maps to N
> duplicate items in `memberships`.

### 4. Per member — discounts (one screen per member, after their picks)
That member's selected memberships listed together, each with its own
discount controls (**discount per membership, one screen**):
- pick existing presets → the item's `discount_ids`
- inline custom value (percent XOR dollar, once/ongoing, optional lifetime)
  → the item's `custom_discounts` (minted server-side as one-shot customs)

Then advance to the next member (back to 3 for them), until all members are
configured.

### 5. Preview
`POST /api/v1/member_memberships/preview` with the fully assembled request.
Render the **three-way split** the endpoint returns:
- `one_time` — the consolidated one-time invoice (trials appear as $0 lines)
- `due_now` — the recurring proration charged immediately (prorate=true)
- `recurring` — the steady-state per-cycle invoice going forward

The preview is server-side DISCOUNTED (it stages the request, discounts
included). **Confirm = navigation only — it must not fire any mutation.**

### 6. Payment screen
Two settlement choices:
- **Card on file** — shows the payer's card. The multi-card wallet UI here is
  a **placeholder with fake data** (card list + "Add new" button): stored
  multiple payment methods are NOT a backend feature yet; it is required
  before launch and another agent will build the backend. Today the backend
  always charges the payer's single card on file ("Add new" = the existing
  update-card flow, which REPLACES the card).
- **Cash** — REAL, shipped: maps to `paid_with_cash: true` on the request
  (the one-time invoice settles out-of-band; the recurring first invoice is
  marked paid out-of-band; future cycles still auto-charge the card).

Echo the preview totals here — the last thing seen before paying is the
number.

**PAY is the single trigger** that sends `POST /api/v1/member_memberships/`.
Nothing else in the wizard mutates anything.

### 7. Results screen (REQUIRED — partial success is real)
The response is a **201 breakdown**, not success/fail:

```json
{ "results": [ { "member_id", "plan_id", "plan_type",
                 "status": "created" | "failed", "item_id", "error" } ],
  "charge_count": 1 | 2, "multiple_charges": bool }
```

Failure granularity is the charge group: in a mixed cart the one-time invoice
can bill while the recurring converge fails (or vice versa). Render
per-membership created (✓, link to the membership) / failed (✗ + the error
text). When `multiple_charges` is true, say plainly that two separate charges
were made. For a failed group, offer "retry the failed memberships" = a NEW
request containing only the failed items (new idempotency key).

**Copy caution — recurring "created" means converged, not PAID.** For a
RECURRING membership, payment success is asynchronous by design (Stripe's
dunning model): a declining card still yields `created` — the subscription
exists with an open first invoice, and recovery/overdue surfaces through the
webhooks + billing views. So the results screen says the membership was
*created/started*, never "payment received". (A ONE-TIME membership's
`created` DOES mean its invoice settled — its charge is synchronous.)

## Request mapping (one request per wizard run)

```json
{
  "payer_member_id": "<step 1>",
  "gym_id": "<gym>",
  "idempotency_key": "<uuid4, generated at PAY press>",
  "prorate": true,
  "paid_with_cash": <step 6 cash choice>,
  "memberships": [
    { "member_id": "<step 2/3 member>",
      "price_id": "<the plan's ACTIVE price — items carry price_id ONLY, no plan_id>",
      "discount_ids": ["<step 4 presets>"],
      "custom_discounts": [ { "percentage_off": 10.0, "discount_mode": "once" } ]
    }
  ]
}
```

## Placeholder / no-op convention (build rule)

Every placeholder or deliberately-inert piece of THIS flow's frontend code
must carry a comment at its code site marking it as a **known todo**, naming
what unlocks it, and saying the comment is to be **deleted when the real
feature is implemented**. Applies (at least) to:

- the **count stepper** submit cap (unlocks with `PaymentRefactor.md` §10 —
  duplicates become multiple purchases),
- the **card wallet** fake data + "Add new" (unlocks with the pre-launch
  multi-payment-method backend),
- the **grayed-out payer options** in step 1 (unlock with
  `PaymentRefactor.md` §7 — per-membership payers).

Example shape:

```dart
// TODO(known placeholder): fake card list — real multi-card wallet ships
// with the pre-launch payment-methods backend. DELETE this comment (and the
// fake data) when implemented.
```

## Backend constraints the UI must respect
- Payer must be top-level (not linked to anyone) — enforce at step 1.
- Every non-payer member must already be linked to the payer — enforce at step 2.
- No duplicate (member_id, price_id) items — the count stepper caps at 1 until §10.
- A `custom`-type discount can never be referenced by id — customs are inline values only.
- Validation failures = HTTP 400 with a clear message (show it); charge failures = 201 with failed results (results screen).
