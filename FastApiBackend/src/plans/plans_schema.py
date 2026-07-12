"""Pydantic schemas for the membership plans domain."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, field_validator, model_validator
from schema.membership_plan import DurationUnit, PlanType

import src.shared.db_schema_path  # noqa: F401

# ── Shared field validators ──────────────────────────────────


def _validate_plan_name(v: str | None) -> str | None:
    """Reject empty / whitespace-only plan names."""
    if v is not None and not v.strip():
        raise ValueError("plan_name cannot be empty")
    return v


def _validate_class_count(v: int | None) -> int | None:
    if v is not None and v <= 0:
        raise ValueError("class_count must be > 0")
    return v


def _validate_duration_amount(v: int | None) -> int | None:
    if v is not None and v <= 0:
        raise ValueError("duration_amount must be > 0")
    return v


def _validate_price(v: int) -> int:
    if v < 0:
        raise ValueError("price must be >= 0")
    return v


# ── Create ───────────────────────────────────────────────────


class MembershipPlanCreateRequest(BaseModel):
    """Create a membership plan with an initial price."""

    gym_id: UUID
    plan_name: str
    # Every plan HAS an image (the plan card leans on it), mirroring
    # gym_classes.image_url — required at create time.
    image_url: str
    plan_type: PlanType
    class_count: int | None = None
    duration_amount: int | None = None
    duration_unit: DurationUnit | None = None
    is_public: bool = True
    price: int
    waiver_ids: list[UUID] = []

    _v_plan_name = field_validator("plan_name")(_validate_plan_name)
    _v_class_count = field_validator("class_count")(_validate_class_count)
    _v_duration_amount = field_validator("duration_amount")(
        _validate_duration_amount,
    )
    _v_price = field_validator("price")(_validate_price)

    @model_validator(mode="after")
    def validate_plan_constraints(self) -> MembershipPlanCreateRequest:
        """Enforce DB CHECK constraints on the API side."""
        _check_plan_constraints(
            plan_type=self.plan_type,
            duration_amount=self.duration_amount,
            duration_unit=self.duration_unit,
            class_count=self.class_count,
        )
        return self


# ── Update ───────────────────────────────────────────────────


class MembershipPlanUpdateData(BaseModel):
    """Mutable plan fields. All optional — only send what changed.

    ``plan_type`` is intentionally absent: a plan's billing model is fixed at
    creation (immutable — see ``MEMBERSHIP_PLANS`` in ``immutable_columns.py``
    and the ``trg_prevent_plan_type_overwrite`` DB trigger).
    """

    plan_name: str | None = None
    image_url: str | None = None
    class_count: int | None = None
    duration_amount: int | None = None
    duration_unit: DurationUnit | None = None
    is_public: bool | None = None
    waiver_ids: list[UUID] | None = None

    _v_plan_name = field_validator("plan_name")(_validate_plan_name)
    _v_class_count = field_validator("class_count")(_validate_class_count)
    _v_duration_amount = field_validator("duration_amount")(
        _validate_duration_amount,
    )


class MembershipPlanUpdateRequest(BaseModel):
    """Update a membership plan. Separates IDs from mutable data."""

    plan_id: UUID
    gym_id: UUID
    data: MembershipPlanUpdateData


# ── Price ────────────────────────────────────────────────────


class MembershipPlanPriceRequest(BaseModel):
    """Set / update the active price on a plan."""

    plan_id: UUID
    gym_id: UUID
    price: int

    _v_price = field_validator("price")(_validate_price)


# ── Response ─────────────────────────────────────────────────


class MembershipPlanPriceResponse(BaseModel):
    """Price details for a membership plan."""

    price_id: UUID
    plan_id: UUID
    gym_id: UUID
    stripe_price_id: str
    price: int
    is_active: bool
    created_at: datetime


class MembershipPlanPriceWithCount(MembershipPlanPriceResponse):
    """A plan price version plus how many members are still on it.

    Drives the edit-mode price list: the active price plus any older
    version that still has members (``member_count > 0``) the gym can
    upgrade onto the current price (via the per-plan reprice).
    """

    member_count: int


class MembershipPlanResponse(BaseModel):
    """Membership plan with its active price."""

    plan_id: UUID
    gym_id: UUID
    plan_name: str
    image_url: str
    plan_type: PlanType
    class_count: int | None = None
    duration_amount: int | None = None
    duration_unit: DurationUnit | None = None
    is_public: bool
    stripe_product_id: str | None = None
    created_at: datetime
    active_price: MembershipPlanPriceResponse | None = None
    # Count of active memberships on this plan. Populated by the list endpoint;
    # the single-plan get defaults it to 0 (its SQL omits the subquery).
    enrolled_count: int = 0
    # Waivers a member must sign for this plan (waiver_id strings).
    waiver_ids: list[UUID] = []


# ── Constraint helpers ───────────────────────────────────────


def _check_plan_constraints(
    *,
    plan_type: PlanType,
    duration_amount: int | None,
    duration_unit: DurationUnit | None,
    class_count: int | None,
) -> None:
    """Validate the DB CHECK constraints for a plan.

    Raises:
        ValueError: On constraint violation.
    """
    # recurring_must_be_monthly
    if plan_type == PlanType.recurring and (
        duration_unit != DurationUnit.month or duration_amount != 1
    ):
        raise ValueError(
            "Recurring plans must have duration_unit='month' and duration_amount=1",
        )

    # duration_both_or_neither
    has_amount = duration_amount is not None
    has_unit = duration_unit is not None
    if has_amount != has_unit:
        raise ValueError(
            "duration_amount and duration_unit must both be set or both be null",
        )

    # duration_required_unless_class_count
    has_duration = has_amount and has_unit
    has_classes = class_count is not None
    if plan_type == PlanType.recurring and not has_duration:
        raise ValueError("Recurring plans require duration fields")
    if not has_duration and not has_classes:
        raise ValueError(
            "Plans need either duration fields or class_count",
        )
