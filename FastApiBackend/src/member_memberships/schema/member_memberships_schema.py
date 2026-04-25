"""Request schemas for member membership lifecycle operations."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class MemberMembershipsCancelResponse(BaseModel):
    """Response returned after cancelling a membership."""

    cancel_date: date


class MemberMembershipsFreezeRequest(BaseModel):
    """Freeze a member's account (account-level)."""

    crm_user_id: UUID
    gym_id: UUID
    freeze_months: int = Field(..., gt=0)
    idempotency_key: UUID


class MemberMembershipsUnfreezeRequest(BaseModel):
    """Unfreeze a member's account (account-level)."""

    crm_user_id: UUID
    gym_id: UUID
    idempotency_key: UUID


class MemberMembershipsStartRequest(BaseModel):
    """Start a new membership for a member."""

    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    price_id: UUID
    discount_ids: list[UUID] | None = None
    include_linked_discount: bool = False
    prorate: bool = True
    paid_with_cash: bool = False
    idempotency_key: UUID


class MemberMembershipsMarkPaidCashRequest(BaseModel):
    """Mark a recurring membership's open invoice as paid via cash."""

    item_id: UUID
    crm_user_id: UUID
    idempotency_key: UUID


class MemberMembershipsChargeCardRequest(BaseModel):
    """Charge a member's card for an ad-hoc amount.

    Creates a one-off Stripe invoice (outside any subscription)
    for ``amount_cents`` with ``reason`` used as both the invoice
    description and the invoice item name. ``paid_cash`` routes
    the invoice through the out-of-band payment path instead of
    charging the card.
    """

    crm_user_id: UUID
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
    crm_user_id: UUID
    prorate: bool = False
    idempotency_key: UUID


class MemberMembershipsUpdateDiscountsRequest(BaseModel):
    """Replace the discount set on an existing membership.

    ``discount_ids`` is the full desired list — an empty list
    detaches every discount currently on the membership.
    """

    item_id: UUID
    crm_user_id: UUID
    discount_ids: list[UUID]
    idempotency_key: UUID

    @field_validator("discount_ids")
    @classmethod
    def _reject_duplicates(cls, value: list[UUID]) -> list[UUID]:
        if len(value) != len(set(value)):
            raise ValueError("discount_ids must not contain duplicates")
        return value
