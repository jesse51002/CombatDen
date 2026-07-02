"""Pydantic models for un-occurring (cancelling) and rescheduling a single
class occurrence.

Two billing-adjacent operations on one occurrence (identity: ``class_id`` +
its ORIGINAL slot — date AND time, since a class may occur several times on
one day):

* **Cancel / un-occur** — reverses the occurrence's ``member_attendance``
  (points clawed back, pack auto-ends reversed), deletes its sign-ups (a
  cancelled occurrence can't be attended), and writes the cancelled instance
  exception.
* **Reschedule** — moves an occurrence to ``new_date`` (any date — past,
  today, or future) by upserting the instance exception's ``new_date``. The
  occurrence's identity key never changes, so reservations always carry;
  attendance follows the move, decided by the new EFFECTIVE start INSTANT
  (never the calendar day): a target instant still ahead of now — including
  later today — wipes the occurrence's check-ins (points clawed back); an
  already-past target instant keeps them with their denormalized
  ``occurred_at`` re-synced.
"""

from datetime import date, time
from uuid import UUID

from pydantic import BaseModel


class OccurrenceCancelResponse(BaseModel):
    """Result of cancelling (un-occurring) a single class occurrence.

    Attributes:
        class_id: The class the occurrence belongs to.
        gym_id: The owning gym.
        occurrence_date: The cancelled occurrence's ORIGINAL date.
        occurrence_time: The cancelled occurrence's ORIGINAL slot time —
            together with the date, the exact occurrence; a same-day sibling
            slot is untouched.
        attendance_rows_deleted: How many ``member_attendance`` rows were
            reversed (0 when nobody had checked in).
        signups_deleted: How many sign-ups for the occurrence were deleted.
        memberships_unended: ``item_id``s of trial / one_time memberships whose
            auto-end-on-depletion ``end_date`` was cleared because un-occurring
            this class dropped them back below their pack capacity.
    """

    class_id: UUID
    gym_id: UUID
    occurrence_date: date
    occurrence_time: time
    attendance_rows_deleted: int
    signups_deleted: int
    memberships_unended: list[UUID]


class OccurrenceRescheduleRequest(BaseModel):
    """Body for rescheduling a single occurrence.

    Attributes:
        gym_id: The owning gym (used for the auth gate + the exception row).
        new_date: The date to move the occurrence to — any date (past, today,
            or future); the original occurrence date is only the anchor, not a
            lower bound.
    """

    gym_id: UUID
    new_date: date


class OccurrenceRescheduleResponse(BaseModel):
    """Result of rescheduling a single class occurrence.

    Attributes:
        exception_id: The upserted ``class_instance_exceptions`` row.
        class_id: The class the occurrence belongs to.
        original_date: The occurrence's original (pre-move) date.
        original_time: The occurrence's original slot time (never moves —
            the identity anchor).
        new_date: Where the occurrence now lands.
    """

    exception_id: UUID
    class_id: UUID
    original_date: date
    original_time: time
    new_date: date
