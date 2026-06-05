"""Request schemas for member membership lifecycle operations."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator
from schema.gym_discount import DiscountType

import src.shared.db_schema_path  # noqa: F401


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

    Memberships are created discount-free — discounts are applied as
    immutable snapshots afterward via the apply path (PUT /discounts), not
    threaded in at creation.
    """

    member_id: UUID
    gym_id: UUID
    plan_id: UUID
    price_id: UUID
    prorate: bool = True
    paid_with_cash: bool = False
    idempotency_key: UUID


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


class MemberMembershipsApplyDiscountsRequest(BaseModel):
    """Add / remove discount snapshots on an existing membership.

    Apply is an explicit add / remove of immutable snapshot rows — never a
    replace-set. ``add_preset_ids`` references live discounts whose ACTIVE value
    version is frozen onto a snapshot (any discount, including a ``linked``
    family discount). ``remove_applied_ids`` deletes existing snapshots by their
    ``applied_discount_id``. Editing a discount is removing one row and adding
    another — a snapshot is never updated.
    """

    item_id: UUID
    member_id: UUID
    add_preset_ids: list[UUID] = Field(default_factory=list)
    remove_applied_ids: list[UUID] = Field(default_factory=list)
    idempotency_key: UUID

    @field_validator("add_preset_ids", "remove_applied_ids")
    @classmethod
    def _reject_duplicates(cls, value: list[UUID]) -> list[UUID]:
        if len(value) != len(set(value)):
            raise ValueError("id lists must not contain duplicates")
        return value

    @model_validator(mode="after")
    def _reject_empty(self) -> MemberMembershipsApplyDiscountsRequest:
        if not (self.add_preset_ids or self.remove_applied_ids):
            raise ValueError(
                "apply request must add or remove at least one discount",
            )
        return self


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
