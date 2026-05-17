import random
import uuid

from schema.member_activity import MemberActivityCreate
from utils import random_past_datetime

ACTIVITY_TYPES = ["class_attended", "rank_promoted", "reward_redeemed", "check_in"]

CLASS_NAMES = ["Morning BJJ", "Evening MMA", "Kickboxing", "Open Mat", "Sparring"]
REWARD_NAMES = ["T-Shirt", "Guest Pass", "Protein Shake"]


def _make_info(activity_type: str) -> dict:
    if activity_type == "class_attended":
        return {"class_name": random.choice(CLASS_NAMES)}
    if activity_type == "rank_promoted":
        return {"new_rank": random.randint(2, 5)}
    if activity_type == "reward_redeemed":
        return {"reward": random.choice(REWARD_NAMES)}
    return {}


def generate(member_id: uuid.UUID, gym_id: uuid.UUID, count: int) -> list[MemberActivityCreate]:
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
    return activities
