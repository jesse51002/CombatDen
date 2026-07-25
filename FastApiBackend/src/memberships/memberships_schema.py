"""Request schemas for member membership lifecycle operations."""

from datetime import date
from enum import StrEnum
from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator
from schema.gym_discount import DiscountType
from schema.member_charge import ChargeStatus
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import DiscountValue
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
    PreviewInvoice,
)


class _CancelItemsBase(BaseModel):
    """Shared base for the cancel + cancel-preview requests: a non-empty,
    duplicate-free list of ``member_memberships`` rows to cancel."""

    item_ids: list[UUID] = Field(..., min_length=1)
    member_id: UUID

    @field_validator("item_ids")
    @classmethod
    def _no_dupes(cls, value: list[UUID]) -> list[UUID]:
        if len(value) != len(set(value)):
            raise ValueError("item_ids must not contain duplicates")
        return value


class MemberMembershipsCancelRequest(_CancelItemsBase):
    """Cancel ONE OR MORE of a member's recurring memberships.

    ``item_ids`` is the list of ``member_memberships`` rows to cancel (a single
    cancel is a one-element list). The backend groups them by payer and
    converges each payer's subscription once. ``idempotency_key`` is scoped to
    this cancel; per-payer Stripe keys are derived from it deterministically so
    a retry dedups.
    """

    idempotency_key: UUID


class MemberMembershipsCancelPreviewRequest(_CancelItemsBase):
    """Preview cancelling ONE OR MORE of a member's recurring memberships."""


class MemberMembershipsCancelResponse(BaseModel):
    """Response after a (possibly batched) cancel.

    ``cancel_dates`` maps each cancelled ``item_id`` (as a string) to its
    resolved ``cancel_date`` — the date through which that membership stays
    active. A single cancel yields a one-entry map.
    """

    cancel_dates: dict[str, date]


class MemberMembershipsFreezeRequest(BaseModel):
    """Freeze a member's account (account-level).

    No ``gym_id``: the gym is derived server-side from the member's own row
    (C-070), so a client value would be dead weight and a misleading contract.
    """

    member_id: UUID
    freeze_months: int = Field(..., gt=0)
    idempotency_key: UUID


class MemberMembershipsUnfreezeRequest(BaseModel):
    """Unfreeze a member's account (account-level).

    No ``gym_id`` — derived server-side from the member's row (see
    :class:`MemberMembershipsFreezeRequest`).
    """

    member_id: UUID
    idempotency_key: UUID


class MemberMembershipsStartItem(BaseModel):
    """One membership to create inside a start request.

    ``price_id`` alone identifies what is bought — a price belongs to
    exactly one plan, so the plan is derived server-side from the price row
    (no redundant plan field to mismatch). ``discount_ids`` reference
    existing preset discounts; ``custom_discounts`` are inline
    values minted as ``custom`` discounts. Both land before the charge, so
    the first (one-time: only) invoice is discounted.

    ``quantity`` is how many identical units this one item buys. one_time /
    trial packs STACK via ``quantity`` (one row billed as a single Stripe line
    with that quantity, so a fixed-$ coupon applies once, not N times, and the
    pack grants ``class_count * quantity`` classes). Recurring must be
    ``quantity == 1`` (enforced in MemberMembershipsStartValidation, where plan
    types are known, and again by the DB trigger). Buying ANOTHER pack of the
    same plan is a SEPARATE item, not a higher quantity on this one.
    """

    member_id: UUID
    price_id: UUID
    quantity: int = Field(1, gt=0)
    discount_ids: list[UUID] = []
    custom_discounts: list[DiscountValue] = []


class MemberMembershipsStartPayment(BaseModel):
    """A card entered at checkout for a start request.

    ``payment_method_id`` is a Stripe PaymentMethod (``pm_...``).
    ``set_default`` promotes it to the payer's saved default **up-front**
    (before any charge), so it bills BOTH the one-time invoice and the
    recurring subscription. Recurring can only bill the saved default, so a
    request that contains any recurring membership MUST set ``set_default``
    (enforced in the start op, where plan types are known). A purely one-time
    cart may leave it ``False`` — then the card is a one-off (attach → pay →
    detach) and the payer's saved default is untouched.
    """

    payment_method_id: str
    set_default: bool = False


