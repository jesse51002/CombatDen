from datetime import date
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class MemberActiveType(StrEnum):
    """Mirrors the Postgres `member_active_type` enum in member_active.sql.

    Tracks class-engagement state, distinct from member_status (which
    tracks membership tier). A member can be member_status=full but
    member_active=inactive when they haven't shown up to class.
    """

    active = "active"
    inactive = "inactive"


class MemberActiveCreate(SeedModel):
    active_id: UUID
    member_id: UUID
    gym_id: UUID
    active_type: MemberActiveType
    start_date: date
    end_date: date | None = None
