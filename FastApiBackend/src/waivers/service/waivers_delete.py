"""Archive (soft-delete) a waiver catalog entry.

Flips is_deleted = true. The waiver's versions and any signatures are retained
(legal record); only the catalog entry is hidden from listings. In the same
transaction, the waiver's id is stripped from every plan's ``waiver_ids`` so
plans stay truthful (the start gate already ignores archived waivers).

The payer-auth waiver is never archivable. The DB trigger only blocks the
client roles (authenticated/anon) — this endpoint runs at service role, so the
guard here is the one that actually protects the API path.
"""

from __future__ import annotations

import logging
from uuid import UUID

from schema.gym_waiver import WaiverType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.service.waivers_base import WaiversBase
from src.waivers.waivers_exceptions import (
    WaiverNotFoundError,
    WaiverPayerAuthNotArchivableError,
)

logger = logging.getLogger(__name__)


class WaiversDelete(WaiversBase):
    """Archive a waiver by soft-deleting its catalog entry."""

    async def delete_waiver(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Archive a waiver (is_deleted = true) and strip it from plans.

        Args:
            waiver_id: The waiver to archive.
            gym_id: The gym owning the waiver (authorization scope).

        Raises:
            WaiverNotFoundError: If the waiver is missing or already
                archived (-> 404).
            WaiverPayerAuthNotArchivableError: If it is the gym's payer-auth
                waiver, which is never archivable (-> 400). Separate TYPES on
                purpose — "refused" and "missing" are different answers and
                must not be able to swap places.
        """
        waiver = await self._get_waiver(waiver_id, gym_id)
        if waiver["waiver_type"] == WaiverType.payer_auth:
            raise WaiverPayerAuthNotArchivableError(
                "The payer-auth waiver cannot be archived",
            )

        delete_sql = load_sql(SQL_DIR / "waivers_soft_delete.sql")
        strip_sql = load_sql(SQL_DIR / "membership_plans_strip_waiver_id.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(delete_sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            if not result.mappings().fetchone():
                raise WaiverNotFoundError(f"Waiver {waiver_id} not found")
            await session.execute(
                text(strip_sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            await session.commit()