class MemberMembershipsStartRequest(BaseModel):
    """Start a linked family's memberships in one call.

    The payer (``payer_member_id``) is identity-only — it need not appear in
    ``memberships``. Every non-payer member must ALREADY be linked to this
    payer (linking is a separate, prior operation; the start op never links).
    ``proration_behavior`` applies to the recurring converge only;
    ``paid_with_cash`` is request-level (the consolidated one-time invoice is
    one charge). The
    single ``idempotency_key`` deterministically derives one sub-key per
    charge group (one-time invoice / recurring converge), so a client retry
    of the same request dedups both charges at Stripe.

    ``payment`` is an optional card entered at checkout
    (``MemberMembershipsStartPayment``). When ``payment.set_default`` the card
    is promoted to the payer's saved default before charging, so it bills the
    one-time invoice AND the recurring subscription. It is card-only (mutually
    exclusive with ``paid_with_cash``); the start op additionally rejects a
    card on a request with a recurring membership unless ``set_default`` is set
    (recurring always bills the saved default).
    """

    payer_member_id: UUID
    gym_id: UUID
    proration_behavior: ProrationBehavior = (
        ProrationBehavior.prorate_to_anchor
    )
    paid_with_cash: bool = False
    payment: MemberMembershipsStartPayment | None = None
    idempotency_key: UUID
    memberships: list[MemberMembershipsStartItem] = Field(
        default_factory=list,
    )

    @model_validator(mode="after")
    def _validate_payment(self) -> Self:
        """A card and an out-of-band (cash) settle are mutually exclusive."""
        if self.payment is not None and self.paid_with_cash:
            raise ValueError(
                "payment cannot be combined with paid_with_cash "
                "(a cash settle charges no card)",
            )
        return self

    @field_validator("memberships")
    @classmethod
    def _validate_memberships(
        cls,
        value: list[MemberMembershipsStartItem],
    ) -> list[MemberMembershipsStartItem]:
        # No two items may share the same (member_id, price_id): buying N of
        # the same pack is ONE item with quantity = N, never N duplicate items.
        # (Two DIFFERENT prices of the same plan are still two distinct items —
        # the recurring-only same-plan guard lives in
        # MemberMembershipsStartValidation, where plan types are known.)
        if not value:
            raise ValueError("memberships must not be empty")
        seen: set[tuple[UUID, UUID]] = set()
        for item in value:
            key = (item.member_id, item.price_id)
            if key in seen:
                raise ValueError(
                    "Duplicate (member_id, price_id) in one request: use "
                    "quantity to buy multiple of the same pack, not repeated "
                    f"items (member_id={item.member_id}, "
                    f"price_id={item.price_id})",
                )
            seen.add(key)
        return value


class MemberMembershipsStartStatus(StrEnum):
    """Outcome of one membership inside a start request."""

    created = "created"
    failed = "failed"


class MemberMembershipsStartResultItem(BaseModel):
    """Per-membership outcome in the start breakdown.

    ``item_id`` is set when ``status = created``; ``error`` carries the
    failure reason when ``status = failed``. Failure granularity is the
    charge group (the one-time invoice / the recurring converge), so
    same-group items share fate.

    ``error`` is prefixed so a client (and the front desk reading the receipt)
    can tell the kinds of failure apart without parsing prose:

    * ``card declined: …`` — the BANK refused. Nothing was collected for this
      group; offering another card is the right next step.
    * ``not collected: …`` — nobody refused, and the money still did not
      arrive: the charge needs authentication (SCA / 3-D Secure) the member has
      to complete. Nothing was collected and nothing was booked. Deliberately
      NOT ``declined`` — no bank said no, so "try another card" is the wrong
      advice; staff collect another way.
    * ``system failure: …`` — OUR side broke. Only reachable when an earlier
      charge in the SAME request already collected, which is why the response is
      a 207 rather than a 500 (see ``MemberMembershipsStart``): another card
      will not help, staff have to finish the job.

    The first two are DEFINITIVE answers about the money and never imply an
    outage; the third is the outage. The prefixes are a stable part of the
    contract — reword the text after them freely, never the prefix itself, and
    never let one become a prefix of another.
    """

    member_id: UUID
    plan_id: UUID
    plan_type: PlanType
    status: MemberMembershipsStartStatus
    item_id: UUID | None = None
    error: str | None = None


class MemberMembershipsStartResponse(BaseModel):
    """Response after a start: the per-membership breakdown.

    ``charge_count`` = (1 if any one-time membership) + (1 if any recurring
    membership); ``multiple_charges`` flags the mixed case so the CRM can
    tell the gym owner two separate charges occurred. Invoice figures are
    NOT returned here — the start preview owns those.
    """

    results: list[MemberMembershipsStartResultItem]
    charge_count: int
    multiple_charges: bool


