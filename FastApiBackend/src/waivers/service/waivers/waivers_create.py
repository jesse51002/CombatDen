"""Create a waiver — inserts the catalog row and publishes version 1.

The catalog row, its first version, and the current-version pointer are written
in a single transaction (the gym_waivers.current_version_id FK to
gym_waiver_versions is satisfied because the version row exists in the same
transaction before the pointer is set).
"""

from __future__ import annotations

import logging

from sqlalchemy import text

from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    WaiverCreateRequest,
    WaiverResponse,
)
from src.waivers.service.waivers.waivers_base import WaiversBase

logger = logging.getLogger(__name__)

_FIRST_VERSION_NUMBER = 1


class WaiversCreate(WaiversBase):
    """Create a waiver and publish its first version."""

    async def create_waiver(
        self,
        request: WaiverCreateRequest,
    ) -> WaiverResponse:
        """Insert the waiver + version 1 and return the full waiver.

        Args:
            request: Waiver creation data (name + body).

        Returns:
            The created waiver with its current version embedded.
        """
        insert_waiver_sql = load_sql(SQL_DIR / "waivers_insert.sql")
        insert_version_sql = load_sql(SQL_DIR / "waiver_versions_insert.sql")
        set_current_sql = load_sql(SQL_DIR / "waivers_set_current_version.sql")
        content_hash = self._compute_content_hash(request.body)

        async with self._db_pool.session() as session:
            waiver_result = await session.execute(
                text(insert_waiver_sql),
                {"gym_id": str(request.gym_id), "name": request.name},
            )
            waiver = dict(waiver_result.mappings().one())

            version_result = await session.execute(
                text(insert_version_sql),
                {
                    "waiver_id": str(waiver["waiver_id"]),
                    "gym_id": str(request.gym_id),
                    "version_number": _FIRST_VERSION_NUMBER,
                    "body": request.body,
                    "content_hash": content_hash,
                },
            )
            version = dict(version_result.mappings().one())

            await session.execute(
                text(set_current_sql),
                {
                    "version_id": str(version["version_id"]),
                    "waiver_id": str(waiver["waiver_id"]),
                    "gym_id": str(request.gym_id),
                },
            )
            await session.commit()

        return await self._load_full_waiver(
            waiver["waiver_id"],
            request.gym_id,
        )
