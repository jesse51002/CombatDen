"""Unit tests for ``ClassesExceptionsService`` — the range-cancel teardown.

``ClassesUndoService`` is mocked (the DB boundary the whole file targets); the
branching logic that decides whether a range-covered date is torn down is
under test. Mirrors the mock style of ``test_classes_undo_service.py``.

Coverage:
* ``create_range_exception`` routes a CANCEL range through the teardown path
  and an instructor-substitution range through the plain write only — never
  both;
* ``_teardown_if_still_cancelled`` — the per-candidate-date decision: an
  instance exception on the date short-circuits (the range never applies to
  a date any instance exception governs — same-date override or moved
  elsewhere); an earlier-created covering range still rendering the date
  short-circuits too; a date that isn't a recurrence date under the current
  versions is a no-op; a genuinely-cancelled date tears down ONLY when its
  original slot instant is still at/after now (never day-based) — the
  founder-approved asymmetry keeps an already-run occurrence's attendance
  untouched;
* ``_teardown_covered_occurrences`` — a no-op when there are no candidate
  dates (skips loading versions), else iterates every candidate;
* ``_range_cancel_candidates`` — the raw SQL read, sorted/deduped;
* ``_create_cancelled_range_with_teardown`` — insert + teardown + commit in
  ONE session.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.classes.schema.classes_crud_schema import (
    ClassRangeExceptionCreateRequest,
)
from src.classes.service.classes_exceptions_service import (
    ClassesExceptionsService,
)

_NOW = datetime(2026, 7, 2, 12, 0, tzinfo=UTC)
_PAST_INSTANT = datetime(2026, 6, 1, 9, 0, tzinfo=UTC)
_FUTURE_INSTANT = datetime(2026, 8, 1, 9, 0, tzinfo=UTC)


def _bare_occurrence(occurred_at: datetime) -> MagicMock:
    """A stand-in for the pure-ownership ``EffectiveOccurrence`` — only
    ``occurred_at`` is read by the code under test."""
    occ = MagicMock()
    occ.occurred_at = occurred_at
    return occ


def _service(undo_service: MagicMock) -> ClassesExceptionsService:
    return ClassesExceptionsService(
        db_pool=MagicMock(), undo_service=undo_service
    )


def _range_request(
    *, is_cancelled: bool, new_instructor_id=None
) -> ClassRangeExceptionCreateRequest:
    return ClassRangeExceptionCreateRequest(
        start_date=date(2026, 7, 1),
        end_date=date(2026, 7, 31),
        is_cancelled=is_cancelled,
        new_instructor_id=new_instructor_id,
    )


def _range_row(*, is_cancelled: bool) -> dict:
    return {
        "exception_id": uuid4(),
        "class_id": uuid4(),
        "gym_id": uuid4(),
        "start_date": date(2026, 7, 1),
        "end_date": date(2026, 7, 31),
        "is_cancelled": is_cancelled,
        "new_instructor_id": None,
        "created_at": datetime.now(UTC),
    }


def _fake_session() -> AsyncMock:
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.commit = AsyncMock()
    return session


# -- create_range_exception routing ------------------------------------------


class TestCreateRangeExceptionRouting:
    async def test_substitution_range_never_tears_down(self) -> None:
        svc = _service(MagicMock())
        svc._write_returning = AsyncMock(
            return_value=_range_row(is_cancelled=False)
        )
        svc._create_cancelled_range_with_teardown = AsyncMock()
        request = _range_request(is_cancelled=False, new_instructor_id=uuid4())

        await svc.create_range_exception(uuid4(), uuid4(), request)

        svc._write_returning.assert_awaited_once()
        svc._create_cancelled_range_with_teardown.assert_not_awaited()

    async def test_cancel_range_routes_through_the_teardown_path(self) -> None:
        svc = _service(MagicMock())
        svc._write_returning = AsyncMock()
        svc._create_cancelled_range_with_teardown = AsyncMock(
            return_value=_range_row(is_cancelled=True)
        )
        request = _range_request(is_cancelled=True)

        await svc.create_range_exception(uuid4(), uuid4(), request)

        svc._create_cancelled_range_with_teardown.assert_awaited_once()
        svc._write_returning.assert_not_awaited()


# -- _teardown_if_still_cancelled --------------------------------------------


class TestTeardownIfStillCancelled:
    async def test_skips_when_an_instance_exception_governs_the_date(
        self,
    ) -> None:
        """A same-date override OR a move elsewhere — either way the range
        never applies to a date with ANY instance exception on it."""
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value={"is_cancelled": False})
        undo.expand_day = AsyncMock()
        undo.owning_slot = MagicMock()
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 7, 10), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()
        undo.expand_day.assert_not_awaited()  # short-circuits before the range check

    async def test_skips_when_an_earlier_range_still_renders_it(self) -> None:
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(
            return_value=[_bare_occurrence(_FUTURE_INSTANT)]
        )
        undo.owning_slot = MagicMock()
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 7, 10), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()
        undo.owning_slot.assert_not_called()

    async def test_skips_when_not_a_recurrence_date(self) -> None:
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(return_value=[])
        undo.owning_slot = MagicMock(return_value=None)
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 7, 10), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()

    async def test_tears_down_a_future_instant_cancelled_date(self) -> None:
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(return_value=[])
        undo.owning_slot = MagicMock(
            return_value=(MagicMock(), _bare_occurrence(_FUTURE_INSTANT))
        )
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)
        class_id, gym_id, day = uuid4(), uuid4(), date(2026, 7, 10)
        session = object()

        await svc._teardown_if_still_cancelled(
            session, class_id, gym_id, [], day, _NOW
        )

        undo.teardown_occurrence.assert_awaited_once_with(
            session, class_id, gym_id, day
        )

    async def test_keeps_an_already_run_cancelled_date(self) -> None:
        """The founder-approved asymmetry: a past-instant occurrence covered
        by a retroactive range cancel keeps its attendance — never torn
        down. A gym wanting that cancels the single occurrence instead."""
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(return_value=[])
        undo.owning_slot = MagicMock(
            return_value=(MagicMock(), _bare_occurrence(_PAST_INSTANT))
        )
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 6, 5), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()


# -- _teardown_covered_occurrences --------------------------------------------


class TestTeardownCoveredOccurrences:
    async def test_noop_when_no_candidate_dates(self) -> None:
        undo = MagicMock()
        undo.load_versions = AsyncMock()
        svc = _service(undo)
        svc._range_cancel_candidates = AsyncMock(return_value=[])

        await svc._teardown_covered_occurrences(
            object(), uuid4(), uuid4(), date(2026, 7, 1), date(2026, 7, 31)
        )

        undo.load_versions.assert_not_awaited()

    async def test_iterates_every_candidate_date(self) -> None:
        undo = MagicMock()
        undo.load_versions = AsyncMock(return_value=["v1"])
        svc = _service(undo)
        days = [date(2026, 7, 3), date(2026, 7, 5)]
        svc._range_cancel_candidates = AsyncMock(return_value=days)
        svc._teardown_if_still_cancelled = AsyncMock()

        await svc._teardown_covered_occurrences(
            object(), uuid4(), uuid4(), date(2026, 7, 1), date(2026, 7, 31)
        )

        assert svc._teardown_if_still_cancelled.await_count == 2
        called_days = {
            call.args[4]
            for call in svc._teardown_if_still_cancelled.await_args_list
        }
        assert called_days == set(days)


# -- _range_cancel_candidates --------------------------------------------------


class TestRangeCancelCandidates:
    async def test_returns_sorted_distinct_dates(self) -> None:
        session = AsyncMock()
        result = MagicMock()
        result.mappings.return_value.all.return_value = [
            {"original_date": date(2026, 7, 5)},
            {"original_date": date(2026, 7, 1)},
        ]
        session.execute = AsyncMock(return_value=result)
        svc = _service(MagicMock())

        dates = await svc._range_cancel_candidates(
            session, uuid4(), date(2026, 7, 1), date(2026, 7, 31)
        )

        assert dates == [date(2026, 7, 1), date(2026, 7, 5)]


# -- _create_cancelled_range_with_teardown ------------------------------------


class TestCreateCancelledRangeWithTeardown:
    async def test_inserts_then_tears_down_then_commits(self) -> None:
        row = _range_row(is_cancelled=True)
        session = _fake_session()
        result = MagicMock()
        result.mappings.return_value.fetchone.return_value = row
        session.execute = AsyncMock(return_value=result)
        db_pool = MagicMock()
        db_pool.session.return_value = session

        svc = _service(MagicMock())
        svc._db_pool = db_pool
        svc._teardown_covered_occurrences = AsyncMock()

        request = _range_request(is_cancelled=True)
        result_row = await svc._create_cancelled_range_with_teardown(
            row["class_id"], row["gym_id"], request, "SQL", {"a": 1}
        )

        assert result_row == row
        svc._teardown_covered_occurrences.assert_awaited_once_with(
            session,
            row["class_id"],
            row["gym_id"],
            request.start_date,
            request.end_date,
        )
        session.commit.assert_awaited_once()