class MemberMembershipsStartItemState(BaseModel):
    """One item's working state across the start phases (internal only).

    Not an API shape — the start service threads this through its insert /
    charge / converge / verify phases and folds it into the response
    breakdown at the end. ``plan_id`` / ``plan_type`` are derived from the
    item's price row.
    """

    member_id: UUID
    gym_id: UUID
    plan_id: UUID
    plan_type: PlanType
    item_id: UUID | None = None
    applied_ids: list[UUID] = Field(default_factory=list)
    minted_ids: list[UUID] = Field(default_factory=list)
    status: MemberMembershipsStartStatus = (
        MemberMembershipsStartStatus.created
    )
    error: str | None = None


class MemberMembershipsStartPreviewResponse(BaseModel):
    """The start preview's three-way invoice split.

    ``one_time`` — the consolidated one-time invoice (all one-time
    memberships, one charge), the one-time lines ONLY (the payer's live
    subscription lines are stripped). ``due_now`` — the recurring proration
    invoice charged immediately; present ONLY when ``proration_behavior`` is
    ``prorate_to_anchor`` and ``None`` otherwise (a ``no_charge`` start
    charges nothing extra now).
    ``recurring`` — the steady-state recurring invoice each cycle going
    forward. Each is ``None`` when the request has no memberships in that
    group.
    """

    one_time: PreviewInvoice | None = None
    due_now: PreviewInvoice | None = None
    recurring: PreviewInvoice | None = None


class MemberMembershipsMarkPaidCashRequest(BaseModel):
    """Mark a recurring membership's open invoice as paid via cash."""

    item_id: UUID
    member_id: UUID
    idempotency_key: UUID


class MemberMembershipsRetryCardRequest(BaseModel):
    """Retry the payer's saved card on a recurring membership's open invoice."""

    item_id: UUID
    member_id: UUID
    idempotency_key: UUID


class MemberMembershipsRetryCardStatus(StrEnum):
    """Outcome of a card retry on ONE membership's open invoice.

    Three outcomes, all of them DATA: the bank collected, the bank refused, or
    nobody refused but the money did not arrive either. Only ``paid`` means
    money moved — see :class:`MemberMembershipsRetryCardResponse`.
    """

    paid = "paid"
    declined = "declined"
    not_collected = "not_collected"


class MemberMembershipsRetryCardResponse(BaseModel):
    """The outcome of one card retry — a definitive answer is a RESULT, not a
    failure.

    ``paid`` (HTTP 200) — the bank collected; the open invoice is settled. The
    ONLY outcome that means money moved.

    ``declined`` (HTTP 207) — the bank refused; nothing was collected and the
    membership stays overdue, with ``decline_reason`` carrying Stripe's own
    end-user wording so staff know what to do next (expired → Update Card;
    insufficient funds → tell the member).

    ``not_collected`` (HTTP 207) — nothing was refused, but nothing was
    collected either: the off-session invoice's PaymentIntent needs
    authentication (SCA / 3-D Secure) the member has to complete, so it came
    back still ``open``. A distinct outcome from ``declined`` on purpose — the
    bank never said no, so "try another card" is the wrong advice; staff have to
    collect another way. Raised as ``PaymentsNotCollectedError``.

    A system/upstream failure is NOT any of these shapes — it is still a 500.

    ``decline_reason`` is the one "why nothing was collected" slot, populated on
    BOTH non-``paid`` outcomes (Stripe's decline wording on ``declined``, the
    authorization-needed explanation on ``not_collected``); the machine-readable
    discriminator is ``status``, never the prose.

    Single-item on purpose: this endpoint settles exactly ONE membership's
    invoice, so the start path's ``results`` LIST would misrepresent it. The
    2xx-with-the-reason-in-the-body contract is the same on both paths.
    """

    item_id: UUID
    member_id: UUID
    status: MemberMembershipsRetryCardStatus
    decline_reason: str | None = None


