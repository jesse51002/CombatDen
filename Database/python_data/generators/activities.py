import random
import uuid

from schema.member_activity import MemberActivityCreate
from utils import random_past_datetime

ACTIVITY_TYPES = ["class_attended", "reward_redeemed", "check_in"]

CLASS_NAMES = ["Morning BJJ", "Evening MMA", "Kickboxing", "Open Mat", "Sparring"]
REWARD_NAMES = ["T-Shirt", "Guest Pass", "Protein Shake"]


def _make_info(activity_type: str) -> dict:
    if activity_type == "class_attended":
        return {"class_name": random.choice(CLASS_NAMES)}
    if activity_type == "reward_redeemed":
        return {"reward": random.choice(REWARD_NAMES)}
    return {}


def generate(
    member_id: uuid.UUID,
    gym_id: uuid.UUID,
    count: int,
    current_rank_id: uuid.UUID | None = None,
    current_rank_name: str | None = None,
) -> list[MemberActivityCreate]:
    activities = []
    for _ in range(count):
        act_type = random.choice(ACTIVITY_TYPES)
        activities.append(
            MemberActivityCreate(
                member_id=member_id,
                gym_id=gym_id,
                activity_type=act_type,
                activity_info=_make_info(act_type),
                time=random_past_datetime(60),
            )
        )

    # One rank_changed row per RANKED member — the assignment that put
    # them on their current rank, in the exact shape the backend's
    # insert_rank_activity.sql writes. This is the member-detail
    # progress anchor, so its presence and shape must match production.
    if current_rank_id is not None:
        activities.append(
            MemberActivityCreate(
                member_id=member_id,
                gym_id=gym_id,
                activity_type="rank_changed",
                activity_info={
                    "old_rank_id": None,
                    "new_rank_id": str(current_rank_id),
                    "old_rank_name": None,
                    "new_rank_name": current_rank_name,
                },
                time=random_past_datetime(60),
            )
        )
    return activities
