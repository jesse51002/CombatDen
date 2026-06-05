"""Pydantic schemas for the discounts domain.

Presets are now plain, coupon-free gym config: regular-only (preset | custom),
no Stripe coupon baked in. Each carries a lifetime spec — discount_mode
(once | ongoing) PLUS, for an ongoing discount, an end set by EITHER a duration
span (duration_amount + duration_unit) OR an explicit end_date, never both;
neither = forever. Coupons are computed at sync-time and written back onto the
applied-discount snapshot, never on the preset.
"""

from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, field_validator, model_validator
from schema.gym_discount import (
    DiscountDurationUnit,
    DiscountMode,
    DiscountType,
)

import src.shared.db_schema_path  # noqa: F401


def _validate_lifetime(
    *,
    duration_amount: int | None,
    duration_unit: DiscountDurationUnit | None,
    end_date: date | None,
) -> None:
    """Enforce the lifetime spec: duration span XOR explicit end_date.

    duration_amount and duration_unit travel together; the span and an
    explicit end_date are mutually exclusive; neither set = forever.

    Raises:
        ValueError: If the lifetime fields are inconsistent.
    """
    has_amount = duration_amount is not None
    has_unit = duration_unit is not None
    if has_amount != has_unit:
        raise ValueError(
            "duration_amount and duration_unit must be set together",
        )
    if has_amount and end_date is not None:
        raise ValueError(
            "lifetime is a duration span OR an explicit end_date, never both",
        )


class DiscountCreateRequest(BaseModel):
    """Create a coupon-free, regular-only gym discount preset."""

    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None

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

    @field_validator("duration_amount")
    @classmethod
    def _check_duration_amount(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("duration_amount must be > 0")
        return v

    @model_validator(mode="after")
    def validate_fields(self) -> DiscountCreateRequest:
        """Validate value exclusivity and the lifetime spec."""
        has_pct = self.percentage_off is not None
        has_amt = self.dollar_off is not None
        if has_pct == has_amt:
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set",
            )

        _validate_lifetime(
            duration_amount=self.duration_amount,
            duration_unit=self.duration_unit,
            end_date=self.end_date,
        )
        return self


class DiscountUpdateData(BaseModel):
    """Mutable preset fields. All optional — only send what changed."""

    discount_name: str | None = None
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode | None = None
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None

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

    @field_validator("duration_amount")
    @classmethod
    def _check_duration_amount(cls, v: int | None) -> int | None:
        if v is not None and v <= 0:
            raise ValueError("duration_amount must be > 0")
        return v


class DiscountUpdateRequest(BaseModel):
    """Update a regular discount preset (intent only).

    Edits affect only future applications; existing snapshot rows on
    member_membership_applied_discounts are never touched.
    """

    discount_id: UUID
    gym_id: UUID
    data: DiscountUpdateData


class DiscountResponse(BaseModel):
    """Response after creating, updating, or fetching a discount.

    Combines the identity (gym_discounts) with its ACTIVE value version
    (gym_discount_values). `value_id` is the active version tag; the
    percent/dollar + lifetime come from that version.
    """

    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    value_id: UUID
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None
    is_deleted: bool
    created_at: datetime
