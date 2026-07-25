import random
import uuid

from schema.gym_reward import GymRewardCreate

# MIRROR OF THE PRESET REWARD CATALOGUE — keep the two in step. The
# authoritative source is `VideoService/gyms/*.yaml` (`rewards:`), synced into
# `template_gym_reward` and imported by a real owner through the backend's
# preset path. These entries are copied VERBATIM so a seeded gym is
# indistinguishable from a preset-imported one (no demo-only data shapes). Do
# NOT add a reward that the preset catalogue does not have.
#
# Literals, not a live read of `template_gym_reward`, because `make seed` runs
# this BEFORE `sync-gyms` populates that table — sampling it on a fresh reset
# would yield zero rewards and zero redemptions. Invert that ordering and this
# module should read the table instead.
#
# Only the combat-appropriate gear items are mirrored: CombatDen seeds bjj /
# mma / generic gyms, so barre, yoga and cycling gear reads as "not my gym".
#
# `price_label` is the member card's VALUE BADGE, not a description — a short
# pill ("Free", "25% off"), and it must be TRUE for its title. There is no
# description column, so do NOT park subtitle copy in it.
REWARD_TEMPLATES = [
    # --- the three every preset gym gets ---
    {
        "title": "Bring a friend",
        "price_label": "Free",
        "point_cost": 1000,
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg",
    },
    {
        "title": "Club t-shirt",
        "price_label": "Free",
        "point_cost": 1500,
        "image_url": "https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200",
    },
    {
        "title": "1-on-1 PT session",
        "price_label": "50% off",
        "point_cost": 2500,
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG",
    },
    # --- the discipline gear item; combat-appropriate entries only ---
    # boxing / cardio_boxing / kickboxing / krav_maga / mma / muay_thai
    {
        "title": "Boxing gloves",
        "price_label": "25% off",
        "point_cost": 2000,
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/c/c8/Boxing_gloves_Bail_10-OZ_%281%29.jpg",
    },
    # conditioning gyms (bft / bootcamp / crossfit / functional_fitness / ...)
    {
        "title": "Jump rope",
        "price_label": "25% off",
        "point_cost": 2000,
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/f/fd/BeadedRope.jpg",
    },
    # no_gi_grappling (plus dance / rowing / sauna templates)
    {
        "title": "Water bottle",
        "price_label": "25% off",
        "point_cost": 2000,
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/4/45/Metal_Water_Bottles.jpeg",
    },
]


# The first UNIVERSAL_COUNT templates are the rewards EVERY preset gym gets;
# the rest are the interchangeable discipline gear slot.
UNIVERSAL_COUNT = 3


def generate(gym_id: uuid.UUID, count: int) -> list[GymRewardCreate]:
    # Mirror the catalogue's COMPOSITION, not just its contents: pin the
    # universals, sample only the gear slot. A flat sample over all six could
    # deal a gym four discounted items and no "Free" reward — a lineup no
    # preset-imported gym can have.
    universals = REWARD_TEMPLATES[:UNIVERSAL_COUNT]
    gear = REWARD_TEMPLATES[UNIVERSAL_COUNT:]
    templates = universals[:count]
    gear_slots = count - len(templates)
    if gear_slots > 0:
        templates = templates + random.sample(gear, min(gear_slots, len(gear)))
    return [
        GymRewardCreate(
            reward_id=uuid.uuid4(),
            gym_id=gym_id,
            is_active=random.random() > 0.2,
            **t,
        )
        for t in templates
    ]
