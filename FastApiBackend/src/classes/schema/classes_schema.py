"""Pydantic models for the classes domain."""

from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import PlanType


class CheckinRequest(BaseModel):
    """Body for POST /api/v1/classes/checkin."""

    member_id: UUID
    gym_id: UUID
    class_history_id: UUID


class CheckinMembershipBreakdown(BaseModel):
    """Usage breakdown for one of the member's active memberships.

    Attributes:
        plan_id: The membership plan.
        plan_type: Trial, one_time, or recurring.
        class_count: Max classes allowed (None = unlimited).
        classes_used: Classes used this cycle (post-checkin for the
            charged plan).
        classes_remaining: Classes left (None = unlimited).
        is_eligible: Whether this plan covers the checked-in class.
    """

    plan_id: UUID
    plan_type: PlanType
    class_count: int | None
    classes_used: int
    classes_remaining: int | None
    is_eligible: bool


class CheckinResponse(BaseModel):
    """Response for POST /api/v1/classes/checkin.

    The check-in is gated: a covering active membership with remaining
    capacity must exist or the check-in is rejected (``log_id`` /
    ``chosen_plan_id`` / ``chosen_item_id`` are ``None`` and no
    attendance row is written). The ``memberships`` breakdown explains
    the decision either way.

    Attributes:
        log_id: The attendance row. None when the check-in was rejected.
        member_id: The member who checked in.
        class_history_id: The class instance attended.
        already_checked_in: True when an attendance row already existed
            for this (member, class instance) — the check-in was
            idempotent and no capacity was consumed.
        chosen_plan_id: The plan charged. None when rejected.
        chosen_item_id: The membership row charged. None when rejected.
        memberships: Breakdown of the member's active memberships.
    """

    log_id: UUID | None
    member_id: UUID
    class_history_id: UUID
    already_checked_in: bool
    chosen_plan_id: UUID | None = None
    chosen_item_id: UUID | None = None
    memberships: list[CheckinMembershipBreakdown] = []


class StreakResponse(BaseModel):
    """Response for GET /api/v1/classes/streak."""

    member_id: UUID
    class_streak_weeks: int
