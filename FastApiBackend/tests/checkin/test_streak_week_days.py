"""Unit tests for the current-week per-day strip building.

``StreakService._build_week_days`` turns the set of Postgres ISO weekday
numbers (1 = Monday .. 7 = Sunday) a member attended on this week into the
length-7, Monday-first ``list[bool]`` the kiosk glance draws its S/M/T/W/T/F/S
strip from (index 0 = Monday .. 6 = Sunday). It is a pure static method, so
these tests exercise it directly -- no DB, no session.
"""

from src.checkin.service.streak_service import StreakService


def test_no_attendance_is_all_false() -> None:
    """An empty week -> seven Falses."""
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
    """Every weekday attended -> seven Trues."""
    assert StreakService._build_week_days([1, 2, 3, 4, 5, 6, 7]) == [True] * 7


def test_duplicates_and_unordered_input_are_idempotent() -> None:
    """Order and repeats don't matter (the SQL is DISTINCT, but the builder
    tolerates duplicates and any order regardless)."""
    assert StreakService._build_week_days([5, 1, 3, 1, 5]) == (
        StreakService._build_week_days([1, 3, 5])
    )


def test_result_is_always_length_seven() -> None:
    """The strip is always exactly 7 long, whatever the input."""
    for sample in ([], [4], [2, 6], [1, 2, 3, 4, 5, 6, 7]):
        assert len(StreakService._build_week_days(sample)) == 7
