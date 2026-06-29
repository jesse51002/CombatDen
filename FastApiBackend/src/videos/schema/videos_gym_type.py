"""GymType — the discipline tag on each pooled video.

The fixed, shared vocabulary of fitness *disciplines*. Like the genre tag
(``VideoGenre`` in the Database package), this is a deliberate exception to the
company-agnostic rule: it is a fixed, shared vocabulary every gym draws from,
not a per-company value.

It is *finer* than the 8-bucket parent category a theme carries (Fighting /
Yoga / Pilates / …) — here a discipline is the specific practice (``vinyasa``,
``bjj_gi``, ``rowing``). The classification pass assigns each pooled video a
*list* of these from the video's actual content (a clip can be relevant to
several disciplines, e.g. a kettlebell-rowing finisher -> ``[kettlebell,
rowing]``). A gym then uses its single discipline to pick which slice of the
pool it scans.
"""

from __future__ import annotations

import enum


class GymType(enum.StrEnum):
    """A fitness discipline. A pooled video carries one or more of these."""

    # Fighting
    MMA = "mma"
    BOXING = "boxing"
    MUAY_THAI = "muay_thai"
    KICKBOXING = "kickboxing"
    BJJ_GI = "bjj_gi"
    NO_GI_GRAPPLING = "no_gi_grappling"
    KARATE = "karate"
    TAEKWONDO = "taekwondo"
    KRAV_MAGA = "krav_maga"

    # Yoga
    VINYASA = "vinyasa"
    HATHA = "hatha"
    ASHTANGA = "ashtanga"
    IYENGAR = "iyengar"
    BIKRAM_HOT = "bikram_hot"
    MODERN_HOT = "modern_hot"
    POWER_YOGA = "power_yoga"
    YIN_RESTORATIVE = "yin_restorative"
    YOGA_MEDITATION = "yoga_meditation"
    AERIAL_YOGA = "aerial_yoga"
    ACRO_YOGA = "acro_yoga"
    PRENATAL_YOGA = "prenatal_yoga"

    # Pilates
    REFORMER_CLASSICAL = "reformer_classical"
    REFORMER_CONTEMPORARY = "reformer_contemporary"
    PILATES_CARDIO = "pilates_cardio"
    MAT_PILATES = "mat_pilates"
    LAGREE_MEGAFORMER = "lagree_megaformer"
    HOT_PILATES = "hot_pilates"
    PILATES_SCULPT = "pilates_sculpt"
    PILATES_BOXING = "pilates_boxing"
    PILATES_BARRE = "pilates_barre"
    PRENATAL_PILATES = "prenatal_pilates"

    # Barre
    CLASSIC_BARRE = "classic_barre"
    FLOW_BARRE = "flow_barre"
    CARDIO_BARRE = "cardio_barre"
    DANCE_BARRE = "dance_barre"
    BARRE_YOGA = "barre_yoga"

    # Strength / HIIT
    CROSSFIT = "crossfit"
    FUNCTIONAL_FITNESS = "functional_fitness"
    GROUP_PT = "group_pt"
    BOOTCAMP = "bootcamp"
    F45 = "f45"
    BFT = "bft"
    ORANGETHEORY = "orangetheory"
    HYROX = "hyrox"
    CALISTHENICS = "calisthenics"
    KETTLEBELL = "kettlebell"
    POWERLIFTING = "powerlifting"
    OLYMPIC_WEIGHTLIFTING = "olympic_weightlifting"
    STRONGMAN = "strongman"
    TACTICAL_FITNESS = "tactical_fitness"
    TRX_SUSPENSION = "trx_suspension"

    # Cardio
    INDOOR_CYCLING = "indoor_cycling"
    SPRINT_CYCLING = "sprint_cycling"
    POWER_CYCLING = "power_cycling"
    SPIN_STRENGTH = "spin_strength"
    AQUA_CYCLING = "aqua_cycling"
    ROWING = "rowing"
    RUNNING = "running"
    TREADMILL = "treadmill"
    TREAD_STRENGTH = "tread_strength"
    STAIR_CLIMBER = "stair_climber"
    VERSACLIMBER = "versaclimber"
    TRAMPOLINE = "trampoline"
    CARDIO_BOXING = "cardio_boxing"
    CARDIO_CIRCUIT = "cardio_circuit"
    DANCE_CARDIO = "dance_cardio"

    # Dance
    DANCE_FITNESS = "dance_fitness"
    BALLET = "ballet"
    HIP_HOP = "hip_hop"
    POLE = "pole"
    AERIAL_SILKS = "aerial_silks"

    # Wellness
    BREATHWORK = "breathwork"
    MEDITATION = "meditation"
    MOBILITY_RECOVERY = "mobility_recovery"
    STRETCH = "stretch"
    SAUNA_COLD_PLUNGE = "sauna_cold_plunge"
