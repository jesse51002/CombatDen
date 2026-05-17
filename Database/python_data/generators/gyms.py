import random
import uuid

from schema.gym import GymCreate

NAME_PREFIXES = [
    "Iron",
    "Dragon",
    "Phoenix",
    "Tiger",
    "Apex",
    "Elite",
    "Warrior",
    "Thunder",
    "Storm",
    "Shadow",
    "Titan",
    "Viper",
]
NAME_SUFFIXES = [
    "MMA",
    "Dojo",
    "Academy",
    "Fight Club",
    "Martial Arts",
    "Combat",
    "Training Center",
    "Gym",
    "Athletics",
]

DESCRIPTION_TEMPLATES = [
    "World-class {style} training for all skill levels. Join our community of dedicated martial artists.",
    "Premier {style} facility offering expert instruction and a supportive training environment.",
    "Train with champions. Our {style} programs build discipline, fitness, and self-defense skills.",
    "Welcome to the best {style} experience in town. Classes for beginners to advanced competitors.",
]

STYLES = [
    "MMA",
    "Brazilian Jiu-Jitsu",
    "Muay Thai",
    "boxing",
    "wrestling",
    "martial arts",
]


def generate(gym_id: uuid.UUID | None = None) -> GymCreate:
    name = f"{random.choice(NAME_PREFIXES)} {random.choice(NAME_SUFFIXES)}"
    description = random.choice(DESCRIPTION_TEMPLATES).format(style=random.choice(STYLES))
    return GymCreate(
        gym_id=gym_id or uuid.uuid4(),
        gym_name=name,
        gym_description=description,
    )
