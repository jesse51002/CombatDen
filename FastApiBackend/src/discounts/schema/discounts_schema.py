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

from pydantic import BaseModel, Field, field_validator, model_validator
from schema.gym_discount import (
    DiscountDurationUnit,
    DiscountMode,
    DiscountType,
)

import src.shared.db_schema_path  # noqa: F401


def validate_lifetime(
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


class CustomDiscountValue(BaseModel):
    """An inline custom discount value to mint + apply at membership creation.

    Mirrors a ``gym_discount_values`` row — the ``gym_id``, name, and ``custom``
    type are supplied by the membership flow that mints it. A percent XOR a fixed
    dollar amount, the once/ongoing mode, and the ongoing lifetime spec (a
    duration span XOR an explicit ``end_date``, never both; neither = forever).
    """

    percentage_off: float | None = Field(default=None, gt=0, le=100)
    dollar_off: int | None = Field(default=None, gt=0)
    discount_mode: DiscountMode
    duration_amount: int | None = Field(default=None, gt=0)
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None

    @model_validator(mode="after")
    def _validate(self) -> CustomDiscountValue:
        """Value is percent XOR dollar; the lifetime spec is consistent."""
        if (self.percentage_off is None) == (self.dollar_off is None):
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set",
            )
        validate_lifetime(
            duration_amount=self.duration_amount,
            duration_unit=self.duration_unit,
            end_date=self.end_date,
        )
        return self


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

        validate_lifetime(
            duration_amount=self.duration_amount,
            duration_unit=self.duration_unit,
            end_date=self.end_date,
        )
        return self


class DiscountUpdateIdentity(BaseModel):
    """Identity change → rename the gym_discounts row in place.

    The discount's IDENTITY (gym_discounts) holds only the editable name;
    everything else is a versioned value (see DiscountUpdateValues).
    """

    discount_name: str | None = None

    @field_validator("discount_name")
    @classmethod
    def _check_name(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("discount_name cannot be empty")
        return v


class DiscountUpdateValues(BaseModel):
    """Value/lifetime change → mint a new gym_discount_values version.

    Every field here lands on a fresh, immutable value version (the prior
    active one is deactivated). The model's shape is the partition: anything
    on this sub-model routes to a new version, never to the identity row.
    """

    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode | None = None
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None

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

    The request shape encodes the destination: `identity` renames the
    gym_discounts row in place; `values` mints a new gym_discount_values
    version. At least one must be present. Edits affect only future
    applications; existing snapshot rows on
    member_membership_applied_discounts are never touched.
    """

    discount_id: UUID
    gym_id: UUID
    identity: DiscountUpdateIdentity | None = None
    values: DiscountUpdateValues | None = None

    @model_validator(mode="after")
    def _require_identity_or_values(self) -> DiscountUpdateRequest:
        """At least one destination must carry a change."""
        if self.identity is None and self.values is None:
            raise ValueError(
                "at least one of identity or values must be provided",
            )
        return self


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
