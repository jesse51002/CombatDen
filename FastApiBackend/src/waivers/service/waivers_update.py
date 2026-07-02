"""Update a waiver — rename in place and/or persist a body edit.

A name change is an in-place UPDATE of the catalog row. A body edit is
conditional on whether the current version has been signed: while it has **0
signatures** the version is **edited in place** (same version_number, body +
content_hash updated); once **a member has signed it** the signed version is
frozen and a **new** version is published (current_version_id re-pointed). An
edit whose body hashes identically to the current version is a no-op. Existing
signatures always stay bound to the exact version they signed.
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
from src.waivers.service.waivers_base import WaiversBase

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
                request.data.requires_resign,
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
        requires_resign: bool,
    ) -> None:
        """Persist a body edit (in place if unsigned, else a new version).

        No-op if the body is unchanged. If the current version has 0
        signatures it is edited in place; once it has been signed the signed
        version is frozen and a fresh version is published, stamped with
        ``requires_resign`` (whether prior signers must re-sign). The in-place
        edit ignores ``requires_resign`` — an unsigned version has no prior
        signers to invalidate.
        """
        content_hash = self._compute_content_hash(body)
        current = (
            await self._get_version(current_version_id)
            if current_version_id is not None
            else None
        )
        if current is not None and current.content_hash == content_hash:
            return  # No-op: identical body.

        if current is not None and current.signature_count == 0:
            await self._edit_version_in_place(
                current.version_id,
                gym_id,
                body,
                content_hash,
            )
            return

        await self._publish_new_version(
            waiver_id, gym_id, body, content_hash, requires_resign,
        )

    async def _edit_version_in_place(
        self,
        version_id: UUID,
        gym_id: UUID,
        body: str,
        content_hash: str,
    ) -> None:
        """Update an unsigned version's body in place (same version_number)."""
        sql = load_sql(SQL_DIR / "waiver_versions_update_body.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "version_id": str(version_id),
                    "gym_id": str(gym_id),
                    "body": body,
                    "content_hash": content_hash,
                },
            )
            if not result.mappings().fetchone():
                raise ValueError(f"Waiver version {version_id} not found")
            await session.commit()

    async def _publish_new_version(
        self,
        waiver_id: UUID,
        gym_id: UUID,
        body: str,
        content_hash: str,
        requires_resign: bool,
    ) -> None:
        """Insert a fresh version and re-point current_version_id to it."""
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
                    "requires_resign": requires_resign,
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
