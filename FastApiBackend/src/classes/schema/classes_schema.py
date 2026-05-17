"""Pydantic models for the classes domain."""

from uuid import UUID

from pydantic import BaseModel


class CheckinRequest(BaseModel):
    """Body for POST /api/v1/classes/checkin."""

    member_id: UUID
    gym_id: UUID
    class_history_id: UUID


class CheckinResponse(BaseModel):
    """Response for POST /api/v1/classes/checkin."""

    log_id: UUID
    member_id: UUID
    class_history_id: UUID
    already_checked_in: bool


class StreakResponse(BaseModel):
    """Response for GET /api/v1/classes/streak."""

    member_id: UUID
    class_streak_weeks: int
