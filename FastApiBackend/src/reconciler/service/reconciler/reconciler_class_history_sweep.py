"""ClassHistorySweep — materialize class occurrences (NON-billing).

An INDEPENDENT, non-billing reconciler step. It touches no Stripe, no
membership, and no payment state. It is a THIN per-gym loop: for every gym it
calls the shared ``ClassesMaterializer.materialize_current`` — the ONE
range-parameterized entry point (also used by the check-in resolve seam and
the schedule board) that owns the load + expand + per-occurrence write. This
keeps recorded class history complete even for occurrences no member ever
checked into (the check-in path only materializes the occurrence(s) someone
actually resolves).

``materialize_current`` applies the materializer's own injected
``lookback_days`` / ``future_hours`` window
(``[today - lookback_days, today + future_hours]``) and per-class /
per-occurrence error isolation internally — this sweep owns none of that
logic, only the gym list + per-gym isolation (one gym's failure is logged and
never aborts the rest) + result aggregation.
"""

import logging
from uuid import UUID

from sqlalchemy import text

from src.classes.service.classes_materializer import ClassesMaterializer
from src.reconciler import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.sweep_result import SweepResult

logger = logging.getLogger(__name__)

SWEEP_NAME = "class_history_materialize"


class ClassHistorySweep:
    """Backfill ``class_history`` for every gym via the shared materializer.

    Args:
        db_pool: Injected database connection pool (used only to list gyms).
        materializer: The shared range-materialize entry point — owns the
            load + expand + per-occurrence write and the lookback /
            future-window config (injected into IT, not read here).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        materializer: ClassesMaterializer,
    ) -> None:
        self._db_pool = db_pool
        self._materializer = materializer

    async def run(self) -> SweepResult:
        """Call ``materialize_current`` for every gym; per-gym isolation."""
        result = SweepResult(name=SWEEP_NAME)
        gym_ids = await self._load_gym_ids()

        for gym_id in gym_ids:
            result.processed += 1
            try:
                created = await self._materializer.materialize_current(
                    gym_id
                )
            except Exception:
                result.errors += 1
                logger.warning(
                    "Class history materialize: gym %s failed",
                    gym_id,
                    exc_info=True,
                )
                continue
            result.changed += created

        logger.info(
            "Class history materialize: gyms=%d created=%d errors=%d",
            result.processed,
            result.changed,
            result.errors,
        )
        return result

    # -- loads -------------------------------------------------------------

    async def _load_gym_ids(self) -> list[UUID]:
        """Every gym — the sweep's scope is not Stripe-Connect-gated (a gym
        with no billing set up still has classes / check-in)."""
        sql = load_sql(SQL_DIR / "reconciler_all_gyms.sql")
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql))).mappings().all()
        return [row["gym_id"] for row in rows]
