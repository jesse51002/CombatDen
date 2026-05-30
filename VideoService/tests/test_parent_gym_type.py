"""ParentGymType roll-up: every fine discipline must map to a parent bucket."""

from __future__ import annotations

from schema.gym_type import GymType
from schema.parent_gym_type import PARENT_OF, ParentGymType, parent_of


def test_every_gym_type_has_a_parent() -> None:
    missing = [g.value for g in GymType if g not in PARENT_OF]
    assert not missing, f"GymType(s) with no parent bucket: {missing}"


def test_parent_lookup() -> None:
    assert parent_of(GymType.VINYASA) is ParentGymType.YOGA
    assert parent_of(GymType.MMA) is ParentGymType.FIGHTING
    assert parent_of(GymType.ROWING) is ParentGymType.CARDIO


def test_eight_parent_buckets() -> None:
    # The coarse vocabulary stays the 8 buckets the picker filters by.
    assert {p.value for p in ParentGymType} == {
        "Fighting", "Yoga", "Pilates", "Barre", "HIIT", "Cardio", "Dance", "Wellness",
    }
