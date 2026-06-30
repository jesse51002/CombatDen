"""Pydantic models for the batch staff check-in endpoint.

POST /api/v1/checkin/batch

The occurrence is addressed by the ``class_id`` + ``occurrence_date`` BODY
fields; the body also carries the gym (for the admin/owner auth gate) and the
members to check in. The endpoint resolves + materializes the single
``class_history`` row ONCE, then runs the per-member gate over each (de-duped)
member. One bad member never sinks the batch — its result is a ``failed`` item —
so the whole call returns 207 Multi-Status with a per-member split (a total
failure is 500; see the FastApiBackend billing-error rule).
"""

from datetime import date
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field

from src.checkin.schema.checkin_schema import CheckinWarning


class BatchCheckinRequest(BaseModel):
    """Body for the batch check-in.

    Attributes:
        gym_id: The owning gym — the admin/owner auth gate is scoped to it.
        class_id: The class to check into.
        occurrence_date: The local calendar date of the occurrence.
        member_ids: The members to check in (at least one; de-duped, order
            preserved).
        is_member: Applies to every member in the batch. ``False`` (the default
            — a staff batch) records every member, attributing to their best
            available membership (NULL when none) and reporting gate conditions
            as ``warnings``. ``True`` runs the strict kiosk gate per member,
            skipping any that no eligible covering membership with capacity
            covers (or that is over capacity).
    """

    gym_id: UUID
    class_id: UUID
    occurrence_date: date
    member_ids: list[UUID] = Field(min_length=1)
    is_member: bool = False


class BatchCheckinItemStatus(StrEnum):
    """Per-member outcome in a batch check-in.

    Attributes:
        checked_in: A new attendance row was recorded (points awarded).
        already_checked_in: An attendance row already existed for this
            (member, occurrence) — idempotent; no capacity consumed, no points
            re-awarded.
        skipped: The strict kiosk gate (``is_member=True``) rejected this member
            (over capacity / no membership / out of classes / ineligible plan);
            nothing written.
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
            already_checked_in); None on skip / fail or a no-membership staff
            check-in.
        log_id: The attendance row (checked_in / already_checked_in); None on
            skip / fail.
        warnings: Gate conditions a staff (``is_member=False``) check-in
            recorded through (empty otherwise).
    """

    member_id: UUID
    status: BatchCheckinItemStatus
    reason: str | None = None
    points_awarded: int = 0
    chosen_plan_id: UUID | None = None
    chosen_item_id: UUID | None = None
    log_id: UUID | None = None
    warnings: list[CheckinWarning] = []


class BatchCheckinResponse(BaseModel):
    """Response body for the batch check-in (returned with 207 Multi-Status).

    Attributes:
        class_id: The class the occurrence belongs to.
        occurrence_date: The local calendar date checked in.
        class_history_id: The single materialized occurrence row every member
            was checked into — exactly one row regardless of member count.
        results: One result per (de-duped) member, in request order.
    """

    class_id: UUID
    occurrence_date: date
    class_history_id: UUID
    results: list[BatchCheckinItemResult]
