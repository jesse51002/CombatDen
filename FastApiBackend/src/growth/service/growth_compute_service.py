"""Recomputes and caches every gym's growth metrics.

The whole domain's write path: one lock-guarded sweep over every gym, running
each registered metric's ``.sql`` and UPSERTing the validated payload into
``gym_growth_metrics``.

Fault tolerance is the point of the design. A metric whose SQL file has not
been written yet is logged and skipped; a metric that raises is logged and
skipped, leaving its previous (stale but valid) row untouched. Neither aborts
the gym or the sweep, so a single broken query can never blank the Growth page.

The contract with every metric SQL author: the query returns EXACTLY ONE row
with EXACTLY ONE column named ``data``, holding a jsonb object that validates
against the registry's model for that key.
"""

import json
import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text

from src.growth import SQL_DIR
from src.growth.service.growth_registry import (
    GROWTH_REGISTRY,
    GrowthMetricDef,
)
from src.shared.database import DirectDatabasePool
from src.shared.resource_lock import ResourceLock
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

DATA_COLUMN = "data"


class GrowthComputeService:
    """Recomputes the cached growth metrics for every gym."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        resource_lock: ResourceLock,
        dormancy_days: int,
        at_risk_days: int,
        lock_key: str,
        lock_ttl_seconds: int,
    ) -> None:
        self._db_pool = db_pool
        self._resource_lock = resource_lock
        self._dormancy_days = dormancy_days
        self._at_risk_days = at_risk_days
        self._lock_key = lock_key
        # The sweep runs every registered metric for every gym, so it lasts far
        # longer than the default 60s lease. Its own TTL must outlive a whole
        # sweep: an expired lease mid-run lets a second container start a
        # concurrent sweep — not corrupting (the write is an idempotent UPSERT)
        # but pure duplicated DB load.
        self._lock_ttl_seconds = lock_ttl_seconds

    async def compute_all_gyms(self) -> None:
        """Recompute every gym's metrics, guarded by the global sweep lock.

        The lock is what keeps two app containers (or a container that just
        restarted while another is mid-sweep) from doing the same work twice.
        A container that loses the race simply skips this tick.
        """
        async with self._resource_lock.try_lock(
            self._lock_key,
            ttl_seconds=self._lock_ttl_seconds,
        ) as acquired:
            if not acquired:
                logger.info(
                    "Growth compute skipped: '%s' held elsewhere",
                    self._lock_key,
                )
                return

            gym_ids = await self._load_gym_ids()
            logger.info("Growth compute starting for %d gyms", len(gym_ids))
            for gym_id in gym_ids:
                await self.compute_gym(gym_id)

    async def compute_gym(self, gym_id: UUID) -> None:
        """Recompute + UPSERT every registered metric for one gym.

        Args:
            gym_id: The gym whose metrics are recomputed.
        """
        for definition in GROWTH_REGISTRY:
            sql = self._load_metric_sql(definition)
            if sql is None:
                continue
            try:
                payload = await self._compute_metric(gym_id, definition, sql)
                await self._upsert_metric(gym_id, definition, payload)
            except Exception:
                logger.error(
                    "Growth metric failed: gym_id=%s, key=%s",
                    gym_id,
                    definition.key,
                    exc_info=True,
                )

        try:
            await self._prune_retired_metrics(gym_id)
        except Exception:
            logger.error(
                "Growth metric prune failed: gym_id=%s",
                gym_id,
                exc_info=True,
            )

    @staticmethod
    def _load_metric_sql(definition: GrowthMetricDef) -> str | None:
        """Load a metric's SQL, or None when its file does not exist yet.

        The registry lists the full target metric set while the SQL files land
        incrementally, so a missing file is an expected state, not an error.
        """
        path = SQL_DIR / definition.sql_file
        if not path.exists():
            logger.warning(
                "Growth metric SQL not found, skipping: key=%s, file=%s",
                definition.key,
                definition.sql_file,
            )
            return None
        # A file with no declared template variables must NOT go through
        # ``str.format_map`` — an untemplated literal brace would explode.
        if definition.sql_variables is None:
            return load_sql(path)
        return load_sql(path, definition.sql_variables)

    def _build_params(
        self,
        gym_id: UUID,
        definition: GrowthMetricDef,
    ) -> dict[str, Any]:
        """The bind dict for one metric, restricted to the binds it declares.

        SQLAlchemy's ``text()`` raises on a parameter it cannot find in the
        statement, so passing the full set to every query is not an option.
        """
        available: dict[str, Any] = {
            "gym_id": str(gym_id),
            "dormancy_days": self._dormancy_days,
            "at_risk_days": self._at_risk_days,
        }
        return {name: available[name] for name in definition.params}

    async def _compute_metric(
        self,
        gym_id: UUID,
        definition: GrowthMetricDef,
        sql: str,
    ) -> dict[str, Any]:
        """Run one metric's query and validate its payload.

        Returns:
            The payload, normalized through the registry's model so what is
            stored is exactly what the serve path will validate.

        Raises:
            ValueError: If the query returned no row.
            pydantic.ValidationError: If the payload does not match the model.
        """
        params = self._build_params(gym_id, definition)
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql), params)).mappings().all()
        if not rows:
            raise ValueError(
                f"Growth metric '{definition.key}' returned no row"
            )
        payload = definition.model.model_validate(rows[0][DATA_COLUMN])
        return payload.model_dump(mode="json")

    async def _upsert_metric(
        self,
        gym_id: UUID,
        definition: GrowthMetricDef,
        payload: dict[str, Any],
    ) -> None:
        """Write one metric's payload, replacing any previous row."""
        sql = load_sql(SQL_DIR / "upsert_metric.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "gym_id": str(gym_id),
                "key": definition.key,
                "type": definition.type.value,
                "data": json.dumps(payload),
            },
        )

    async def _prune_retired_metrics(self, gym_id: UUID) -> None:
        """Delete this gym's rows for keys the registry no longer defines."""
        sql = load_sql(SQL_DIR / "prune_retired_metrics.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "gym_id": str(gym_id),
                "keys": [definition.key for definition in GROWTH_REGISTRY],
            },
        )

    async def _load_gym_ids(self) -> list[UUID]:
        """Every gym id the sweep iterates."""
        sql = load_sql(SQL_DIR / "list_gym_ids.sql")
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql), {})).mappings().all()
        return [UUID(str(row["gym_id"])) for row in rows]
