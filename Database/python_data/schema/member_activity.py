from datetime import datetime
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class MemberActivityType(StrEnum):
    """Mirrors the Postgres `member_activity_type` enum in
    schemas/member_activities.sql — the kinds of member activity the feed
    records."""

    class_attended = "class_attended"
    rank_changed = "rank_changed"
    video_clicked = "video_clicked"


class MemberActivityCreate(SeedModel):
    member_id: UUID
    gym_id: UUID
    activity_type: MemberActivityType
    activity_info: dict = {}
    time: datetime | None = None
