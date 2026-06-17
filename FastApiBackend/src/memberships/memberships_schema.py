"""Request schemas for member membership lifecycle operations."""

from datetime import date
from enum import StrEnum
from typing import Self
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator
from schema.gym_discount import DiscountType
from schema.membership_plan import PlanType

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


class MemberMembershipsStartRequest(BaseModel):
    """Start a linked family's memberships in one call.

    The payer (``payer_member_id``) is identity-only — it need not appear in
    ``memberships``. Every non-payer member must ALREADY be linked to this
    payer (linking is a separate, prior operation; the start op never links).
    ``prorate`` applies to the recurring converge only; ``paid_with_cash``
    is request-level (the consolidated one-time invoice is one charge). The
    single ``idempotency_key`` deterministically derives one sub-key per
    charge group (one-time invoice / recurring converge), so a client retry
    of the same request dedups both charges at Stripe.

    ``custom_payment_method_id`` charges the consolidated ONE-TIME invoice
    with a specific card (a one-off card entered at checkout) instead of the
    payer's saved default; the recurring converge always uses the saved
    default. ``custom_card_set_default`` then promotes that card to the
    payer's saved default — but ONLY after the whole request succeeds, so a
    failed charge never changes the saved card. Both are card-only
    (mutually exclusive with ``paid_with_cash``) and the start op rejects a
    custom card on a request with no one-time / trial group.
    """

    payer_member_id: UUID
    gym_id: UUID
    prorate: bool = True
    paid_with_cash: bool = False
    custom_payment_method_id: str | None = None
    custom_card_set_default: bool = False
    idempotency_key: UUID
    memberships: list[MemberMembershipsStartItem] = Field(
        default_factory=list,
    )

    @model_validator(mode="after")
    def _validate_custom_card(self) -> Self:
        """A one-off card is card-only and required for the set-default flag."""
        if self.custom_payment_method_id is not None and self.paid_with_cash:
            raise ValueError(
                "custom_payment_method_id cannot be combined with "
                "paid_with_cash (a cash settle charges no card)",
            )
        if self.custom_card_set_default and self.custom_payment_method_id is None:
            raise ValueError(
                "custom_card_set_default requires custom_payment_method_id",
            )
        return self

    @field_validator("memberships")
    @classmethod
    def _validate_memberships(
        cls,
        value: list[MemberMembershipsStartItem],
    ) -> list[MemberMembershipsStartItem]:
        if not value:
            raise ValueError("memberships must not be empty")
        pairs = [(item.member_id, item.price_id) for item in value]
        if len(pairs) != len(set(pairs)):
            raise ValueError(
                "memberships must not contain duplicate (member_id, price_id) pairs",
            )
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
    invoice charged immediately; present ONLY when ``prorate=True`` and
    ``None`` otherwise (a non-prorating start charges nothing extra now).
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


class MemberMembershipsUpdatePriceRequest(BaseModel):
    """Upgrade a membership to its plan's currently active price.

    The target price is not caller-supplied: the service
    always moves the membership onto the plan's single
    ``is_active = true`` price. If the membership is already
    there the call is a CRM no-op but still re-syncs Stripe.
    """

    item_id: UUID
    member_id: UUID
    prorate: bool = False
    idempotency_key: UUID


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
