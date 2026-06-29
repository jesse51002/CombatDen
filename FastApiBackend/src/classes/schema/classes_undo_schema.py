"""Pydantic models for un-occurring (cancelling) and rescheduling a single
class occurrence — Phase 6 of the class system.

Two billing-adjacent operations on one materialized (or not-yet-materialized)
occurrence:

* **Cancel / un-occur** — drops the materialized ``class_history`` row and its
  ``member_attendance``, reverses an auto-end-on-depletion ``end_date`` on the
  trial / one_time packs that were drawn for it, and writes the cancelled
  instance exception so the occurrence never re-materializes. Points are NEVER
  clawed back.
* **Reschedule** — moves a future occurrence to a later date by upserting the
  instance exception's ``new_date`` (no history / attendance touched).
"""

from datetime import date
from uuid import UUID

from pydantic import BaseModel


class OccurrenceCancelResponse(BaseModel):
    """Result of cancelling (un-occurring) a single class occurrence.

    Attributes:
        class_id: The class the occurrence belongs to.
        gym_id: The owning gym.
        occurrence_date: The gym-local calendar date that was cancelled.
        class_history_id: The materialized occurrence that was deleted, or None
            when the occurrence had never been materialized (no check-ins yet) —
            in which case only the cancelled exception is written.
        attendance_rows_deleted: How many ``member_attendance`` rows were
            removed (0 when nothing was materialized).
        memberships_unended: ``item_id``s of trial / one_time memberships whose
            auto-end-on-depletion ``end_date`` was cleared because un-occurring
            this class dropped them back below their pack capacity.
    """

    class_id: UUID
    gym_id: UUID
    occurrence_date: date
    class_history_id: UUID | None
    attendance_rows_deleted: int
    memberships_unended: list[UUID]


class OccurrenceRescheduleRequest(BaseModel):
    """Body for rescheduling a single occurrence to a later date.

    Attributes:
        gym_id: The owning gym (used for the auth gate + the exception row).
        new_date: The date to move the occurrence to (must be strictly after
            the original occurrence date).
    """

    gym_id: UUID
    new_date: date


class OccurrenceRescheduleResponse(BaseModel):
    """Result of rescheduling a single class occurrence.

    Attributes:
        exception_id: The upserted ``class_instance_exceptions`` row.
        class_id: The class the occurrence belongs to.
        original_date: The occurrence's original (pre-move) date.
        new_date: Where the occurrence now lands.
    """

    exception_id: UUID
    class_id: UUID
    original_date: date
    new_date: date
