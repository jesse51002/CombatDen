"""Pydantic schemas for the discounts domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, model_validator
from schema.gym_discount import DiscountType

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.payments_enums import StripeCouponDuration


class DiscountCreateRequest(BaseModel):
    """Create a new gym discount with a Stripe coupon."""

    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    percentage_off: float | None = None
    dollar_off: int | None = None
    membership_plan_id: UUID | None = None
    linked_discount_num: int | None = None
    duration: StripeCouponDuration
    duration_in_months: int | None = None

    @model_validator(mode="after")
    def validate_fields(self) -> DiscountCreateRequest:
        """Validate mutual exclusivity and conditional requirements."""
        has_pct = self.percentage_off is not None
        has_amt = self.dollar_off is not None
        if has_pct == has_amt:
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set",
            )

        is_linked = self.discount_type == DiscountType.linked
        has_plan = self.membership_plan_id is not None
        has_num = self.linked_discount_num is not None
        if is_linked and (not has_plan or not has_num):
            raise ValueError(
                "Linked discounts require membership_plan_id and linked_discount_num",
            )
        if not is_linked and (has_plan or has_num):
            raise ValueError(
                "membership_plan_id and linked_discount_num are only for linked discounts",
            )

        if self.duration == StripeCouponDuration.repeating:
            if self.duration_in_months is None:
                raise ValueError(
                    "duration_in_months is required when duration is 'repeating'",
                )
        elif self.duration_in_months is not None:
            raise ValueError(
                "duration_in_months must be None when duration is not 'repeating'",
            )

        return self


class DiscountUpdateData(BaseModel):
    """Mutable discount fields. All optional — only send what changed."""

    discount_name: str | None = None
    percentage_off: float | None = None
    dollar_off: int | None = None
    duration: StripeCouponDuration | None = None
    duration_in_months: int | None = None


class DiscountUpdateRequest(BaseModel):
    """Update a non-linked gym discount.

    Linked discounts cannot be updated via this endpoint.
    """

    discount_id: UUID
    gym_id: UUID
    data: DiscountUpdateData


class DiscountResponse(BaseModel):
    """Response after creating, updating, or fetching a discount."""

    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    percentage_off: float | None = None
    dollar_off: int | None = None
    membership_plan_id: UUID | None = None
    linked_discount_num: int | None = None
    duration: StripeCouponDuration
    duration_in_months: int | None = None
    stripe_coupon_id: str | None = None
    created_at: datetime
