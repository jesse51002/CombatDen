"""Pydantic models for class sign-ups (reservations)."""

from datetime import date, time
from uuid import UUID

from pydantic import BaseModel


class SignupRequest(BaseModel):
    """Body for POST /api/v1/signup.

    Reserves ``member_id`` a spot on the occurrence addressed by ``class_id``
    + ``occurrence_date`` + ``occurrence_time`` (the gym-local original slot
    the class runs — a class may occur several times on one day, so the date
    alone never identifies an occurrence). A sign-up is a reservation, NOT
    attendance — ``member_attendance`` is still only written by a check-in; a
    signed-up member who never checks in is a no-show, never auto-counted as
    attended.

    Both staff (any employee of the gym) and the member themselves may create
    a sign-up — the same ``verify_can_view_member`` auth check the check-in
    endpoints use. Idempotent: signing up twice for the same (member,
    occurrence) is a no-op (``already_signed_up=true``), consuming no extra
    capacity.
    """

    member_id: UUID
    gym_id: UUID
    class_id: UUID
    occurrence_date: date
    occurrence_time: time


class SignupResponse(BaseModel):
    """Response for POST /api/v1/signup.

    Attributes:
        signup_id: The sign-up row — the existing row's id on an idempotent
            repeat.
        already_signed_up: True when the member already had a sign-up for
            this occurrence (idempotent repeat); no new row was written and
            no capacity was consumed.
    """

    signup_id: UUID
    already_signed_up: bool


class SignupRemoveResponse(BaseModel):
    """Response for DELETE /api/v1/signup.

    Attributes:
        removed: True when a sign-up row was deleted; False when the member
            had no sign-up for this occurrence.
    """

    removed: bool
