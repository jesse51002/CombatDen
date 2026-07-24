import random
import uuid

from schema.gym_reward import GymRewardCreate

# ---------------------------------------------------------------------------
# MIRROR OF THE PRESET REWARD CATALOGUE — keep the two in step.
#
# AUTHORITATIVE SOURCE: `VideoService/gyms/*.yaml` (each file's `rewards:`
# block). Those rows are synced into `template_gym_reward` by
# `VideoService/scripts/shared/video_db_writer.py` (via
# `VideoService/scripts/sql/insert_gym_reward.sql`), and a real gym owner
# imports them into `gym_rewards` through the backend's production preset
# path (`FastApiBackend/src/presets/sql/presets_insert_reward.sql`).
#
# The entries below are copied VERBATIM from that catalogue — same titles,
# same value badges, same point costs, same image URLs — so a seeded gym is
# indistinguishable from a gym that imported presets. That is the point:
# `FastApiBackend/CLAUDE.md` ("Domain builds") forbids demo-only data shapes,
# and a seed that invents its own reward vocabulary is exactly that. Do NOT
# add a reward here that does not exist in the preset catalogue.
#
# WHY LITERALS AND NOT A LIVE READ OF `template_gym_reward`:
# `Database/Makefile`'s `seed` target runs `python python_data/main.py` FIRST
# and `make -C ../VideoService sync-gyms` SECOND, so on a fresh
# `make reset && make seed` the template table is still EMPTY at the moment
# rewards are seeded. Sampling it would yield zero rewards (and therefore zero
# redemptions). If that ordering is ever inverted, switch this module to read
# `template_gym_reward` directly and delete the literals.
#
# WHICH SLICE: the preset catalogue gives every gym 3 universal rewards
# (Bring a friend / Club t-shirt / 1-on-1 PT session) plus ONE
# discipline-specific gear item. Only the combat-sports-appropriate gear items
# are mirrored here — CombatDen seeds bjj / mma / generic gyms, so barre,
# yoga, cycling and running gear would read as "not my gym".
#
# `price_label` is the member card's VALUE BADGE, not a description: a short
# pill (aim <= 16 chars) like "Free", "25% off". `gym_rewards` has no
# description column, so subtitle copy has nowhere to live here — do NOT park
# it in this field. The badge must also be TRUE for its title: a discounted
# item never reads "Free", and a comped one never reads "% off". The preset
# catalogue uses only "Free" / "25% off" / "50% off"; stay inside that set.
# ---------------------------------------------------------------------------
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
    # Mirror the preset catalogue's COMPOSITION, not just its contents: pin the
    # universals and sample only the gear slot. A flat sample over all six could
    # deal a gym four discounted items and no "Free" reward at all (1 draw in
    # 15) — a lineup no preset-imported gym can ever have.
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
