"""Waiver CRUD + versioning + signature-read operations (facade).

Delegates to focused sub-services while preserving the public API. Waivers are
plain gym config (no Stripe): a named, versioned document plus an append-only
e-sign audit. Phase 1 covers catalog CRUD, version history, and read-only
signature tracking; the front-desk signing capture is Phase 2.
"""

from __future__ import annotations

from uuid import UUID

from src.shared.database import DirectDatabasePool
from src.waivers.schema.waivers_schema import (
    MemberWaiverStatusRow,
    WaiverCreateRequest,
    WaiverResponse,
    WaiverSignatoryRow,
    WaiverUpdateRequest,
    WaiverVersionResponse,
)
from src.waivers.service.waivers.waivers_create import WaiversCreate
from src.waivers.service.waivers.waivers_delete import WaiversDelete
from src.waivers.service.waivers.waivers_list import WaiversList
from src.waivers.service.waivers.waivers_signatures import WaiversSignatures
from src.waivers.service.waivers.waivers_update import WaiversUpdate
from src.waivers.service.waivers.waivers_versions import WaiversVersions


class WaiversService:
    """Waiver CRUD + versioning + signature reads (facade).

    Delegates to focused sub-services for create, update, archive, list, read,
    version history, and signature tracking.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._create = WaiversCreate(db_pool)
        self._update = WaiversUpdate(db_pool)
        self._delete = WaiversDelete(db_pool)
        self._list = WaiversList(db_pool)
        self._versions = WaiversVersions(db_pool)
        self._signatures = WaiversSignatures(db_pool)

    # ── List / read ────────────────────────────────────────────

    async def list_waivers(
        self,
        gym_id: UUID,
    ) -> list[WaiverResponse]:
        """List non-deleted waivers for a gym."""
        return await self._list.list_waivers(gym_id)

    async def get_waiver(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> WaiverResponse:
        """Get one waiver with its current version body."""
        return await self._list.get_waiver(waiver_id, gym_id)

    # ── Create / update / delete ───────────────────────────────

    async def create_waiver(
        self,
        request: WaiverCreateRequest,
    ) -> WaiverResponse:
        """Create a waiver and publish its first version."""
        return await self._create.create_waiver(request)

    async def update_waiver(
        self,
        request: WaiverUpdateRequest,
    ) -> WaiverResponse:
        """Rename and/or publish a new version of a waiver's text."""
        return await self._update.update_waiver(request)

    async def delete_waiver(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Archive a waiver (soft-delete)."""
        await self._delete.delete_waiver(waiver_id, gym_id)

    # ── Versions ───────────────────────────────────────────────

    async def list_versions(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> list[WaiverVersionResponse]:
        """List a waiver's version history with per-version sign counts."""
        return await self._versions.list_versions(waiver_id, gym_id)

    # ── Signature tracking (read-only) ─────────────────────────

    async def list_signatories(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> list[WaiverSignatoryRow]:
        """List every gym member and their sign status for a waiver."""
        return await self._signatures.list_signatories(waiver_id, gym_id)

    async def list_member_status(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> list[MemberWaiverStatusRow]:
        """List every gym waiver and a member's sign status for each."""
        return await self._signatures.list_member_status(member_id, gym_id)
