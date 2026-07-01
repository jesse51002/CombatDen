"""Unit tests for SignupService (no DB).

Driven against a mocked db_pool session (mirrors test_checkin_points.py's
``_writer_with_results`` pattern) for the effective-capacity read + the
insert/delete writes, and a mocked ``CheckinQueries`` for the shared
signed-up-or-attended union (the same collaborator ``test_checkin_member_gate``
mocks for the check-in capacity gate). This is the capacity-decision coverage
that doesn't need the live ``class_signups`` table — see
``test_signup_integration.py`` for the live-DB behavior (which needs the
migration to be applied first).
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.checkin.service.signup_service import SignupService

_OCCURRENCE_DATE = date(2026, 6, 1)


def _result(row: dict | None) -> MagicMock:
    """A SQLAlchemy-result double whose ``.mappings().fetchone()`` is ``row``."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    return result


def _service_with_results(
    results: list[MagicMock],
) -> tuple[SignupService, AsyncMock]:
    """A service whose session.execute yields ``results`` in order.

    ``_queries`` is replaced with a bare MagicMock so
    ``get_signup_or_attended_members`` can be stubbed per test without a real
    DB round-trip.
    """
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=results)
    session.commit = AsyncMock()

    pool = MagicMock()
    pool.session.return_value = session

    service = SignupService(pool)
    service._queries = MagicMock()
    return service, session


# ── capacity ──────────────────────────────────────────────────────────


async def test_unlimited_capacity_always_inserts() -> None:
    """NULL max_capacity (and no instance-exception override) -> unlimited;
    the signed-up-or-attended union is never queried, straight to insert."""
    service, session = _service_with_results(
        [
            _result({"max_capacity": None, "exception_max_capacity": None}),
            _result({"signup_id": uuid4()}),
        ]
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False
    service._queries.get_signup_or_attended_members.assert_not_awaited()


async def test_room_creates_when_under_capacity() -> None:
    """Effective capacity 5, union already has 2 (member not among them) ->
    room, inserts."""
    service, session = _service_with_results(
        [
            _result({"max_capacity": 5, "exception_max_capacity": None}),
            _result({"signup_id": uuid4()}),
        ]
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4(), uuid4()}
    )

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False


async def test_full_room_rejects_a_new_member() -> None:
    """Effective capacity 2, union already has 2 OTHER members -> 'Class is
    full', and the insert is never attempted."""
    service, session = _service_with_results(
        [_result({"max_capacity": 2, "exception_max_capacity": None})]
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4(), uuid4()}
    )

    with pytest.raises(ValueError, match="Class is full"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert session.execute.call_count == 1  # only the capacity read


async def test_already_counted_member_bypasses_full_room() -> None:
    """A member already in the union (a prior sign-up, or already attended)
    is admitted even when the room is nominally full -- adding them doesn't
    grow the count."""
    member_id = uuid4()
    service, session = _service_with_results(
        [
            _result({"max_capacity": 2, "exception_max_capacity": None}),
            _result({"signup_id": uuid4()}),
        ]
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={member_id, uuid4()}
    )

    resp = await service.create(member_id, uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False


async def test_exception_max_capacity_overrides_class_default() -> None:
    """A per-occurrence exception_max_capacity wins over the class default."""
    service, session = _service_with_results(
        [_result({"max_capacity": 100, "exception_max_capacity": 1})]
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4()}  # already 1/1 under the override
    )

    with pytest.raises(ValueError, match="Class is full"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)


async def test_unknown_class_raises_not_found() -> None:
    service, session = _service_with_results([_result(None)])
    service._queries.get_signup_or_attended_members = AsyncMock()

    with pytest.raises(ValueError, match="Class not found"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)


# ── idempotent create ─────────────────────────────────────────────────


async def test_idempotent_repeat_returns_existing_signup_id() -> None:
    """ON CONFLICT DO NOTHING (no row) falls back to the existing-row lookup,
    reporting already_signed_up=True with the pre-existing id."""
    existing_id = uuid4()
    service, session = _service_with_results(
        [
            _result({"max_capacity": None, "exception_max_capacity": None}),
            _result(None),  # insert conflict
            _result({"signup_id": existing_id}),  # existing lookup
        ]
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.signup_id == existing_id
    assert resp.already_signed_up is True


# ── remove ────────────────────────────────────────────────────────────


async def test_remove_returns_removed_true_when_row_deleted() -> None:
    service, session = _service_with_results([_result({"signup_id": uuid4()})])

    resp = await service.remove(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.removed is True


async def test_remove_returns_removed_false_when_no_row() -> None:
    service, session = _service_with_results([_result(None)])

    resp = await service.remove(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.removed is False
