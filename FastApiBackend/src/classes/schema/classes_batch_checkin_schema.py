"""Pydantic models for the batch staff check-in endpoint.

POST /api/v1/classes/{class_id}/occurrences/{occurrence_date}/checkin-batch

The occurrence is addressed by the ``class_id`` + ``occurrence_date`` PATH
params; the body carries the gym (for the admin/owner auth gate) and the
members to check in. The endpoint resolves + materializes the single
``class_history`` row ONCE, then runs the Phase-4 per-member gate over each
(de-duped) member. One bad member never sinks the batch — its result is a
``failed`` item — so the whole call returns 207 Multi-Status with a per-member
split (a total failure is 500; see the FastApiBackend billing-error rule).
"""

from datetime import date
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field


class BatchCheckinRequest(BaseModel):
    """Body for the batch check-in.

    ``class_id`` and ``occurrence_date`` are PATH params, not body fields.

    Attributes:
        gym_id: The owning gym — the admin/owner auth gate is scoped to it.
        member_ids: The members to check in (at least one; de-duped, order
            preserved).
        allow_override: When True, force every member's check-in past the
            eligibility, punch-card, and room-capacity gates (front-desk
            coverage), attributing to each member's best active membership even
            if depleted. A member with no active membership is still skipped.
    """

    gym_id: UUID
    member_ids: list[UUID] = Field(min_length=1)
    allow_override: bool = False


class BatchCheckinItemStatus(StrEnum):
    """Per-member outcome in a batch check-in.

    Attributes:
        checked_in: A new attendance row was recorded (points awarded).
        already_checked_in: An attendance row already existed for this
            (member, occurrence) — idempotent; no capacity consumed, no points
            re-awarded.
        skipped: The gate rejected this member (capacity full / no membership /
            no eligible plan); nothing written.
        failed: An unexpected error hit this member; the rest of the batch was
            still processed.
    """

    checked_in = "checked_in"
    already_checked_in = "already_checked_in"
    skipped = "skipped"
    failed = "failed"


class BatchCheckinItemResult(BaseModel):
    """One member's result inside a batch check-in.

    Attributes:
        member_id: The member this result is for.
        status: checked_in / already_checked_in / skipped / failed.
        reason: The skip reason (skipped) or the error message (failed); None
            when checked_in / already_checked_in.
        points_awarded: Points added to the member's balance — the class's
            ``points_worth`` on a fresh check-in, 0 otherwise.
        chosen_plan_id: The plan charged (checked_in / already_checked_in);
            None on skip / fail.
        chosen_item_id: The membership row charged (checked_in /
            already_checked_in); None on skip / fail.
        log_id: The attendance row (checked_in / already_checked_in); None on
            skip / fail.
    """

    member_id: UUID
    status: BatchCheckinItemStatus
    reason: str | None = None
    points_awarded: int = 0
    chosen_plan_id: UUID | None = None
    chosen_item_id: UUID | None = None
    log_id: UUID | None = None


class BatchCheckinResponse(BaseModel):
    """Response body for the batch check-in (returned with 207 Multi-Status).

    Attributes:
        class_id: The class the occurrence belongs to.
        occurrence_date: The local calendar date checked in (PATH param).
        class_history_id: The single materialized occurrence row every member
            was checked into — exactly one row regardless of member count.
        results: One result per (de-duped) member, in request order.
    """

    class_id: UUID
    occurrence_date: date
    class_history_id: UUID
    results: list[BatchCheckinItemResult]
