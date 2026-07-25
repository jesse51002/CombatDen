"""Shared dependencies and helpers for waiver operations.

Waivers are plain gym config (no Stripe), so this base holds only the DB pool
plus the shared row fetchers and the content-hash helper used across create,
update, read, and the signature reads.
"""

from __future__ import annotations

import hashlib
import logging
from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    WaiverResponse,
    WaiverVersionResponse,
)
from src.waivers.waivers_exceptions import WaiverNotFoundError

logger = logging.getLogger(__name__)

# Hash algorithm for a waiver version's body. The hash is taken over the raw
# UTF-8 bytes of `body` exactly as stored (no normalization) so it is stable and
# reproducible, and is copied onto each signature as proof of the signed text.
WAIVER_HASH_ALGO = "sha256"


class WaiversBase:
    """Base class for waiver sub-services.

    Holds the shared DB pool and reusable query helpers used across create,
    update, delete, list, read, and signature-read operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._db_pool = db_pool

    # ── Shared helpers ─────────────────────────────────────────

    @staticmethod
    def _compute_content_hash(body: str) -> str:
        """Return the sha256 hex digest of a version body's UTF-8 bytes."""
        return hashlib.new(WAIVER_HASH_ALGO, body.encode("utf-8")).hexdigest()

    @staticmethod
    def _build_summary_response(row: dict) -> WaiverResponse:
        """Build a WaiverResponse from a waiver summary row (no body)."""
        return WaiverResponse(**dict(row))

    async def _get_waiver(self, waiver_id: UUID, gym_id: UUID) -> dict:
        """Fetch a non-deleted waiver summary row.

        Raises:
            WaiverNotFoundError: If the waiver is missing or archived
                (-> 404). Typed, so the status comes off the class rather
                than off whether this message contains "not found".
        """
        sql = load_sql(SQL_DIR / "waivers_get_by_id.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise WaiverNotFoundError(f"Waiver {waiver_id} not found")
        return dict(row)

    async def _get_version(
        self,
        version_id: UUID,
    ) -> WaiverVersionResponse | None:
        """Fetch a single version (with its signature count), or None."""
        sql = load_sql(SQL_DIR / "waiver_version_get.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"version_id": str(version_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            return None
        return WaiverVersionResponse(**dict(row))

    async def _load_full_waiver(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> WaiverResponse:
        """Load a waiver summary and embed its current version (with body).

        Raises:
            WaiverNotFoundError: If the waiver is missing or archived
                (-> 404).
        """
        response = self._build_summary_response(
            await self._get_waiver(waiver_id, gym_id),
        )
        if response.current_version_id is not None:
            response.current_version = await self._get_version(
                response.current_version_id,
            )
        return response
