import random
import uuid

from schema.gym_reward import GymRewardCreate

REWARD_TEMPLATES = [
    {"title": "Free T-Shirt", "subtitle": "Official gym branded tee", "point_cost": 200},
    {"title": "Private Lesson", "subtitle": "1-on-1 with an instructor", "point_cost": 500},
    {"title": "Guest Pass", "subtitle": "Bring a friend for free", "point_cost": 100},
    {"title": "Protein Shake", "subtitle": "Post-workout recovery", "point_cost": 50},
    {"title": "Gym Bag", "subtitle": "Branded duffel bag", "point_cost": 350},
    {"title": "Competition Entry", "subtitle": "Free entry to next tournament", "point_cost": 400},
    {"title": "Month Extension", "subtitle": "Add 1 week to membership", "point_cost": 300},
]


def generate(gym_id: uuid.UUID, count: int) -> list[GymRewardCreate]:
    templates = random.sample(REWARD_TEMPLATES, min(count, len(REWARD_TEMPLATES)))
    return [
        GymRewardCreate(
            reward_id=uuid.uuid4(),
            gym_id=gym_id,
            is_active=random.random() > 0.2,
            **t,
        )
        for t in templates
    ]
