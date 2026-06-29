"""Pure-unit coverage for ClassesUndoService that needs no DB.

The reschedule date-order validation is the first line of
``reschedule_occurrence`` and runs before any db_pool / expander access, so it
is testable with stub dependencies and asserts the 400 path (``new_date`` must
be strictly after the occurrence date).
"""

from __future__ import annotations

from datetime import date

import pytest

from src.classes.service.classes_undo_service import ClassesUndoService


@pytest.fixture
def service() -> ClassesUndoService:
    # db_pool / expander are never reached for the date-order rejection, so
    # passing None proves the check happens before any I/O.
    return ClassesUndoService(db_pool=None, expander=None)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_reschedule_rejects_earlier_new_date(
    service: ClassesUndoService,
) -> None:
    from uuid import uuid4

    with pytest.raises(ValueError, match="after the occurrence date"):
        await service.reschedule_occurrence(
            class_id=uuid4(),
            gym_id=uuid4(),
            occurrence_date=date(2025, 1, 10),
            new_date=date(2025, 1, 5),
        )


@pytest.mark.asyncio
async def test_reschedule_rejects_same_new_date(
    service: ClassesUndoService,
) -> None:
    from uuid import uuid4

    with pytest.raises(ValueError, match="after the occurrence date"):
        await service.reschedule_occurrence(
            class_id=uuid4(),
            gym_id=uuid4(),
            occurrence_date=date(2025, 1, 10),
            new_date=date(2025, 1, 10),
        )
