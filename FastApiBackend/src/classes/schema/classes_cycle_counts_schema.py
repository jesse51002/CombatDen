"""Schemas for the cycle-based class-count endpoint."""

from uuid import UUID

from pydantic import BaseModel

from src.classes.schema.classes_plan_type import PlanType


class ClassesCycleCountsRequest(BaseModel):
    """Request body for fetching current-cycle class counts.

    Attributes:
        gym_id: The gym to query.
        crm_user_ids: Members to include.
    """

    gym_id: UUID
    crm_user_ids: list[UUID]


class MembershipUsage(BaseModel):
    """Class usage for a single membership within the current billing cycle.

    Attributes:
        plan_id: The membership plan.
        plan_type: Trial, one_time, or recurring.
        status: Membership status (active, frozen, ended, cancelled).
        class_count: Max classes allowed (None = unlimited).
        classes_used: Classes attended this cycle.
        classes_remaining: Classes left (None = unlimited).
    """

    plan_id: UUID
    plan_type: PlanType
    status: str
    class_count: int | None
    classes_used: int
    classes_remaining: int | None


class UserCycleCounts(BaseModel):
    """Cycle counts for a single member across all their memberships.

    Attributes:
        crm_user_id: The member.
        memberships: Usage per active membership.
    """

    crm_user_id: UUID
    memberships: list[MembershipUsage]


class ClassesCycleCountsResponse(BaseModel):
    """Response for the cycle-counts endpoint.

    Attributes:
        users: Per-user cycle usage.
    """

    users: list[UserCycleCounts]
