"""Unit tests for ``StreakService._build_week_days`` (pure static, no DB).

Turns the week's Postgres ISODOW numbers (1 = Monday .. 7 = Sunday) into the
length-7, MONDAY-FIRST ``list[bool]`` the kiosk strip draws (index 0 = Monday
.. 6 = Sunday).
"""

from src.checkin.service.streak_service import StreakService


def test_no_attendance_is_all_false() -> None:
    assert StreakService._build_week_days([]) == [False] * 7


def test_monday_only_sets_index_zero() -> None:
    """ISODOW 1 (Monday) lands at index 0."""
    assert StreakService._build_week_days([1]) == [
        True,
        False,
        False,
        False,
        False,
        False,
        False,
    ]


def test_sunday_only_sets_index_six() -> None:
    """ISODOW 7 (Sunday) lands at index 6, not index 0 -- Monday-first."""
    assert StreakService._build_week_days([7]) == [
        False,
        False,
        False,
        False,
        False,
        False,
        True,
    ]


def test_mon_wed_fri() -> None:
    """A representative multi-day week maps each ISODOW to its index."""
    assert StreakService._build_week_days([1, 3, 5]) == [
        True,
        False,
        True,
        False,
        True,
        False,
        False,
    ]


def test_full_week_is_all_true() -> None:
    assert StreakService._build_week_days([1, 2, 3, 4, 5, 6, 7]) == [True] * 7


def test_duplicates_and_unordered_input_are_idempotent() -> None:
    """The SQL is DISTINCT, but the builder tolerates repeats and any order."""
    assert StreakService._build_week_days([5, 1, 3, 1, 5]) == (
        StreakService._build_week_days([1, 3, 5])
    )


def test_result_is_always_length_seven() -> None:
    """The strip is always exactly 7 long, whatever the input."""
    for sample in ([], [4], [2, 6], [1, 2, 3, 4, 5, 6, 7]):
        assert len(StreakService._build_week_days(sample)) == 7
