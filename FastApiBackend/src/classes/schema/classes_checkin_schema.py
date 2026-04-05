"""Schemas for the class check-in endpoint."""

from uuid import UUID

from pydantic import BaseModel

from src.classes.schema.classes_plan_type import PlanType


class ClassesCheckinRequest(BaseModel):
    """Request body for checking a member into a class.

    Attributes:
        crm_user_id: The member checking in.
        gym_id: The gym where the class takes place.
        class_id: The class being attended.
    """

    crm_user_id: UUID
    gym_id: UUID
    class_id: UUID


class CheckinMembershipBreakdown(BaseModel):
    """Usage breakdown for one membership after check-in.

    Attributes:
        plan_id: The membership plan.
        plan_type: Trial, one_time, or recurring.
        class_count: Max classes allowed (None = unlimited).
        classes_used: Classes used this cycle (post-checkin).
        classes_remaining: Classes left (None = unlimited).
        is_eligible: Whether this plan covers the checked-in class.
    """

    plan_id: UUID
    plan_type: PlanType
    class_count: int | None
    classes_used: int
    classes_remaining: int | None
    is_eligible: bool


class ClassesCheckinResponse(BaseModel):
    """Response for the check-in endpoint.

    Attributes:
        log_id: The newly created log entry. None if check-in
            was not possible.
        chosen_plan_id: The plan that was charged. None if no
            eligible plan with capacity was found.
        memberships: Full breakdown of all active memberships.
    """

    log_id: UUID | None
    chosen_plan_id: UUID | None
    memberships: list[CheckinMembershipBreakdown]
