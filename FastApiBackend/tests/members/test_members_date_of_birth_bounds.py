"""``members.date_of_birth`` is bounded at BOTH layers, on purpose.

* **The API layer** — a ``field_validator`` on every schema accepting a DOB, so
  a bad value is a 422 before it reaches the database. Covered on the CREATE
  *and* the UPDATE model: staff correcting a DOB post to the update model, the
  other way a value reaches the column.
* **The DB layer** — the ``date_of_birth_plausible`` CHECK, the backstop for
  every writer that does NOT pass through those models (the seed, an importer,
  a hand-run UPDATE). A validator-only bound looks correct in every API test
  while leaving the column open to all of them, so a hermetic drift guard reads
  the schema file and the migration off disk and fails if either loses the
  constraint or disagrees with the model about the floor.
"""

from __future__ import annotations

import re
from datetime import date, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.members.schema.members_schema import (
    EARLIEST_DATE_OF_BIRTH,
    MemberCreateRequest,
    MemberUpdateData,
)

_DB_DIR = Path(__file__).resolve().parents[3] / "Database" / "supabase"
_SCHEMA_FILE = _DB_DIR / "schemas" / "members.sql"
_MIGRATIONS_DIR = _DB_DIR / "migrations"

_CONSTRAINT_NAME = "date_of_birth_plausible"


def _create(**overrides) -> MemberCreateRequest:
    """A minimal valid create request, with overrides applied."""
    return MemberCreateRequest(
        gym_id=uuid4(),
        first_name="Ada",
        last_name="Lovelace",
        **overrides,
        send_invite=False,
    )


# ── the API layer: a bad DOB is a 422, on both models ───────────────────


@pytest.mark.parametrize(
    ("label", "bad_dob"),
    [
        ("tomorrow", date.today() + timedelta(days=1)),
        ("a slipped year", date(2035, 6, 1)),
        ("a truncated year", date(202, 6, 1)),
        ("the year zero-ish", date(1, 1, 1)),
        ("one day before the floor", EARLIEST_DATE_OF_BIRTH - timedelta(days=1)),
    ],
)
def test_create_rejects_an_implausible_date_of_birth(label, bad_dob) -> None:
    """Every implausible DOB is refused at deserialization (-> 422).

    ``date(202, 6, 1)`` — a year typed with a digit missing — is the real kiosk
    typo, and a perfectly valid ``date`` object, which is why only a validator
    can reject it.
    """
    with pytest.raises(ValidationError) as excinfo:
        _create(date_of_birth=bad_dob)
    assert "date_of_birth" in str(excinfo.value), label


@pytest.mark.parametrize(
    ("label", "bad_dob"),
    [
        ("tomorrow", date.today() + timedelta(days=1)),
        ("a slipped year", date(2035, 6, 1)),
        ("a truncated year", date(202, 6, 1)),
    ],
)
def test_update_rejects_an_implausible_date_of_birth(label, bad_dob) -> None:
    """The UPDATE model carries the same guard: without it the bound is
    trivially bypassable — create with no DOB, then PUT the bad one."""
    with pytest.raises(ValidationError) as excinfo:
        MemberUpdateData(date_of_birth=bad_dob)
    assert "date_of_birth" in str(excinfo.value), label


@pytest.mark.parametrize(
    ("label", "good_dob"),
    [
        ("None — the column is optional", None),
        ("today, the upper boundary", date.today()),
        ("the floor itself", EARLIEST_DATE_OF_BIRTH),
        ("an ordinary adult", date(1990, 4, 17)),
        ("a plausible senior", date(1928, 11, 3)),
    ],
)
def test_a_plausible_date_of_birth_is_accepted(label, good_dob) -> None:
    """Both bounds are INCLUSIVE, and NULL stays legal.

    An off-by-one here silently rejects real members, so the boundaries are
    named: a newborn registered today and the oldest plausible member both pass.
    """
    assert _create(date_of_birth=good_dob).date_of_birth == good_dob
    assert MemberUpdateData(date_of_birth=good_dob).date_of_birth == good_dob


# The oldest verified human lifespan (Jeanne Calment, 122y164d). A floor
# further back than this cannot reject a living person.
_MAX_VERIFIED_HUMAN_AGE_YEARS = 122


def test_the_floor_is_defensible() -> None:
    """The floor can never reject a living person.

    Asserted rather than commented so that raising the floor toward the present
    — the change that WOULD start rejecting real members — fails here.
    """
    assert date(1900, 1, 1) == EARLIEST_DATE_OF_BIRTH
    years_of_headroom = (date.today() - EARLIEST_DATE_OF_BIRTH).days / 365.25
    assert years_of_headroom > _MAX_VERIFIED_HUMAN_AGE_YEARS


# ── the DB layer: the CHECK exists and agrees with the model ────────────


def _constraint_text(sql: str) -> str | None:
    """The ``date_of_birth_plausible`` CHECK body, whitespace-collapsed.

    Parens are BALANCED rather than regex-matched: the predicate nests them, so
    a lazy ``(.*?)`` stops at the inner close and a greedy one swallows the file
    — either way the assertions below would pass on text that is not the
    constraint at all, and a guard that cannot fail is worse than no guard.
    """
    match = re.search(rf"{_CONSTRAINT_NAME}\s+CHECK\s*\(", sql)
    if match is None:
        return None
    depth = 0
    start = match.end() - 1
    for index in range(start, len(sql)):
        if sql[index] == "(":
            depth += 1
        elif sql[index] == ")":
            depth -= 1
            if depth == 0:
                return re.sub(r"\s+", " ", sql[start + 1 : index]).strip()
    return None


def test_the_schema_file_declares_the_check() -> None:
    """``schemas/members.sql`` is the source of truth for the end state, so
    losing the constraint has to fail somewhere — this is where."""
    sql = _SCHEMA_FILE.read_text(encoding="utf-8")
    body = _constraint_text(sql)
    assert body is not None, f"{_CONSTRAINT_NAME} missing from schemas/members.sql"
    assert "date_of_birth IS NULL" in body, "NULL must stay legal"
    assert "CURRENT_DATE" in body, "the no-future-date bound is missing"
    assert (
        f"DATE '{EARLIEST_DATE_OF_BIRTH.isoformat()}'" in body
    ), "the DB floor disagrees with EARLIEST_DATE_OF_BIRTH"


def test_a_migration_applies_the_check() -> None:
    """Some migration adds it, so an already-migrated database gets it too.

    Schema files are only replayed by a full ``supabase db reset``; if only they
    carried the constraint, a reset-from-scratch database and a migrated one
    would disagree.
    """
    adders = [
        path
        for path in sorted(_MIGRATIONS_DIR.glob("*.sql"))
        if _CONSTRAINT_NAME in path.read_text(encoding="utf-8")
    ]
    assert adders, f"no migration adds {_CONSTRAINT_NAME}"
    body = _constraint_text(adders[-1].read_text(encoding="utf-8"))
    assert body is not None, f"{adders[-1].name} names it but declares no CHECK"
    assert "date_of_birth IS NULL" in body
    assert "CURRENT_DATE" in body
    assert f"DATE '{EARLIEST_DATE_OF_BIRTH.isoformat()}'" in body, (
        "the migration's floor disagrees with EARLIEST_DATE_OF_BIRTH"
    )
