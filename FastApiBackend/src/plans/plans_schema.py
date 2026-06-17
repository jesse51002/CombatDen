"""Pydantic schemas for the membership plans domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, field_validator, model_validator
from schema.membership_plan import DurationUnit, PlanType

import src.shared.db_schema_path  # noqa: F401

# A linked (family) discount supports up to this many extra-member tiers
# (2nd..5th member — a hard cap of 5 members on the membership).
MAX_LINKED_TIERS = 4

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


class LinkedDiscountValue(BaseModel):
    """One family tier's discount — a real discount value ($ off or % off).

    Exactly one of ``percentage_off`` / ``dollar_off`` is set, mirroring a
    regular discount (`gym_discount_values`). The backend mints a real
    ``linked`` discount entry per tier on write and stores the ids in
    ``membership_plans.linked_discount_ids``; reads resolve them back here.
    """

    percentage_off: float | None = None
    dollar_off: int | None = None

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

    @model_validator(mode="after")
    def _validate_exactly_one(self) -> LinkedDiscountValue:
        if (self.percentage_off is not None) == (self.dollar_off is not None):
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set",
            )
        return self


def _validate_linked_values(
    v: list[LinkedDiscountValue] | None,
) -> list[LinkedDiscountValue] | None:
    """Cap the family tiers at ``MAX_LINKED_TIERS`` (max 5 members)."""
    if v is not None and len(v) > MAX_LINKED_TIERS:
        raise ValueError(
            f"linked_discount_values supports at most {MAX_LINKED_TIERS} tiers",
        )
    return v


# ── Create ───────────────────────────────────────────────────


class MembershipPlanCreateRequest(BaseModel):
    """Create a membership plan with an initial price."""

    gym_id: UUID
    plan_name: str
    plan_type: PlanType
    class_count: int | None = None
    duration_amount: int | None = None
    duration_unit: DurationUnit | None = None
    is_public: bool = True
    price: int
    waiver_ids: list[UUID] = []
    linked_discount_enabled: bool = False
    linked_discount_values: list[LinkedDiscountValue] = []

    _v_plan_name = field_validator("plan_name")(_validate_plan_name)
    _v_class_count = field_validator("class_count")(_validate_class_count)
    _v_duration_amount = field_validator("duration_amount")(
        _validate_duration_amount,
    )
    _v_price = field_validator("price")(_validate_price)
    _v_linked_values = field_validator("linked_discount_values")(
        _validate_linked_values,
    )

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
    class_count: int | None = None
    duration_amount: int | None = None
    duration_unit: DurationUnit | None = None
    is_public: bool | None = None
    waiver_ids: list[UUID] | None = None
    linked_discount_enabled: bool | None = None
    linked_discount_values: list[LinkedDiscountValue] | None = None

    _v_plan_name = field_validator("plan_name")(_validate_plan_name)
    _v_class_count = field_validator("class_count")(_validate_class_count)
    _v_duration_amount = field_validator("duration_amount")(
        _validate_duration_amount,
    )
    _v_linked_values = field_validator("linked_discount_values")(
        _validate_linked_values,
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
    # Per-plan linked (family) member discount config. The column stores
    # `linked_discount_ids` (real `linked` discount entries the backend mints
    # from the entered values); `linked_discount_values` is the resolved
    # $ off / % off per tier (2nd..5th member) so the CRM can display/edit them.
    linked_discount_enabled: bool = False
    linked_discount_ids: list[UUID] = []
    linked_discount_values: list[LinkedDiscountValue] = []


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
