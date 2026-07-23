"""Schemas for the cycle-based class-count endpoint."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import PlanType


class CheckinCycleCountsRequest(BaseModel):
    """Request body for fetching current-cycle class counts.

    Attributes:
        gym_id: The gym to query.
        member_ids: Members to include.
    """

    gym_id: UUID
    member_ids: list[UUID]


class MembershipUsage(BaseModel):
    """Class usage for a single membership within the current billing cycle.

    Usage is keyed per membership (``item_id``), not per plan, so a separate
    membership on the same plan (e.g. another pack bought later) gets its own
    bucket. A stacked pack bought N at once is ONE membership whose bucket holds
    ``class_count * quantity`` classes (computed in ``classes_all_memberships.sql``).

    Attributes:
        item_id: The membership row — the consumption bucket.
        plan_id: The membership plan.
        start_date: When this membership started (the oldest pack with
            capacity is drained first).
        plan_type: Trial, one_time, or recurring.
        status: Membership status as of NOW (active, frozen, ended,
            cancelled) — display only; the gate predicate is
            ``covers_reference``.
        covers_reference: Whether the membership was ACTIVE at the reference
            instant the counts were evaluated for (the occurrence being
            checked into; now when no reference was passed — then it equals
            ``status == active``). THE check-in gate's candidacy predicate:
            an ended trial still covers a class that ran inside its window;
            a membership started after the occurrence does not.
        reference_date: The gym-LOCAL date of that same reference instant
            (today when no reference was passed). Carried so a consumer can
            evaluate a date rule against the occurrence rather than against
            a bare UTC "now" — the check-in gate's overdue warning compares
            ``renew_date`` to this, staying occurrence-anchored exactly like
            ``covers_reference``.
        class_count: Max classes allowed for this membership — the plan's
            ``class_count`` times the membership's ``quantity`` (None =
            unlimited). NOT the raw plan value when the pack is stacked.
        classes_used: Classes attended in the billing cycle CONTAINING the
            reference instant (the current cycle when no reference).
        classes_remaining: Classes left in that cycle (None = unlimited).
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
    covers_reference: bool = True
    reference_date: date
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


class CheckinCycleCountsResponse(BaseModel):
    """Response for the cycle-counts endpoint.

    Attributes:
        users: Per-user cycle usage.
    """

    users: list[UserCycleCounts]
