"""Unit tests for ``ClassesExceptionsService`` — the range-cancel teardown.

``ClassesUndoService`` is mocked (the DB boundary the whole file targets); the
branching logic that decides whether a range-covered SLOT is torn down is
under test. Mirrors the mock style of ``test_classes_undo_service.py``.

Coverage:
* ``_write_range_and_teardown`` (the shared seam both ``create_range_exception``
  and ``update_range_exception`` route through) — a CANCEL range tears down
  after the write, an instructor-substitution range skips the teardown
  entirely — never both;
* ``update_range_exception`` — 404s when the exception doesn't belong to the
  class; otherwise re-runs the SAME teardown decision keyed off the
  EXISTING row's ``is_cancelled`` (not any field on the update request,
  which carries no such flag);
* ``delete_range_exception`` — 404s on a zero-row delete, else returns the
  deleted row;
* ``list_range_exceptions`` — reads the "all, newest-first" SQL (no window);
* ``_teardown_if_still_cancelled`` — the per-candidate-SLOT decision: an
  instance exception on the slot's date short-circuits (the range never
  applies to a date any instance exception governs — same-date override or
  moved elsewhere); an earlier-created covering range still rendering the
  slot's time short-circuits too; a slot that isn't a recurrence slot under
  the current versions is a no-op; a genuinely-cancelled slot tears down
  ONLY when its original slot instant is still at/after now (never
  day-based) — the founder-approved asymmetry keeps an already-run
  occurrence's attendance untouched;
* ``_teardown_covered_occurrences`` — a no-op when there are no candidate
  slots (skips loading versions), else iterates every candidate SLOT — and a
  2-SLOT day fully covered by the range decides EACH slot independently: the
  past-instant slot is kept, the future sibling slot on the SAME date is
  torn down;
* ``_range_cancel_candidates`` — the raw SQL read, sorted/deduped SLOTS
  (``(original_date, original_time)`` pairs).
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time
from unittest.mock import ANY, AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.classes.schema.classes_crud_schema import (
    ClassRangeExceptionCreateRequest,
    ClassRangeExceptionUpdateRequest,
)
from src.classes.service.classes_exceptions_service import (
    ClassesExceptionsService,
)

_NOW = datetime(2026, 7, 2, 12, 0, tzinfo=UTC)
_PAST_INSTANT = datetime(2026, 6, 1, 9, 0, tzinfo=UTC)
_FUTURE_INSTANT = datetime(2026, 8, 1, 9, 0, tzinfo=UTC)


def _bare_occurrence(
    occurred_at: datetime, original_time: time | None = None
) -> MagicMock:
    """A stand-in for the pure-ownership ``EffectiveOccurrence`` — only
    ``occurred_at`` (the past/future instant check) and ``original_time``
    (the earlier-covering-range render check) are read by the code under
    test."""
    occ = MagicMock()
    occ.occurred_at = occurred_at
    occ.original_time = original_time
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


# -- create_range_exception / update_range_exception routing ----------------


class TestCreateRangeExceptionRouting:
    async def test_substitution_range_never_tears_down(self) -> None:
        svc = _service(MagicMock())
        svc._write_range_and_teardown = AsyncMock(
            return_value=_range_row(is_cancelled=False)
        )
        request = _range_request(is_cancelled=False, new_instructor_id=uuid4())

        await svc.create_range_exception(uuid4(), uuid4(), request)

        svc._write_range_and_teardown.assert_awaited_once()
        assert svc._write_range_and_teardown.await_args.kwargs["is_cancelled"] is False

    async def test_cancel_range_routes_through_the_teardown_path(self) -> None:
        svc = _service(MagicMock())
        svc._write_range_and_teardown = AsyncMock(
            return_value=_range_row(is_cancelled=True)
        )
        request = _range_request(is_cancelled=True)

        await svc.create_range_exception(uuid4(), uuid4(), request)

        svc._write_range_and_teardown.assert_awaited_once()
        assert svc._write_range_and_teardown.await_args.kwargs["is_cancelled"] is True

    async def test_rejects_a_range_that_neither_cancels_nor_substitutes(
        self,
    ) -> None:
        svc = _service(MagicMock())
        request = _range_request(is_cancelled=False, new_instructor_id=None)

        with pytest.raises(ValueError, match="cancel the range"):
            await svc.create_range_exception(uuid4(), uuid4(), request)


class TestUpdateRangeExceptionRouting:
    async def test_not_found_raises_before_any_write(self) -> None:
        undo = MagicMock()
        svc = _service(undo)
        svc._load_range_exception = AsyncMock(
            side_effect=ValueError("Range exception not found")
        )
        svc._write_range_and_teardown = AsyncMock()

        with pytest.raises(ValueError, match="not found"):
            await svc.update_range_exception(
                uuid4(),
                uuid4(),
                uuid4(),
                ClassRangeExceptionUpdateRequest(
                    start_date=date(2026, 8, 1), end_date=date(2026, 8, 5)
                ),
            )
        svc._write_range_and_teardown.assert_not_awaited()

    async def test_teardown_decision_follows_the_existing_rows_is_cancelled(
        self,
    ) -> None:
        """The UPDATE request has no is_cancelled field at all — the
        teardown decision must come from the EXISTING row, not the request."""
        svc = _service(MagicMock())
        svc._load_range_exception = AsyncMock(
            return_value=_range_row(is_cancelled=True)
        )
        svc._write_range_and_teardown = AsyncMock(
            return_value=_range_row(is_cancelled=True)
        )
        new_start, new_end = date(2026, 8, 1), date(2026, 8, 10)

        await svc.update_range_exception(
            uuid4(),
            uuid4(),
            uuid4(),
            ClassRangeExceptionUpdateRequest(
                start_date=new_start, end_date=new_end
            ),
        )

        kwargs = svc._write_range_and_teardown.await_args.kwargs
        assert kwargs["is_cancelled"] is True
        assert kwargs["start_date"] == new_start
        assert kwargs["end_date"] == new_end

    async def test_substitution_range_update_never_tears_down(self) -> None:
        svc = _service(MagicMock())
        svc._load_range_exception = AsyncMock(
            return_value=_range_row(is_cancelled=False)
        )
        svc._write_range_and_teardown = AsyncMock(
            return_value=_range_row(is_cancelled=False)
        )

        await svc.update_range_exception(
            uuid4(),
            uuid4(),
            uuid4(),
            ClassRangeExceptionUpdateRequest(
                start_date=date(2026, 8, 1), end_date=date(2026, 8, 5)
            ),
        )

        assert svc._write_range_and_teardown.await_args.kwargs["is_cancelled"] is False


class TestDeleteRangeException:
    async def test_not_found_raises(self) -> None:
        svc = _service(MagicMock())
        svc._write_returning = AsyncMock(return_value=None)

        with pytest.raises(ValueError, match="not found"):
            await svc.delete_range_exception(uuid4(), uuid4())

    async def test_returns_the_deleted_row(self) -> None:
        svc = _service(MagicMock())
        row = _range_row(is_cancelled=True)
        svc._write_returning = AsyncMock(return_value=row)

        result = await svc.delete_range_exception(row["class_id"], row["exception_id"])

        assert result.exception_id == row["exception_id"]
        assert svc._write_returning.await_args.kwargs.get("allow_missing") is True


class TestListRangeExceptions:
    async def test_reads_all_with_no_window(self) -> None:
        svc = _service(MagicMock())
        rows = [_range_row(is_cancelled=True), _range_row(is_cancelled=False)]
        svc._read_all = AsyncMock(return_value=rows)

        result = await svc.list_range_exceptions(uuid4())

        assert len(result.items) == 2
        args, kwargs = svc._read_all.await_args
        # No start_date/end_date -- the "all ranges" read is unwindowed.
        assert "start_date" not in args[1]
        assert "end_date" not in args[1]


# -- _write_range_and_teardown ------------------------------------------------


class TestWriteRangeAndTeardown:
    async def test_writes_tears_down_then_commits_for_a_cancel(self) -> None:
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

        result_row = await svc._write_range_and_teardown(
            row["class_id"],
            row["gym_id"],
            "SQL",
            {"a": 1},
            is_cancelled=True,
            start_date=date(2026, 8, 1),
            end_date=date(2026, 8, 31),
        )

        assert result_row == row
        svc._teardown_covered_occurrences.assert_awaited_once_with(
            session,
            row["class_id"],
            row["gym_id"],
            date(2026, 8, 1),
            date(2026, 8, 31),
        )
        session.commit.assert_awaited_once()

    async def test_substitution_write_skips_teardown(self) -> None:
        row = _range_row(is_cancelled=False)
        session = _fake_session()
        result = MagicMock()
        result.mappings.return_value.fetchone.return_value = row
        session.execute = AsyncMock(return_value=result)
        db_pool = MagicMock()
        db_pool.session.return_value = session

        svc = _service(MagicMock())
        svc._db_pool = db_pool
        svc._teardown_covered_occurrences = AsyncMock()

        await svc._write_range_and_teardown(
            row["class_id"],
            row["gym_id"],
            "SQL",
            {"a": 1},
            is_cancelled=False,
            start_date=date(2026, 8, 1),
            end_date=date(2026, 8, 31),
        )

        svc._teardown_covered_occurrences.assert_not_awaited()
        session.commit.assert_awaited_once()


# -- _teardown_if_still_cancelled --------------------------------------------


class TestTeardownIfStillCancelled:
    async def test_skips_when_an_instance_exception_governs_the_slot(
        self,
    ) -> None:
        """A same-slot override OR a move elsewhere — either way the range
        never applies to a slot with ANY instance exception on it."""
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value={"is_cancelled": False})
        undo.expand_day = AsyncMock()
        undo.owning_slot = MagicMock()
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 7, 10), time(6, 0), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()
        undo.expand_day.assert_not_awaited()  # short-circuits before the range check

    async def test_skips_when_an_earlier_range_still_renders_the_slot(
        self,
    ) -> None:
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        slot_time = time(6, 0)
        undo.expand_day = AsyncMock(
            return_value=[_bare_occurrence(_FUTURE_INSTANT, slot_time)]
        )
        undo.owning_slot = MagicMock()
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 7, 10), slot_time, _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()
        undo.owning_slot.assert_not_called()

    async def test_skips_when_not_a_recurrence_slot(self) -> None:
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(return_value=[])
        undo.owning_slot = MagicMock(return_value=None)
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)

        await svc._teardown_if_still_cancelled(
            object(), uuid4(), uuid4(), [], date(2026, 7, 10), time(6, 0), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()

    async def test_tears_down_a_future_instant_cancelled_slot(self) -> None:
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(return_value=[])
        undo.owning_slot = MagicMock(
            return_value=(MagicMock(), _bare_occurrence(_FUTURE_INSTANT))
        )
        undo.teardown_occurrence = AsyncMock()
        svc = _service(undo)
        class_id, gym_id, day, slot_time = (
            uuid4(),
            uuid4(),
            date(2026, 7, 10),
            time(6, 0),
        )
        session = object()

        await svc._teardown_if_still_cancelled(
            session, class_id, gym_id, [], day, slot_time, _NOW
        )

        undo.teardown_occurrence.assert_awaited_once_with(
            session, class_id, gym_id, day, slot_time
        )

    async def test_keeps_an_already_run_cancelled_slot(self) -> None:
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
            object(), uuid4(), uuid4(), [], date(2026, 6, 5), time(18, 0), _NOW
        )

        undo.teardown_occurrence.assert_not_awaited()


# -- _teardown_covered_occurrences --------------------------------------------


class TestTeardownCoveredOccurrences:
    async def test_noop_when_no_candidate_slots(self) -> None:
        undo = MagicMock()
        undo.load_versions = AsyncMock()
        svc = _service(undo)
        svc._range_cancel_candidates = AsyncMock(return_value=[])

        await svc._teardown_covered_occurrences(
            object(), uuid4(), uuid4(), date(2026, 7, 1), date(2026, 7, 31)
        )

        undo.load_versions.assert_not_awaited()

    async def test_iterates_every_candidate_slot(self) -> None:
        undo = MagicMock()
        undo.load_versions = AsyncMock(return_value=["v1"])
        svc = _service(undo)
        slots = [
            (date(2026, 7, 3), time(6, 0)),
            (date(2026, 7, 5), time(18, 0)),
        ]
        svc._range_cancel_candidates = AsyncMock(return_value=slots)
        svc._teardown_if_still_cancelled = AsyncMock()

        await svc._teardown_covered_occurrences(
            object(), uuid4(), uuid4(), date(2026, 7, 1), date(2026, 7, 31)
        )

        assert svc._teardown_if_still_cancelled.await_count == 2
        called_slots = {
            (call.args[4], call.args[5])
            for call in svc._teardown_if_still_cancelled.await_args_list
        }
        assert called_slots == set(slots)

    async def test_two_slot_day_past_instant_kept_future_sibling_torn_down(
        self,
    ) -> None:
        """A range covers a day with TWO slots: the slot whose original
        instant already ran keeps its attendance; the future sibling slot on
        the SAME date is torn down — decided per-slot, not per-day."""
        undo = MagicMock()
        undo.exception_on = AsyncMock(return_value=None)
        undo.expand_day = AsyncMock(return_value=[])
        day = date(2026, 7, 10)
        past_time, future_time = time(6, 0), time(18, 0)

        def _owning_slot(versions, when, slot_time):
            occurred_at = (
                _PAST_INSTANT if slot_time == past_time else _FUTURE_INSTANT
            )
            return (MagicMock(), _bare_occurrence(occurred_at))

        undo.owning_slot = MagicMock(side_effect=_owning_slot)
        undo.teardown_occurrence = AsyncMock()
        undo.load_versions = AsyncMock(return_value=["v1"])
        svc = _service(undo)
        svc._range_cancel_candidates = AsyncMock(
            return_value=[(day, past_time), (day, future_time)]
        )
        class_id, gym_id = uuid4(), uuid4()

        await svc._teardown_covered_occurrences(
            object(), class_id, gym_id, day, day
        )

        undo.teardown_occurrence.assert_awaited_once_with(
            ANY, class_id, gym_id, day, future_time
        )


# -- _range_cancel_candidates --------------------------------------------------


class TestRangeCancelCandidates:
    async def test_returns_sorted_distinct_slots(self) -> None:
        session = AsyncMock()
        result = MagicMock()
        result.mappings.return_value.all.return_value = [
            {"original_date": date(2026, 7, 5), "original_time": time(18, 0)},
            {"original_date": date(2026, 7, 1), "original_time": time(6, 0)},
            {"original_date": date(2026, 7, 1), "original_time": time(18, 0)},
        ]
        session.execute = AsyncMock(return_value=result)
        svc = _service(MagicMock())

        slots = await svc._range_cancel_candidates(
            session, uuid4(), date(2026, 7, 1), date(2026, 7, 31)
        )

        assert slots == [
            (date(2026, 7, 1), time(6, 0)),
            (date(2026, 7, 1), time(18, 0)),
            (date(2026, 7, 5), time(18, 0)),
        ]
