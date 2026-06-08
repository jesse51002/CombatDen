"""Request schemas for member membership lifecycle operations."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel, Field, field_validator
from schema.gym_discount import DiscountType

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import CustomDiscountValue


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


class MemberMembershipsStartRequest(BaseModel):
    """Start a new membership for a member.

    Optional discounts-at-creation: ``preset_ids`` reference existing preset /
    linked discounts; ``custom_discounts`` are inline values minted as ``custom``
    discounts at start. Both are snapshotted **before** the first charge, so the
    membership's first (and, for one-time, only) invoice is discounted.
    """

    member_id: UUID
    gym_id: UUID
    plan_id: UUID
    price_id: UUID
    prorate: bool = True
    paid_with_cash: bool = False
    idempotency_key: UUID
    preset_ids: list[UUID] = []
    custom_discounts: list[CustomDiscountValue] = []


class MemberMembershipsMarkPaidCashRequest(BaseModel):
    """Mark a recurring membership's open invoice as paid via cash."""

    item_id: UUID
    member_id: UUID
    idempotency_key: UUID


class MemberMembershipsChargeCardRequest(BaseModel):
    """Charge a member's card for an ad-hoc amount.

    Creates a one-off Stripe invoice (outside any subscription)
    for ``amount_cents`` with ``reason`` used as both the invoice
    description and the invoice item name. ``paid_cash`` routes
    the invoice through the out-of-band payment path instead of
    charging the card.
    """

    member_id: UUID
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
    """Add discount snapshots to a membership (or preview the addition).

    An explicit add of immutable snapshot rows — never a replace-set.
    ``preset_ids`` references live discounts whose ACTIVE value version is frozen
    onto a snapshot (any discount, including a ``linked`` family discount).
    ``preview=True`` stages the adds as ``preview_add`` rows and returns the
    resulting invoice preview without committing.
    """

    item_id: UUID
    member_id: UUID
    preset_ids: list[UUID] = Field(default_factory=list)
    idempotency_key: UUID
    preview: bool = False

    @field_validator("preset_ids")
    @classmethod
    def _validate_preset_ids(cls, value: list[UUID]) -> list[UUID]:
        if not value:
            raise ValueError("preset_ids must not be empty")
        if len(value) != len(set(value)):
            raise ValueError("preset_ids must not contain duplicates")
        return value


class MemberMembershipsRemoveDiscountsRequest(BaseModel):
    """Remove discount snapshots from a membership (or preview the removal).

    ``applied_ids`` deletes existing snapshots by their ``applied_discount_id``.
    ``preview=True`` stages the removal as ``preview_remove`` rows and returns
    the resulting invoice preview without committing.
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
    """A single applied-discount snapshot returned to the client.

    Joins the snapshot to its frozen value version (``value_id``) and owning
    discount (``discount_id`` + name/type) so the CRM can show the discount and
    the exact version it is pinned to.
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
