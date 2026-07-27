"""Schemas for a member's class history (the member-page history card).

One member's relationship with class occurrences over time, split into two
lists the CRM renders as one card:

* ``upcoming`` — reservations for occurrences that haven't ENDED yet
  (soonest first, unpaginated — a member holds few open reservations).
* ``history`` — newest first, paginated: every ATTENDED occurrence plus
  every NO-SHOW (a reservation whose occurrence ended with no matching
  attendance). "Past means ended, not started" — an in-session reservation
  is still ``upcoming``, not yet a no-show.
"""

from datetime import date, datetime, time
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel


class MemberClassHistoryStatus(StrEnum):
    """How the member relates to one occurrence."""

    reserved = "reserved"
    attended = "attended"
    no_show = "no_show"


class MemberClassHistoryRow(BaseModel):
    """One occurrence in a member's class history.

    Attributes:
        class_id: The class.
        class_name: Display name (joined from ``gym_classes``).
        image_url: The class image, if any.
        original_date: The occurrence's identity date (the original slot).
        original_time: The occurrence's identity time.
        duration_minutes: The class's length (the CURRENT schedule
            version's — the same approximation the ended-ness split uses),
            so the card can render a start–end time range.
        points_worth: The class's ``points_worth`` — what attending this
            class awards (the points earned on an ``attended`` row; the
            potential award on a reservation/no-show).
        occurred_at: The attendance row's effective start instant —
            attended rows only (None for reservations / no-shows, which
            have no attendance row to read it from).
        status: reserved / attended / no_show.
    """

    class_id: UUID
    class_name: str
    image_url: str
    original_date: date
    original_time: time
    duration_minutes: int
    points_worth: int
    occurred_at: datetime | None
    status: MemberClassHistoryStatus


class MemberClassHistoryResponse(BaseModel):
    """The member-page class-history card's feed.

    Attributes:
        upcoming: Open reservations, soonest first (unpaginated).
        history: Attended + no-show rows, newest first (paginated).
        has_more: Whether more history rows exist past this page.
    """

    upcoming: list[MemberClassHistoryRow]
    history: list[MemberClassHistoryRow]
    has_more: bool
