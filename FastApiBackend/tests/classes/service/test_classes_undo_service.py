"""Pure-unit coverage for ClassesUndoService's time-aware reschedule conflict.

``assert_no_reschedule_conflict`` keys the rejection on the exact target instant
(new_date AND the effective start time), so a move onto a busy day at a DIFFERENT
time is allowed while a move onto the exact same instant is a conflict. The DB
reads (the direct-collision query + the per-day exception lists) are stubbed to
empty, leaving the pure recurrence expander to decide — no DB needed.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest

from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_undo_service import (
    ClassesUndoService,
    RescheduleConflictError,
)

_GYM_TZ = "America/Chicago"
_CLASS_TIME = time(9, 0)


def _class_row(class_id: UUID, gym_id: UUID) -> dict:
    """A daily-recurring class at 09:00, open-ended from 2025-01-01."""
    row: dict = {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_time": _CLASS_TIME,
        "duration_minutes": 60,
        "recurring_unit": "daily",
        "recurring_interval": 1,
        "start_date": date(2025, 1, 1),
        "end_date": None,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        row[day] = True
        row[f"{day}_instructor_id"] = None
    return row


@pytest.fixture
def service() -> ClassesUndoService:
    # db_pool + reverser are never touched: every DB read is stubbed to empty and
    # the conflict check does no wiping, so only the pure expander (real) decides.
    svc = ClassesUndoService(
        db_pool=None,  # type: ignore[arg-type]
        expander=ClassesExpander(),
        reverser=None,  # type: ignore[arg-type]
    )

    async def _no_db_reads(sql: str, params: dict) -> list:
        return []

    svc._read_all = _no_db_reads  # type: ignore[method-assign]
    return svc


def _occurred_at(when: date, at: time) -> datetime:
    return datetime.combine(when, at, tzinfo=ZoneInfo(_GYM_TZ)).astimezone(UTC)


@pytest.mark.asyncio
async def test_conflict_when_same_date_same_time(
    service: ClassesUndoService,
) -> None:
    """A move onto a day that already has an occurrence at the SAME time is a
    conflict (the exact target instant is taken)."""
    class_id, gym_id = uuid4(), uuid4()
    row = _class_row(class_id, gym_id)
    target = date(2025, 6, 2)  # the daily class occurs here at 09:00

    with pytest.raises(RescheduleConflictError):
        await service.assert_no_reschedule_conflict(
            row,
            class_id,
            original_date=date(2025, 6, 1),
            new_date=target,
            effective_time=_CLASS_TIME,
            new_occurred_at=_occurred_at(target, _CLASS_TIME),
            gym_tz=_GYM_TZ,
        )


@pytest.mark.asyncio
async def test_allowed_when_same_date_different_time(
    service: ClassesUndoService,
) -> None:
    """A move onto a busy day at a DIFFERENT time is allowed — it returns without
    raising (the 09:00 occurrence and a 10:00 move are different instants)."""
    class_id, gym_id = uuid4(), uuid4()
    row = _class_row(class_id, gym_id)
    target = date(2025, 6, 2)  # occurs at 09:00; 10:00 is a free slot that day

    await service.assert_no_reschedule_conflict(
        row,
        class_id,
        original_date=date(2025, 6, 1),
        new_date=target,
        effective_time=time(10, 0),
        new_occurred_at=_occurred_at(target, time(10, 0)),
        gym_tz=_GYM_TZ,
    )
