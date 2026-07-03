"""Create a waiver — inserts the catalog row and publishes version 1.

The catalog row, its first version, and the current-version pointer are written
in a single transaction (the gym_waivers.current_version_id FK to
gym_waiver_versions is satisfied because the version row exists in the same
transaction before the pointer is set).

``create_waiver`` is the gym-staff path (a ``custom`` waiver);
``create_payer_auth_waiver`` seed-copies the shared platform default
authorized-payer agreement into the gym's own undeletable ``payer_auth`` row
(the gym then owns and versions its copy).
"""

from __future__ import annotations

import logging
from uuid import UUID

from schema.default_waiver import (
    DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME,
    default_authorized_payer_waiver_body,
)
from schema.gym_waiver import WaiverType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    WaiverCreateRequest,
    WaiverResponse,
)
from src.waivers.service.waivers_base import WaiversBase

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
        return await self._create(
            request.gym_id,
            request.name,
            request.body,
            waiver_type=WaiverType.custom,
        )

    async def create_payer_auth_waiver(
        self,
        gym_id: UUID,
    ) -> WaiverResponse:
        """Seed-copy the shared default authorized-payer agreement into a gym.

        Creates the gym's undeletable ``payer_auth`` waiver from the shared
        platform default name + body. Called when a gym is created so the
        authorized-payer gate always has a document to sign.
        """
        return await self._create(
            gym_id,
            DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME,
            default_authorized_payer_waiver_body(),
            waiver_type=WaiverType.payer_auth,
        )

    async def _create(
        self,
        gym_id: UUID,
        name: str,
        body: str,
        *,
        waiver_type: WaiverType,
    ) -> WaiverResponse:
        """Insert a waiver + version 1 + current-version pointer in one txn."""
        insert_name = (
            "waivers_insert_payer_auth.sql"
            if waiver_type is WaiverType.payer_auth
            else "waivers_insert.sql"
        )
        insert_waiver_sql = load_sql(SQL_DIR / insert_name)
        insert_version_sql = load_sql(SQL_DIR / "waiver_versions_insert.sql")
        set_current_sql = load_sql(SQL_DIR / "waivers_set_current_version.sql")
        content_hash = self._compute_content_hash(body)

        async with self._db_pool.session() as session:
            waiver_result = await session.execute(
                text(insert_waiver_sql),
                {"gym_id": str(gym_id), "name": name},
            )
            waiver = dict(waiver_result.mappings().one())

            version_result = await session.execute(
                text(insert_version_sql),
                {
                    "waiver_id": str(waiver["waiver_id"]),
                    "gym_id": str(gym_id),
                    "version_number": _FIRST_VERSION_NUMBER,
                    "body": body,
                    "content_hash": content_hash,
                    # Version 1: everyone signs it (no prior signers to spare).
                    "requires_resign": True,
                },
            )
            version = dict(version_result.mappings().one())

            await session.execute(
                text(set_current_sql),
                {
                    "version_id": str(version["version_id"]),
                    "waiver_id": str(waiver["waiver_id"]),
                    "gym_id": str(gym_id),
                },
            )
            await session.commit()

        return await self._load_full_waiver(
            waiver["waiver_id"],
            gym_id,
        )