class MemberMembershipsChargeCardRequest(BaseModel):
    """Charge an ad-hoc amount for a member, billed to an explicit payer.

    Creates a one-off Stripe invoice (outside any subscription)
    for ``amount_cents`` with ``reason`` used as both the invoice
    description and the invoice item name. ``member_id`` is the
    BENEFICIARY (whose record the charge belongs to);
    ``paid_by_member_id`` is whose customer/card is billed — the
    member themselves or their linked parent (chosen in the CRM).
    ``paid_cash`` routes the invoice through the out-of-band
    payment path instead of charging the card.

    ``payment_method_id`` is an optional one-off card (a Stripe
    PaymentMethod ``pm_...``) entered at checkout: it is attached to
    the payer's customer, billed once, then detached — the payer's
    saved default is left untouched. ``None`` bills the payer's saved
    default. It is card-only (mutually exclusive with ``paid_cash``).
    """

    member_id: UUID
    paid_by_member_id: UUID
    gym_id: UUID
    amount_cents: int = Field(..., gt=0)
    reason: str = Field(..., min_length=1)
    paid_cash: bool = False
    payment_method_id: str | None = None
    idempotency_key: UUID

    @model_validator(mode="after")
    def _validate_payment(self) -> Self:
        """A one-off card and a cash settle are mutually exclusive."""
        if self.payment_method_id is not None and self.paid_cash:
            raise ValueError(
                "payment_method_id cannot be combined with paid_cash "
                "(a cash settle charges no card)",
            )
        return self


class MemberMembershipsChargeCardResponse(BaseModel):
    """The **207** body when an ad-hoc charge collected NOTHING.

    A collected charge is still 204 with no body — the success contract is
    unchanged. This reuses retry-card's status vocabulary (``decline_reason``
    is the same "why nothing was collected" slot), so a client branches on
    ``status``, never on the 2xx class. Only ``not_collected`` is reachable
    here today; a decline on this route is still a 500 — see the router.
    """

    member_id: UUID
    paid_by_member_id: UUID
    status: MemberMembershipsRetryCardStatus
    decline_reason: str | None = None


class MemberMembershipsRefundRequest(BaseModel):
    """Refund a prior charge on a member's payment history.

    ``member_id`` is the member whose billing history the refund was launched
    from (the auth + gym-scope anchor). ``charge_id`` is the ``member_charges``
    row to refund (a succeeded payment). ``amount`` is positive minor units;
    ``None`` refunds the full remaining balance (the charge minus anything
    already refunded). ``idempotency_key`` is minted per submission by the CRM so
    a retried request dedups the Stripe refund.
    """

    member_id: UUID
    charge_id: UUID
    amount: int | None = None
    idempotency_key: str


class MemberMembershipsRefundResponse(BaseModel):
    """Outcome of a refund: the recorded refund row's id, the minor units
    refunded, the method ('card' / 'cash'), and the refund status.

    ``refund_charge_id`` is ``None`` for a Stripe refund that comes back
    ``pending`` — no row is written until the ``refund.*`` webhook confirms it
    succeeded.
    """

    refund_charge_id: UUID | None = None
    refunded_amount: int
    payment_method: str
    status: ChargeStatus


class MemberMembershipsUpdatePriceRequest(BaseModel):
    """Reprice ONE membership onto its plan's currently active price.

    The member-detail upgrade: the target is not caller-supplied — the
    reprice moves the membership onto the plan's single ``is_active = true``
    price. This is a DIRECT, synchronous op (NOT a task — tasks are only for
    the per-plan batch): the endpoint reprices and returns the new membership
    id. A membership already on the active price is a no-op (returns its own
    id). ``idempotency_key`` is accepted for client compatibility; the
    reprice mints its own Stripe keys.
    """

    item_id: UUID
    member_id: UUID
    proration_behavior: ProrationBehavior = ProrationBehavior.no_charge
    idempotency_key: UUID


class MemberMembershipsUpdatePriceResponse(BaseModel):
    """The reprice's successor membership row id (== ``item_id`` on a no-op)."""

    item_id: UUID


class MemberMembershipsBatchRepriceRequest(BaseModel):
    """Upgrade EVERY member on a plan to that plan's active price (batch).

    The only task workflow: the backend auto-discovers every active
    membership on ``plan_id`` whose price is not the plan's ``is_active``
    price (skipping any already mid-task), creates one ``membership_reprice``
    task with an item per membership, runs it in the background, and returns
    the task id to poll. The caller never supplies a member list.
    """

    plan_id: UUID
    gym_id: UUID
    proration_behavior: ProrationBehavior = ProrationBehavior.no_charge


