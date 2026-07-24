"""Serves the cached growth metrics for one gym.

A pure read over ``gym_growth_metrics``: the row supplies only the payload and
its compute time, while the name, categories, render type and sort order all
come from the registry. The registry ALWAYS wins over the stored ``type``
column (which is a write-time debugging copy), so a rolling deploy where an
older container wrote an older type still serves correctly.

Rows the current code cannot render — an unknown key, or a payload that no
longer matches its model — are skipped rather than failing the page. They
self-heal on the next compute.
"""

import logging
from uuid import UUID

from pydantic import ValidationError
from sqlalchemy import text

from src.growth import SQL_DIR
from src.growth.schema.growth_schema import GrowthMetric, GrowthResponse
from src.growth.service.growth_registry import REGISTRY_BY_KEY
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class GrowthService:
    """Read-only access to a gym's cached growth metrics."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_growth(self, gym_id: UUID) -> GrowthResponse:
        """Return every renderable cached metric for a gym.

        Args:
            gym_id: The gym whose Growth page is being served.

        Returns:
            The metrics in registry order, plus the OLDEST surviving compute
            time as the page's staleness floor (``None`` when nothing has been
            computed yet).
        """
        sql = load_sql(SQL_DIR / "list_metrics_for_gym.sql")
        async with self._db_pool.session() as session:
            rows = (
                await session.execute(text(sql), {"gym_id": str(gym_id)})
            ).mappings().all()

        metrics: list[GrowthMetric] = []
        for row in rows:
            metric = self._build_metric(gym_id, row)
            if metric is not None:
                metrics.append(metric)

        metrics.sort(key=lambda metric: (metric.order, metric.key))
        computed_at = min(
            (metric.computed_at for metric in metrics),
            default=None,
        )
        return GrowthResponse(computed_at=computed_at, metrics=metrics)

    @staticmethod
    def _build_metric(gym_id: UUID, row: dict) -> GrowthMetric | None:
        """Turn one stored row into a served metric, or None to skip it."""
        key = row["key"]
        definition = REGISTRY_BY_KEY.get(key)
        if definition is None:
            logger.debug(
                "Growth metric key not in registry, skipping: gym_id=%s, key=%s",
                gym_id,
                key,
            )
            return None

        try:
            payload = definition.model.model_validate(row["data"])
        except ValidationError:
            logger.warning(
                "Growth metric payload no longer matches its model, skipping: "
                "gym_id=%s, key=%s",
                gym_id,
                key,
            )
            return None

        return GrowthMetric(
            key=definition.key,
            name=definition.name,
            categories=list(definition.categories),
            type=definition.type,
            order=definition.order,
            computed_at=row["computed_at"],
            data=payload.model_dump(mode="json"),
        )
