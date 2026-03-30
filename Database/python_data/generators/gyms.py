import random
import uuid

from schema.gym import GymCreate

RANK_PRESETS = {
    "bjj": ["White", "Blue", "Purple", "Brown", "Black"],
    "muay_thai": ["White", "Yellow", "Green", "Red", "Black"],
    "karate": ["White", "Yellow", "Green", "Brown", "Black"],
    "taekwondo": ["White", "Yellow", "Green", "Blue", "Black"],
    "judo": ["White", "Yellow", "Orange", "Green", "Brown"],
    "mma": ["Beginner", "Intermediate", "Advanced", "Elite", "Pro"],
}

NAME_PREFIXES = [
    "Iron", "Dragon", "Phoenix", "Tiger", "Apex", "Elite", "Warrior",
    "Thunder", "Storm", "Shadow", "Titan", "Viper",
]
NAME_SUFFIXES = [
    "MMA", "Dojo", "Academy", "Fight Club", "Martial Arts", "Combat",
    "Training Center", "Gym", "Athletics",
]


def generate(owner_id: str) -> GymCreate:
    preset = random.choice(list(RANK_PRESETS.keys()))
    ranks = RANK_PRESETS[preset]
    name = f"{random.choice(NAME_PREFIXES)} {random.choice(NAME_SUFFIXES)}"
    return GymCreate(
        gym_id=uuid.uuid4(),
        gym_name=name,
        owner_id=owner_id,
        rank_preset=preset,
        rank_1_name=ranks[0],
        rank_2_name=ranks[1],
        rank_3_name=ranks[2],
        rank_4_name=ranks[3],
        rank_5_name=ranks[4],
    )
