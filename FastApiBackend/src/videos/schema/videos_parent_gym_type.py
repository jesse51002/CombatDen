"""ParentGymType — the coarse parent category of a fine ``GymType`` discipline.

The 8-bucket vocabulary the template browser filters by (Fighting / Yoga / … ).
Every fine discipline rolls up to exactly one parent here (``vinyasa`` -> Yoga,
``mma`` -> Fighting). This roll-up is gym business logic that lives in the videos
domain — not in ThemeService, which only produces themes.
"""

from __future__ import annotations

import enum

from src.videos.schema.videos_gym_type import GymType


class ParentGymType(enum.StrEnum):
    """The coarse gym-type bucket — a discipline's parent category."""

    FIGHTING = "Fighting"
    YOGA = "Yoga"
    PILATES = "Pilates"
    BARRE = "Barre"
    HIIT = "HIIT"
    CARDIO = "Cardio"
    DANCE = "Dance"
    WELLNESS = "Wellness"


# Each fine discipline's parent bucket. Exhaustive over GymType (a guard test
# asserts every GymType is mapped, so a new discipline must add its parent).
PARENT_OF: dict[GymType, ParentGymType] = {
    # Fighting
    GymType.MMA: ParentGymType.FIGHTING,
    GymType.BOXING: ParentGymType.FIGHTING,
    GymType.MUAY_THAI: ParentGymType.FIGHTING,
    GymType.KICKBOXING: ParentGymType.FIGHTING,
    GymType.BJJ_GI: ParentGymType.FIGHTING,
    GymType.NO_GI_GRAPPLING: ParentGymType.FIGHTING,
    GymType.KARATE: ParentGymType.FIGHTING,
    GymType.TAEKWONDO: ParentGymType.FIGHTING,
    GymType.KRAV_MAGA: ParentGymType.FIGHTING,
    # Yoga
    GymType.VINYASA: ParentGymType.YOGA,
    GymType.HATHA: ParentGymType.YOGA,
    GymType.ASHTANGA: ParentGymType.YOGA,
    GymType.IYENGAR: ParentGymType.YOGA,
    GymType.BIKRAM_HOT: ParentGymType.YOGA,
    GymType.MODERN_HOT: ParentGymType.YOGA,
    GymType.POWER_YOGA: ParentGymType.YOGA,
    GymType.YIN_RESTORATIVE: ParentGymType.YOGA,
    GymType.YOGA_MEDITATION: ParentGymType.YOGA,
    GymType.AERIAL_YOGA: ParentGymType.YOGA,
    GymType.ACRO_YOGA: ParentGymType.YOGA,
    GymType.PRENATAL_YOGA: ParentGymType.YOGA,
    # Pilates
    GymType.REFORMER_CLASSICAL: ParentGymType.PILATES,
    GymType.REFORMER_CONTEMPORARY: ParentGymType.PILATES,
    GymType.PILATES_CARDIO: ParentGymType.PILATES,
    GymType.MAT_PILATES: ParentGymType.PILATES,
    GymType.LAGREE_MEGAFORMER: ParentGymType.PILATES,
    GymType.HOT_PILATES: ParentGymType.PILATES,
    GymType.PILATES_BOXING: ParentGymType.PILATES,
    GymType.PILATES_BARRE: ParentGymType.PILATES,
    GymType.PILATES_SCULPT: ParentGymType.PILATES,
    GymType.PRENATAL_PILATES: ParentGymType.PILATES,
    # Barre
    GymType.CLASSIC_BARRE: ParentGymType.BARRE,
    GymType.FLOW_BARRE: ParentGymType.BARRE,
    GymType.CARDIO_BARRE: ParentGymType.BARRE,
    GymType.DANCE_BARRE: ParentGymType.BARRE,
    GymType.BARRE_YOGA: ParentGymType.BARRE,
    # HIIT / strength
    GymType.CROSSFIT: ParentGymType.HIIT,
    GymType.FUNCTIONAL_FITNESS: ParentGymType.HIIT,
    GymType.GROUP_PT: ParentGymType.HIIT,
    GymType.BOOTCAMP: ParentGymType.HIIT,
    GymType.F45: ParentGymType.HIIT,
    GymType.BFT: ParentGymType.HIIT,
    GymType.ORANGETHEORY: ParentGymType.HIIT,
    GymType.HYROX: ParentGymType.HIIT,
    GymType.CALISTHENICS: ParentGymType.HIIT,
    GymType.KETTLEBELL: ParentGymType.HIIT,
    GymType.POWERLIFTING: ParentGymType.HIIT,
    GymType.OLYMPIC_WEIGHTLIFTING: ParentGymType.HIIT,
    GymType.STRONGMAN: ParentGymType.HIIT,
    GymType.TACTICAL_FITNESS: ParentGymType.HIIT,
    GymType.TRX_SUSPENSION: ParentGymType.HIIT,
    # Cardio
    GymType.INDOOR_CYCLING: ParentGymType.CARDIO,
    GymType.SPRINT_CYCLING: ParentGymType.CARDIO,
    GymType.POWER_CYCLING: ParentGymType.CARDIO,
    GymType.SPIN_STRENGTH: ParentGymType.CARDIO,
    GymType.AQUA_CYCLING: ParentGymType.CARDIO,
    GymType.ROWING: ParentGymType.CARDIO,
    GymType.RUNNING: ParentGymType.CARDIO,
    GymType.TREADMILL: ParentGymType.CARDIO,
    GymType.TREAD_STRENGTH: ParentGymType.CARDIO,
    GymType.STAIR_CLIMBER: ParentGymType.CARDIO,
    GymType.VERSACLIMBER: ParentGymType.CARDIO,
    GymType.TRAMPOLINE: ParentGymType.CARDIO,
    GymType.CARDIO_BOXING: ParentGymType.CARDIO,
    GymType.CARDIO_CIRCUIT: ParentGymType.CARDIO,
    GymType.DANCE_CARDIO: ParentGymType.CARDIO,
    # Dance
    GymType.DANCE_FITNESS: ParentGymType.DANCE,
    GymType.BALLET: ParentGymType.DANCE,
    GymType.HIP_HOP: ParentGymType.DANCE,
    GymType.POLE: ParentGymType.DANCE,
    GymType.AERIAL_SILKS: ParentGymType.DANCE,
    # Wellness
    GymType.BREATHWORK: ParentGymType.WELLNESS,
    GymType.MEDITATION: ParentGymType.WELLNESS,
    GymType.MOBILITY_RECOVERY: ParentGymType.WELLNESS,
    GymType.STRETCH: ParentGymType.WELLNESS,
    GymType.SAUNA_COLD_PLUNGE: ParentGymType.WELLNESS,
}


def parent_of(gym_type: GymType) -> ParentGymType:
    """The parent bucket for one fine discipline."""
    return PARENT_OF[gym_type]