class MemberMembershipsBatchRepriceResponse(BaseModel):
    """The batch reprice task (``task_id`` is null when nothing needs it).

    Poll ``GET /api/v1/tasks/{task_id}`` for per-membership progress.
    ``membership_count`` is how many memberships the task is repricing.
    """

    task_id: UUID | None
    membership_count: int


class MemberMembershipsUpgradeRequest(BaseModel):
    """Upgrade ONE membership to a DIFFERENT plan's active price (cross-plan).

    Moves the membership onto ``target_plan_id``'s currently active price and
    charges the prorated DIFFERENCE now when ``proration_behavior`` is
    ``prorate_to_anchor`` AND the new price is higher; a downgrade or equal
    price charges nothing (the op forces ``no_charge``). A DIRECT, synchronous
    op (NOT a task — there is no batch upgrade): the endpoint upgrades and
    returns the new membership id. The target must be a DIFFERENT recurring
    plan on the SAME billing interval (same-plan moves are a reprice). The
    proration default is ``prorate_to_anchor`` (charging the difference is the
    point); ``idempotency_key`` dedups the Stripe charge across client retries.
    """

    item_id: UUID
    member_id: UUID
    target_plan_id: UUID
    proration_behavior: ProrationBehavior = (
        ProrationBehavior.prorate_to_anchor
    )
    idempotency_key: UUID


class MemberMembershipsUpgradeResponse(BaseModel):
    """The upgrade's successor membership row id (on the new target plan)."""

    item_id: UUID


class MemberMembershipsUpgradePreviewRequest(BaseModel):
    """Preview an upgrade — the due-now difference + the new per-cycle bill.

    Same target / proration as the upgrade, minus the idempotency key (a
    preview writes nothing and bills nothing). The response's ``due_now`` is
    the prorated difference charged now (``null`` on a downgrade/equal, where
    nothing is charged now); ``recurring`` is the new steady-state monthly bill.
    """

    item_id: UUID
    member_id: UUID
    target_plan_id: UUID
    proration_behavior: ProrationBehavior = (
        ProrationBehavior.prorate_to_anchor
    )


class MemberMembershipsCancelOneTimeRequest(BaseModel):
    """Cancel a ONE-TIME / TRIAL membership early — a MANUAL termination.

    Writes ``cancel_date`` = today → status ``cancelled`` (the terminal-date
    convention: ``cancel_date`` is the human's date; ``end_date`` stays
    automatic-only — the purchase-stamped duration expiry and the check-in
    depletion auto-end). A one-time / trial pack is a terminal invoice with
    no subscription line, so this is a pure DB date write with NO Stripe
    action and no money movement (a refund is the separate ``/refund``
    flow). Recurring memberships use ``DELETE /`` (cancel) instead — this
    endpoint rejects them.
    """

    item_id: UUID
    member_id: UUID


class MemberMembershipsCancelOneTimeResponse(BaseModel):
    """The resolved ``cancel_date`` (today) the membership terminated on."""

    cancel_date: date


class MemberMembershipsAddDiscountsRequest(BaseModel):
    """Add applied-discount rows to a membership (or preview the addition).

    An explicit add of immutable applied-discount rows — never a replace-set.
    ``discount_ids`` references live discounts whose ACTIVE value version is
    frozen onto an applied-discount row. ``preview=True`` stages the adds as
    ``preview_add`` rows and returns the resulting invoice preview without
    committing.
    """

    item_id: UUID
    member_id: UUID
    discount_ids: list[UUID] = Field(default_factory=list)
    idempotency_key: UUID
    preview: bool = False

    @field_validator("discount_ids")
    @classmethod
    def _validate_discount_ids(cls, value: list[UUID]) -> list[UUID]:
        if not value:
            raise ValueError("discount_ids must not be empty")
        if len(value) != len(set(value)):
            raise ValueError("discount_ids must not contain duplicates")
        return value


class MemberMembershipsRemoveDiscountsRequest(BaseModel):
    """Remove applied-discount rows from a membership (or preview the removal).

    ``applied_ids`` deletes existing applied-discount rows by their
    ``applied_discount_id``. ``preview=True`` stages the removal as
    ``preview_remove`` rows and returns the resulting invoice preview without
    committing.
    """

    item_id: UUID
    member_id: UUID
    applied_ids: list[UUID] = Field(default_factory=list)
    idempotency_key: UUID
    preview: bool = False

    @field_validator("applied_ids")
    @classmethod
    def _validate_applied_ids(cls, value: list[UUID]) -> list[UUID]:
        if not value:
            raise ValueError("applied_ids must not be empty")
        if len(value) != len(set(value)):
            raise ValueError("applied_ids must not contain duplicates")
        return value


