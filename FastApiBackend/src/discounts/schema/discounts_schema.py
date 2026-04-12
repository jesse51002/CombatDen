"""Pydantic schemas for the discounts domain."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, field_validator, model_validator
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

    @field_validator("discount_name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("discount_name cannot be empty")
        return v

    @field_validator("percentage_off")
    @classmethod
    def _check_percentage(cls, v: float | None) -> float | None:
        if v is not None and (v <= 0 or v > 100):
            raise ValueError("percentage_off must be in (0, 100]")
        return v

    @field_validator("dollar_off")
    @classmethod
    def _check_dollar(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("dollar_off must be > 0")
        return v

    @field_validator("linked_discount_num")
    @classmethod
    def _check_linked_num(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("linked_discount_num must be > 0")
        return v

    @field_validator("duration_in_months")
    @classmethod
    def _check_duration_in_months(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("duration_in_months must be > 0")
        return v

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
        if is_linked and (not has_plan or not has_num or not has_amt):
            raise ValueError(
                "Linked discounts require membership_plan_id, linked_discount_num, and dollar_off",
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

    @field_validator("discount_name")
    @classmethod
    def _check_name(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("discount_name cannot be empty")
        return v

    @field_validator("percentage_off")
    @classmethod
    def _check_percentage(cls, v: float | None) -> float | None:
        if v is not None and (v <= 0 or v > 100):
            raise ValueError("percentage_off must be in (0, 100]")
        return v

    @field_validator("dollar_off")
    @classmethod
    def _check_dollar(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("dollar_off must be > 0")
        return v

    @field_validator("duration_in_months")
    @classmethod
    def _check_duration_in_months(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("duration_in_months must be > 0")
        return v


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
