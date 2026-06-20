"""Schemas for the cycle-based class-count endpoint."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import PlanType


class ClassesCycleCountsRequest(BaseModel):
    """Request body for fetching current-cycle class counts.

    Attributes:
        gym_id: The gym to query.
        member_ids: Members to include.
    """

    gym_id: UUID
    member_ids: list[UUID]


class MembershipUsage(BaseModel):
    """Class usage for a single membership within the current billing cycle.

    Usage is keyed per membership (``item_id``), not per plan, so a member
    holding two packs on the same plan gets a separate bucket for each.

    Attributes:
        item_id: The membership row — the consumption bucket.
        plan_id: The membership plan.
        start_date: When this membership started (the oldest pack with
            capacity is drained first).
        plan_type: Trial, one_time, or recurring.
        status: Membership status (active, frozen, ended, cancelled).
        class_count: Max classes allowed (None = unlimited).
        classes_used: Classes attended this cycle.
        classes_remaining: Classes left (None = unlimited).
        renew_date: Next renewal / due date (recurring plans; None
            otherwise).
        end_date: Membership expiry date (trial / one_time plans; None
            otherwise).
    """

    item_id: UUID
    plan_id: UUID
    start_date: date
    plan_type: PlanType
    status: str
    class_count: int | None
    classes_used: int
    classes_remaining: int | None
    renew_date: date | None
    end_date: date | None


class UserCycleCounts(BaseModel):
    """Cycle counts for a single member across all their memberships.

    Attributes:
        member_id: The member.
        memberships: Usage per active membership.
    """

    member_id: UUID
    memberships: list[MembershipUsage]


class ClassesCycleCountsResponse(BaseModel):
    """Response for the cycle-counts endpoint.

    Attributes:
        users: Per-user cycle usage.
    """

    users: list[UserCycleCounts]