class MembersBillingLinkRequest(BaseModel):
    """Authorize a payer for a member in ONE request (sign + authorize).

    The payer (``payer_member_id``) is the signer: ``signer_name`` is their typed
    legal name, ``consent_acknowledged`` must be True, and ``waiver_version_id``
    is the gym's default-waiver version the client displayed (echoed so the
    backend version-locks before signing, 409 on a stale echo). The handler
    builds the placeholder values (the payer's + the member-being-paid-for's
    names) and calls the shared signing service, then records the authorization
    referencing the new signature. The two are NOT atomic — a retry after a
    failed authorize leaves a harmless extra (append-only) signature.
    """

    payer_member_id: UUID
    waiver_version_id: UUID
    signer_name: str
    # Literal[True]: a false consent is not a valid e-signature, so reject it at
    # deserialization rather than relying on a downstream runtime guard.
    consent_acknowledged: Literal[True]

    @field_validator("signer_name")
    @classmethod
    def _check_signer_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("signer_name cannot be empty")
        return v


class MembersBillingLinkCheckRequest(BaseModel):
    """Pre-flight check whether a payer can be authorized for a member."""

    payer_member_id: UUID


class MembersBillingLinkCheckResponse(BaseModel):
    """Result of checking whether a member can be linked to a payer.

    ``error`` is a pre-formatted, user-facing string and should be
    rendered as-is in the UI when ``can_link`` is ``False``.
    """

    can_link: bool
    error: str | None = None


class MembersBillingRemoveAuthorizationPreviewRequest(BaseModel):
    """Preview removing a payer's authorization for the path member.

    Identifies the relationship by ``payer_member_id`` (the path member is the
    payee). The preview is **read-only** — it stages nothing on Stripe and
    mutates no membership row — so it carries NO ``idempotency_key`` (there is no
    Stripe write to dedup). Returns the per-payer cancel cost preview (a list of
    ``PayerInvoiceChange``; pair-scoped, so always a single entry).
    """

    payer_member_id: UUID


class MembersBillingRemoveAuthorizationRequest(
    MembersBillingRemoveAuthorizationPreviewRequest
):
    """Remove a payer's authorization for the path member, cascading a cancel.

    Pair-scoped: cancels the path member's live recurring memberships that
    ``payer_member_id`` funds, then de-authorizes the pair. Memberships paid by
    OTHER payers — and the payer's memberships for OTHER members — are untouched.

    Adds ``idempotency_key`` to the preview request: it is scoped to this
    remove-authorization action and threads straight into the cascading cancel's
    list path (which derives the payer's Stripe key from it deterministically),
    so a retry of the same action dedups at Stripe instead of minting a fresh,
    non-idempotent key. The preview needs no such key (read-only), which is why
    it lives only on the mutating request.
    """

    idempotency_key: UUID


class PayerInvoiceChange(BaseModel):
    """One payer's billing outcome from a (possibly batched) cancel.

    A LIST of these is the cancel / remove-authorization cost preview: one entry
    per payer considered. ``affected`` is a **membership-level** flag — True iff
    this payer funds at least one of the memberships being cancelled — decided
    independently of the cost. When ``affected`` is True ``preview`` carries the
    payer's subscription recurring current → new; when False the operation
    cancels nothing for this payer (``preview`` is null) and the UI shows no
    billing change. A single cancel yields a one-entry affected list; a member's
    memberships may be funded by different payers, so a multi-cancel can change
    several payers' bills at once.
    """

    payer_member_id: UUID
    payer_first_name: str
    payer_last_name: str
    affected: bool
    preview: DueNowVsRecurringPreview | None = None


class MemberMembershipsAppliedDiscount(BaseModel):
    """A single applied-discount row returned to the client.

    Joins the applied-discount row to its frozen value version (``value_id``)
    and owning discount (``discount_id`` + name/type) so the CRM can show the
    discount and the exact version it is pinned to.
    """

    applied_discount_id: UUID
    item_id: UUID
    member_id: UUID
    gym_id: UUID
    value_id: UUID
    discount_id: UUID
    discount_name: str
    discount_type: DiscountType
    percentage_off: float | None = None
    dollar_off: int | None = None
    end_date: date | None = None
    stripe_coupon_id: str | None = None
