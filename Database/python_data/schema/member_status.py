from datetime import date
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class MemberStatusType(StrEnum):
    """Mirrors the Postgres `member_status_type` enum in member_status.sql.

    Stored: trial / full / disabled. There is no `inactive` here — that's
    derived from absence of any member_status row covering today, and
    `inactive` / `active` belong to class-attendance engagement, not
    membership tier.
    """

    trial = "trial"
    full = "full"
    disabled = "disabled"


class MemberStatusCreate(SeedModel):
    status_id: UUID
    member_id: UUID
    gym_id: UUID
    status_type: MemberStatusType
    start_date: date
    end_date: date | None = None
