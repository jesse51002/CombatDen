"""Pydantic schemas for the discounts domain.

Presets are now plain, coupon-free gym config: regular-only (preset | custom),
no Stripe coupon baked in. Each carries a lifetime spec — an end set by EITHER a
duration span (duration_amount + duration_unit, where ``cycle`` is one plan
billing cycle) OR an explicit end_date, never both; neither = forever. A 1-cycle
span is the single-invoice discount that replaced the old ``once`` mode. Coupons
are computed at sync-time and written back onto the applied-discount row, never
on the preset.

``DiscountValue`` is the single shared shape for a discount value version —
everything that determines the discount (how much, how long it lasts). Create
requests, update requests, responses, and the membership start's inline customs
all carry one; there is no flat duplicate of these fields anywhere in the API.
"""

from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator
from schema.gym_discount import (
    DiscountDurationUnit,
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


class DiscountValue(BaseModel):
    """One discount value version — everything that determines the discount.

    Mirrors a ``gym_discount_values`` row: how much (a percent XOR a fixed
    dollar amount in cents) and how long it lasts (a duration span XOR an
    explicit ``end_date``, never both; neither = forever). A 1-``cycle`` span is
    the single-invoice discount that replaced the old ``once`` mode.
    """

    percentage_off: float | None = Field(default=None, gt=0, le=100)
    dollar_off: int | None = Field(default=None, gt=0)
    duration_amount: int | None = Field(default=None, gt=0)
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None

    @model_validator(mode="after")
    def _validate(self) -> DiscountValue:
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
    """Create a coupon-free gym discount: identity + its first value version."""

    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    value: DiscountValue

    @field_validator("discount_name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("discount_name cannot be empty")
        return v


class DiscountUpdateIdentity(BaseModel):
    """Identity change → rename the gym_discounts row in place.

    The discount's IDENTITY (gym_discounts) holds only the editable name;
    everything else is a versioned value (see DiscountValue).
    """

    discount_name: str | None = None

    @field_validator("discount_name")
    @classmethod
    def _check_name(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("discount_name cannot be empty")
        return v


class DiscountUpdateRequest(BaseModel):
    """Update a regular discount preset (intent only).

    The request shape encodes the destination: `identity` renames the
    gym_discounts row in place; `value` mints a new gym_discount_values
    version from the COMPLETE spec sent — the client always sends the full
    ``DiscountValue``, never a partial merge with the current version. At
    least one must be present. Edits affect only future applications;
    existing applied-discount rows on member_membership_applied_discounts are
    never touched.
    """

    discount_id: UUID
    gym_id: UUID
    identity: DiscountUpdateIdentity | None = None
    value: DiscountValue | None = None

    @model_validator(mode="after")
    def _require_identity_or_value(self) -> DiscountUpdateRequest:
        """At least one destination must carry a change."""
        if self.identity is None and self.value is None:
            raise ValueError(
                "at least one of identity or value must be provided",
            )
        return self


class DiscountResponse(BaseModel):
    """Response after creating, updating, or fetching a discount.

    Combines the identity (gym_discounts) with its ACTIVE value version
    (gym_discount_values). `value_id` is the active version tag; `value` is
    that version's spec.
    """

    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    value_id: UUID
    value: DiscountValue
    is_deleted: bool
    created_at: datetime

    @classmethod
    def from_row(cls, row: dict) -> DiscountResponse:
        """Build the nested response from a flat identity+value DB row.

        The one place the flat SQL row shape (gym_discounts joined to its
        active gym_discount_values version) maps to the nested API shape.
        """
        return cls(
            discount_id=row["discount_id"],
            gym_id=row["gym_id"],
            discount_name=row["discount_name"],
            discount_type=row["discount_type"],
            value_id=row["value_id"],
            value=DiscountValue(
                percentage_off=row.get("percentage_off"),
                dollar_off=row.get("dollar_off"),
                duration_amount=row.get("duration_amount"),
                duration_unit=row.get("duration_unit"),
                end_date=row.get("end_date"),
            ),
            is_deleted=row["is_deleted"],
            created_at=row["created_at"],
        )
