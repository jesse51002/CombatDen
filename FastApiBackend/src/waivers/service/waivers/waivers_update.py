"""Update a waiver — rename in place and/or publish a new version.

A name change is an in-place UPDATE of the catalog row. A body change PUBLISHES
a new immutable version (existing versions are never mutated) and re-points
current_version_id; an edit whose body hashes identically to the current version
is a no-op (no version churn). Existing signatures stay bound to the exact
version they signed.
"""

from __future__ import annotations

import logging
from uuid import UUID

from schema.immutable_columns import GYM_WAIVERS
from sqlalchemy import text

from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    WaiverResponse,
    WaiverUpdateRequest,
)
from src.waivers.service.waivers.waivers_base import WaiversBase

logger = logging.getLogger(__name__)


class WaiversUpdate(WaiversBase):
    """Rename a waiver and/or publish a new version of its text."""

    async def update_waiver(
        self,
        request: WaiverUpdateRequest,
    ) -> WaiverResponse:
        """Apply a rename and/or a body publish, then return the waiver.

        Args:
            request: Waiver update data (optional name and/or body).

        Returns:
            The updated waiver with its current version embedded.

        Raises:
            ValueError: If the waiver is not found.
        """
        existing = await self._get_waiver(request.waiver_id, request.gym_id)

        if request.data.name is not None:
            validate_mutable_columns(GYM_WAIVERS, {"name"})
            await self._rename(
                request.waiver_id,
                request.gym_id,
                request.data.name,
            )

        if request.data.body is not None:
            await self._maybe_publish_version(
                request.waiver_id,
                request.gym_id,
                existing.get("current_version_id"),
                request.data.body,
            )

        return await self._load_full_waiver(request.waiver_id, request.gym_id)

    # ── Private ────────────────────────────────────────────────

    async def _rename(
        self,
        waiver_id: UUID,
        gym_id: UUID,
        name: str,
    ) -> None:
        """Rename the catalog row in place."""
        sql = load_sql(SQL_DIR / "waivers_update_name.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "waiver_id": str(waiver_id),
                    "gym_id": str(gym_id),
                    "name": name,
                },
            )
            if not result.mappings().fetchone():
                raise ValueError(f"Waiver {waiver_id} not found")
            await session.commit()

    async def _maybe_publish_version(
        self,
        waiver_id: UUID,
        gym_id: UUID,
        current_version_id: UUID | None,
        body: str,
    ) -> None:
        """Publish a new version unless the body is unchanged."""
        content_hash = self._compute_content_hash(body)
        if current_version_id is not None:
            current = await self._get_version(current_version_id)
            if current is not None and current.content_hash == content_hash:
                return  # No-op: identical body, no new version.

        next_number_sql = load_sql(SQL_DIR / "waiver_versions_next_number.sql")
        insert_version_sql = load_sql(SQL_DIR / "waiver_versions_insert.sql")
        set_current_sql = load_sql(SQL_DIR / "waivers_set_current_version.sql")

        async with self._db_pool.session() as session:
            next_result = await session.execute(
                text(next_number_sql),
                {"waiver_id": str(waiver_id)},
            )
            next_number = next_result.mappings().one()["next_version_number"]

            version_result = await session.execute(
                text(insert_version_sql),
                {
                    "waiver_id": str(waiver_id),
                    "gym_id": str(gym_id),
                    "version_number": next_number,
                    "body": body,
                    "content_hash": content_hash,
                },
            )
            version = dict(version_result.mappings().one())

            await session.execute(
                text(set_current_sql),
                {
                    "version_id": str(version["version_id"]),
                    "waiver_id": str(waiver_id),
                    "gym_id": str(gym_id),
                },
            )
            await session.commit()
