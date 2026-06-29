"""Pydantic models for the classes domain."""

from datetime import date, datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import PlanType


class CheckinSkipReason(StrEnum):
    """Why a non-override check-in was skipped (no attendance written).

    Attributes:
        no_membership: The member has no active membership to attribute to.
        no_eligible_plan: No active membership covers this class with remaining
            capacity (eligibility / punch-card gate).
        capacity_full: The room is at ``max_capacity`` for this occurrence.
    """

    no_membership = "no_membership"
    no_eligible_plan = "no_eligible_plan"
    capacity_full = "capacity_full"


class CheckinRequest(BaseModel):
    """Body for POST /api/v1/classes/checkin.

    The occurrence is addressed by ``class_id`` + ``occurrence_date`` (the local
    calendar date the class runs); the backend resolves / lazily materializes
    the ``class_history`` row. ``allow_override`` forces the check-in past the
    eligibility, punch-card, and room-capacity gates (front-desk coverage),
    attributing to the member's best active membership even if depleted.
    """

    member_id: UUID
    gym_id: UUID
    class_id: UUID
    occurrence_date: date
    allow_override: bool = False


class OccurrenceContext(BaseModel):
    """A resolved, materialized class occurrence — the input to a per-member
    check-in.

    Produced by ``ClassesCheckinService.resolve_occurrence`` once per
    occurrence, then reused to check in one or many members (Phase 4b batch).

    Attributes:
        class_history_id: The materialized occurrence row (find-or-create).
        class_id: The owning class.
        gym_id: The owning gym.
        occurred_at: UTC, timezone-aware start instant of the occurrence.
        points_worth: Points awarded for attending this class.
        class_name: The class's display name (snapshotted into the activity).
        max_capacity: Effective room capacity (the instance exception's
            ``new_max_capacity`` if set, else the class's ``max_capacity``);
            None = unlimited.
        allowed_plan_ids: Plans permitted to attend (None = all). Carried for
            context; the eligibility gate queries this in SQL.
        instructor_id: Effective instructor for the occurrence (None = none).
        duration_minutes: Effective length of the occurrence in minutes.
    """

    class_history_id: UUID
    class_id: UUID
    gym_id: UUID
    occurred_at: datetime
    points_worth: int
    class_name: str
    max_capacity: int | None
    allowed_plan_ids: list[UUID] | None
    instructor_id: UUID | None
    duration_minutes: int


class CheckinMembershipBreakdown(BaseModel):
    """Usage breakdown for one of the member's active memberships.

    Attributes:
        item_id: The membership row (the bucket this usage belongs to).
        plan_id: The membership plan.
        plan_type: Trial, one_time, or recurring.
        class_count: Max classes allowed (None = unlimited).
        classes_used: Classes used this cycle (post-checkin for the
            charged membership).
        classes_remaining: Classes left (None = unlimited).
        is_eligible: Whether this plan covers the checked-in class.
        renew_date: Next renewal / due date (recurring plans; None
            otherwise).
        end_date: Membership expiry date (trial / one_time plans; None
            otherwise).
    """

    item_id: UUID
    plan_id: UUID
    plan_type: PlanType
    class_count: int | None
    classes_used: int
    classes_remaining: int | None
    is_eligible: bool
    renew_date: date | None
    end_date: date | None


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
        class_history_id: The resolved/materialized class instance attended.
        class_id: The class the occurrence belongs to.
        already_checked_in: True when an attendance row already existed
            for this (member, class instance) — the check-in was
            idempotent and no capacity was consumed.
        chosen_plan_id: The plan charged. None when rejected.
        chosen_item_id: The membership row charged. None when rejected.
        points_awarded: Points added to the member's balance — the class's
            ``points_worth`` on a newly-recorded check-in, 0 on an idempotent
            repeat or a skip.
        skip_reason: Why the check-in was skipped (no attendance written);
            None when recorded or an idempotent repeat.
        memberships: Breakdown of the member's active memberships.
    """

    log_id: UUID | None
    member_id: UUID
    class_history_id: UUID
    class_id: UUID
    already_checked_in: bool
    chosen_plan_id: UUID | None = None
    chosen_item_id: UUID | None = None
    points_awarded: int = 0
    skip_reason: CheckinSkipReason | None = None
    memberships: list[CheckinMembershipBreakdown] = []


class StreakResponse(BaseModel):
    """Response for GET /api/v1/classes/streak."""

    member_id: UUID
    class_streak_weeks: int
