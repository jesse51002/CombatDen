"""Request schemas for member membership lifecycle operations."""

from datetime import date
from enum import StrEnum
from typing import Self
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator
from schema.gym_discount import DiscountType
from schema.member_charge import ChargeStatus
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import DiscountValue
from src.payments.schema.payments_invoice_schema import PreviewInvoice


class MemberMembershipsCancelResponse(BaseModel):
    """Response returned after cancelling a membership."""

    cancel_date: date


class MemberMembershipsFreezeRequest(BaseModel):
    """Freeze a member's account (account-level)."""

    member_id: UUID
    gym_id: UUID
    freeze_months: int = Field(..., gt=0)
    idempotency_key: UUID


class MemberMembershipsUnfreezeRequest(BaseModel):
    """Unfreeze a member's account (account-level)."""

    member_id: UUID
    gym_id: UUID
    idempotency_key: UUID


class MemberMembershipsStartItem(BaseModel):
    """One membership to create inside a start request.

    ``price_id`` alone identifies what is bought — a price belongs to
    exactly one plan, so the plan is derived server-side from the price row
    (no redundant plan field to mismatch). ``discount_ids`` reference
    existing preset / linked discounts; ``custom_discounts`` are inline
    values minted as ``custom`` discounts. Both land before the charge, so
    the first (one-time: only) invoice is discounted.
    """

    member_id: UUID
    price_id: UUID
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
        # Intra-request duplicates are allowed here: N identical one_time /
        # trial items is how a member buys N copies of the same pack. The
        # recurring-only "no two of the same plan in one request" guard lives
        # in MemberMembershipsStartValidation, where plan types are known.
        if not value:
            raise ValueError("memberships must not be empty")
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
    """

    member_id: UUID
    paid_by_member_id: UUID
    gym_id: UUID
    amount_cents: int = Field(..., gt=0)
    reason: str = Field(..., min_length=1)
    paid_cash: bool = False
    idempotency_key: UUID


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


class MemberMembershipsAddDiscountsRequest(BaseModel):
    """Add applied-discount rows to a membership (or preview the addition).

    An explicit add of immutable applied-discount rows — never a replace-set.
    ``discount_ids`` references live discounts whose ACTIVE value version is
    frozen onto an applied-discount row (any discount, including a ``linked``
    family discount). ``preview=True`` stages the adds as ``preview_add`` rows
    and returns the resulting invoice preview without committing.
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
    """Link an existing member to a paying parent account."""

    parent_member_id: UUID


class MembersBillingLinkCheckResponse(BaseModel):
    """Result of checking whether a member can be linked to a payer.

    ``error`` is a pre-formatted, user-facing string and should be
    rendered as-is in the UI when ``can_link`` is ``False``.
    """

    can_link: bool
    error: str | None = None


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
    discount_mode: str
    end_date: date | None = None
    stripe_coupon_id: str | None = None
