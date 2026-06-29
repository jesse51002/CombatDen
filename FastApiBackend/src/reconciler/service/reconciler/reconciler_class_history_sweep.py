"""ClassHistorySweep — materialize past class occurrences (NON-billing).

An INDEPENDENT, non-billing reconciler step. It touches no Stripe, no membership,
and no payment state: it only INSERTs ``class_history`` rows for PAST,
non-cancelled class occurrences (even zero-attendee ones) via the existing
idempotent ``ClassesMaterializer``. This keeps recorded class history complete
even for occurrences no member ever checked into (the check-in path only
materializes the occurrences someone actually attends).

It reuses the canonical ``ClassesExpander`` (recurrence + exceptions, cancelled
occurrences dropped by default) so runtime materialization and the seeded history
can never disagree. The window is ``[today - settings.class_history_lookback_days,
today]`` (UTC dates); only occurrences whose UTC instant is already in the past
(``occurred_at < now``) are materialized — today's not-yet-started class is left
for a later sweep. The materializer's ``uq_class_history_occurrence`` ON CONFLICT
makes every insert idempotent, so re-running the sweep — or overlapping a live
check-in materialize — is a no-op for an already-recorded occurrence.

Per-item isolation: one bad class (unknown timezone, mapping error) or one failed
occurrence insert increments ``errors`` and never aborts the sweep.
"""

import logging
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.classes.service.classes_materializer import ClassesMaterializer
from src.core.config import settings
from src.reconciler import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.sweep_result import SweepResult

logger = logging.getLogger(__name__)

SWEEP_NAME = "class_history_materialize"


class ClassHistorySweep:
    """Backfill ``class_history`` for past, non-cancelled class occurrences.

    Args:
        db_pool: Injected database connection pool.
        expander: The canonical recurrence + exception expander (pure).
        materializer: Lazy idempotent find-or-create of a class_history row.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
        materializer: ClassesMaterializer,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander
        self._materializer = materializer

    async def run(self) -> SweepResult:
        """Materialize every past, non-cancelled occurrence in the window."""
        result = SweepResult(name=SWEEP_NAME)
        lookback = settings.class_history_lookback_days
        if lookback <= 0:
            logger.warning(
                "class_history_lookback_days=%d (<= 0); "
                "skipping class-history sweep",
                lookback,
            )
            return result

        now = datetime.now(UTC)
        window_end = now.date()
        window_start = window_end - timedelta(days=lookback)

        classes = await self._load_classes()
        instances_by_class = self._group_by_class(
            await self._load_instance_exceptions(window_start, window_end)
        )
        ranges_by_class = self._group_by_class(
            await self._load_range_exceptions(window_start, window_end)
        )

        for class_row in classes:
            await self._process_class(
                class_row,
                instances_by_class.get(class_row["class_id"], []),
                ranges_by_class.get(class_row["class_id"], []),
                window_start,
                window_end,
                now,
                result,
            )

        logger.info(
            "Class history materialize: classes=%d processed=%d created=%d "
            "existing=%d errors=%d",
            len(classes),
            result.processed,
            result.changed,
            result.skipped,
            result.errors,
        )
        return result

    # -- per-class expansion + materialize -------------------------------

    async def _process_class(
        self,
        class_row: dict,
        instance_rows: list[dict],
        range_rows: list[dict],
        window_start: date,
        window_end: date,
        now: datetime,
        result: SweepResult,
    ) -> None:
        """Expand one class and materialize each of its PAST occurrences.

        The whole expansion is isolated: a bad class row (e.g. an unknown
        timezone) counts ONE error and never aborts the sweep. Each occurrence's
        materialize is isolated too (one bad insert counts one error).
        """
        try:
            occurrences = self._expander.expand(
                to_expander_class(class_row),
                [to_expander_instance(row) for row in instance_rows],
                [to_expander_range(row) for row in range_rows],
                window_start,
                window_end,
                class_row["timezone"],
            )
        except Exception:
            result.errors += 1
            logger.warning(
                "Class history materialize: expand failed for class %s",
                class_row.get("class_id"),
                exc_info=True,
            )
            return

        for occ in occurrences:
            # window_end is today, so the expander already bounds effective_date
            # to <= today; the precise PAST gate is the UTC instant. A class
            # later today (occurred_at >= now) hasn't happened yet -> leave it.
            if occ.occurred_at >= now:
                continue
            await self._materialize_one(class_row, occ, result)

    async def _materialize_one(
        self,
        class_row: dict,
        occ: EffectiveOccurrence,
        result: SweepResult,
    ) -> None:
        """Find-or-create one class_history row; count created vs existing."""
        result.processed += 1
        try:
            _, was_created = await self._materializer.find_or_create_history(
                class_row["class_id"],
                class_row["gym_id"],
                occ.occurred_at,
                occ.instructor_id,
                occ.duration_minutes,
            )
        except Exception:
            result.errors += 1
            logger.warning(
                "Class history materialize: insert failed for class %s @ %s",
                class_row.get("class_id"),
                occ.occurred_at,
                exc_info=True,
            )
            return
        if was_created:
            result.changed += 1
        else:
            result.skipped += 1

    # -- loads -----------------------------------------------------------

    async def _load_classes(self) -> list[dict]:
        """Every non-deleted class across all gyms, with its gym timezone."""
        return await self._read_all("reconciler_active_classes.sql", {})

    async def _load_instance_exceptions(
        self,
        window_start: date,
        window_end: date,
    ) -> list[dict]:
        """Instance exceptions whose original_date is in the window."""
        return await self._read_all(
            "reconciler_class_instance_exceptions.sql",
            {"window_start": window_start, "window_end": window_end},
        )

    async def _load_range_exceptions(
        self,
        window_start: date,
        window_end: date,
    ) -> list[dict]:
        """Range exceptions overlapping the window."""
        return await self._read_all(
            "reconciler_class_range_exceptions.sql",
            {"window_start": window_start, "window_end": window_end},
        )

    @staticmethod
    def _group_by_class(rows: list[dict]) -> dict[object, list[dict]]:
        """Group exception rows by their ``class_id``."""
        grouped: dict[object, list[dict]] = defaultdict(list)
        for row in rows:
            grouped[row["class_id"]].append(row)
        return grouped

    async def _read_all(self, sql_file: str, params: dict) -> list[dict]:
        """Run a reconciler SQL file and return its rows as plain dicts."""
        sql = load_sql(SQL_DIR / sql_file)
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]
