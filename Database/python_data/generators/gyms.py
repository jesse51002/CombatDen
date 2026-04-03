import random
import uuid
from typing import Optional

from schema.gym import GymCreate

NAME_PREFIXES = [
    "Iron", "Dragon", "Phoenix", "Tiger", "Apex", "Elite", "Warrior",
    "Thunder", "Storm", "Shadow", "Titan", "Viper",
]
NAME_SUFFIXES = [
    "MMA", "Dojo", "Academy", "Fight Club", "Martial Arts", "Combat",
    "Training Center", "Gym", "Athletics",
]


def generate(gym_id: Optional[uuid.UUID] = None) -> GymCreate:
    name = f"{random.choice(NAME_PREFIXES)} {random.choice(NAME_SUFFIXES)}"
    return GymCreate(
        gym_id=gym_id or uuid.uuid4(),
        gym_name=name,
    )
