"""Update a waiver — rename, persist a body edit, or flip requires_resign.

A name change is an in-place UPDATE of the catalog row. A body edit is
conditional on whether the current version has been signed: while it has **0
signatures** the version is **edited in place** (same version_number, body +
content_hash updated); once **a member has signed it** the signed version is
frozen and a **new** version is published (current_version_id re-pointed). An
edit whose body hashes identically to the current version leaves the text
untouched. Existing signatures always stay bound to the exact version they
signed.

``requires_resign`` rides along: stamped on a fork (default True when
omitted), applied to an in-place edit, and — with no body at all — flipped on
the CURRENT version in place (the mistake-correction toggle; moving it moves
the re-sign floor).
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
from src.waivers.waivers_exceptions import (
    WaiverNoCurrentVersionError,
    WaiverNotFoundError,
    WaiverVersionNotFoundError,
)

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
            WaiverNotFoundError: If the waiver is missing or archived
                (-> 404).
            WaiverVersionNotFoundError: If a version-scoped write matches no
                row (-> 404).
            WaiverNoCurrentVersionError: If a flag-only update targets a
                waiver with no current version (-> 400).
            ValueError: From the shared ``validate_mutable_columns`` guard
                when a rename touches an immutable column (-> 400). Untyped
                on purpose — the guard is domain-agnostic — which is why the
                router keeps a generic bad-input arm below its typed one.
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
        elif request.data.requires_resign is not None:
            await self._set_requires_resign(
                request.gym_id,
                existing.get("current_version_id"),
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
                raise WaiverNotFoundError(f"Waiver {waiver_id} not found")
            await session.commit()

    async def _maybe_publish_version(
        self,
        waiver_id: UUID,
        gym_id: UUID,
        current_version_id: UUID | None,
        body: str,
        requires_resign: bool | None,
    ) -> None:
        """Persist a body edit (in place if unsigned, else a new version).

        If the current version has 0 signatures it is edited in place; once
        it has been signed the signed version is frozen and a fresh version
        is published. ``requires_resign`` (whether prior signers must
        re-sign) is stamped on the fork (default True when None), applied to
        the in-place edit, and — when the body is unchanged — still flipped
        on the current version so the save-time choice always lands.
        """
        content_hash = self._compute_content_hash(body)
        current = (
            await self._get_version(current_version_id)
            if current_version_id is not None
            else None
        )
        if current is not None and current.content_hash == content_hash:
            # Identical body — but the re-sign choice still applies.
            if (
                requires_resign is not None
                and requires_resign != current.requires_resign
            ):
                await self._set_requires_resign(
                    gym_id, current.version_id, requires_resign,
                )
            return

        if current is not None and current.signature_count == 0:
            await self._edit_version_in_place(
                current.version_id,
                gym_id,
                body,
                content_hash,
                requires_resign,
            )
            return

        await self._publish_new_version(
            waiver_id,
            gym_id,
            body,
            content_hash,
            requires_resign if requires_resign is not None else True,
        )

    async def _edit_version_in_place(
        self,
        version_id: UUID,
        gym_id: UUID,
        body: str,
        content_hash: str,
        requires_resign: bool | None,
    ) -> None:
        """Update an unsigned version's body in place (same version_number).

        ``requires_resign`` is applied when provided (None keeps the flag).
        """
        sql = load_sql(SQL_DIR / "waiver_versions_update_body.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "version_id": str(version_id),
                    "gym_id": str(gym_id),
                    "body": body,
                    "content_hash": content_hash,
                    "requires_resign": requires_resign,
                },
            )
            if not result.mappings().fetchone():
                raise WaiverVersionNotFoundError(
                    f"Waiver version {version_id} not found",
                )
            await session.commit()

    async def _set_requires_resign(
        self,
        gym_id: UUID,
        current_version_id: UUID | None,
        requires_resign: bool,
    ) -> None:
        """Flip requires_resign on the CURRENT version (mistake correction).

        Moving the flag moves the re-sign floor: raising it re-blocks prior
        signers; lowering it makes their signatures count again.

        The two failure modes are deliberately DIFFERENT types with different
        statuses: no current-version pointer at all is a 400 (the operation has
        no target), a pointer whose row is gone is a 404 (the version was
        addressed and is missing). The 400 is inherited from the prose
        dispatch, not chosen — see ``waivers_exceptions``.
        """
        if current_version_id is None:
            raise WaiverNoCurrentVersionError("Waiver has no current version")
        sql = load_sql(SQL_DIR / "waiver_versions_update_requires_resign.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "version_id": str(current_version_id),
                    "gym_id": str(gym_id),
                    "requires_resign": requires_resign,
                },
            )
            if not result.mappings().fetchone():
                raise WaiverVersionNotFoundError(
                    f"Waiver version {current_version_id} not found",
                )
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
