"""Pure-logic unit tests for the presets domain (no DB / no Stripe).

The instructor name-split is the one transform with edge cases worth pinning:
the import must always produce a non-empty first AND last name so the
``gym_employees`` NOT NULL / non-empty CHECK constraints are satisfied.
"""

from src.presets.service.presets_service import PresetsService


def test_split_name_two_parts():
    assert PresetsService._split_name("James Carter") == ("James", "Carter")


def test_split_name_splits_on_last_space():
    assert PresetsService._split_name("Mary Jo Smith") == ("Mary Jo", "Smith")


def test_split_name_single_word_uses_nonempty_fallback():
    first, last = PresetsService._split_name("Madonna")
    assert first == "Madonna"
    assert last  # non-empty fallback so the DB last_name CHECK passes


def test_split_name_blank_uses_nonempty_fallback():
    first, last = PresetsService._split_name("")
    assert first and last  # both non-empty


def test_split_name_none_uses_nonempty_fallback():
    first, last = PresetsService._split_name(None)
    assert first and last
