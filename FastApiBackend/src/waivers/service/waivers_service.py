"""Waiver CRUD + versioning + signature-read operations (facade).

Delegates to focused sub-services while preserving the public API. Waivers are
plain gym config (no Stripe): a named, versioned document plus an append-only
e-sign audit. Covers catalog CRUD, version history, read-only signature
tracking, and seed-copying a gym's undeletable default authorized-payer waiver;
the front-desk signing capture is recorded by the link flow (memberships).
"""

from __future__ import annotations

from uuid import UUID

from src.shared.database import DirectDatabasePool
from src.waivers.schema.waivers_schema import (
    AuthorizedPayerWaiverResponse,
    MemberWaiverStatusRow,
    WaiverCreateRequest,
    WaiverDefaultInfo,
    WaiverResponse,
    WaiverSignatoryRow,
    WaiverSignatureResponse,
    WaiverUpdateRequest,
    WaiverVersionResponse,
)
from src.waivers.service.waivers_create import WaiversCreate
from src.waivers.service.waivers_delete import WaiversDelete
from src.waivers.service.waivers_list import WaiversList
from src.waivers.service.waivers_signatures import WaiversSignatures
from src.waivers.service.waivers_update import WaiversUpdate
from src.waivers.service.waivers_versions import WaiversVersions


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

    async def create_default_waiver(
        self,
        gym_id: UUID,
    ) -> WaiverResponse:
        """Seed-copy the gym's undeletable default authorized-payer waiver."""
        return await self._create.create_default_waiver(gym_id)

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

    # ── Signing + default-waiver resolution ───────────────────────

    async def get_default_waiver_for_member(
        self,
        member_id: UUID,
    ) -> WaiverDefaultInfo:
        """Resolve a member's gym default authorized-payer waiver + version."""
        return await self._signatures.get_default_waiver_for_member(member_id)

    async def get_default_waiver_with_body_for_member(
        self,
        member_id: UUID,
    ) -> AuthorizedPayerWaiverResponse:
        """Resolve a member's gym default authorized-payer waiver WITH its
        current body — what the front-desk sign dialog renders before a payer
        signs. Composes the id resolution (``get_default_waiver_for_member``)
        with the body read (``get_waiver``)."""
        default = await self._signatures.get_default_waiver_for_member(member_id)
        waiver = await self._list.get_waiver(default.waiver_id, default.gym_id)
        if waiver.current_version is None:
            raise ValueError(
                f"Default waiver has no current version: "
                f"waiver_id={default.waiver_id}"
            )
        return AuthorizedPayerWaiverResponse(
            waiver_id=default.waiver_id,
            version_id=default.version_id,
            name=waiver.name,
            body=waiver.current_version.body,
        )

    async def sign_waiver(
        self,
        *,
        gym_id: UUID,
        member_id: UUID,
        waiver_id: UUID,
        waiver_version_id: UUID,
        signer_name: str,
        consent_acknowledged: bool,
        ip_address: str,
        user_agent: str,
        operator_employee_id: UUID,
        waiver_args: dict[str, str] | None = None,
    ) -> WaiverSignatureResponse:
        """Record a member's signature on a waiver in its own committed txn.

        The ONE signing path: version-locks on the echoed ``waiver_version_id``,
        renders the template body with the auto-filled placeholders + the
        caller's ``waiver_args`` (e.g. the link flow's ``payee_name``), and
        freezes the rendered text on the row.
        """
        return await self._signatures.sign_waiver(
            gym_id=gym_id,
            member_id=member_id,
            waiver_id=waiver_id,
            waiver_version_id=waiver_version_id,
            signer_name=signer_name,
            consent_acknowledged=consent_acknowledged,
            ip_address=ip_address,
            user_agent=user_agent,
            operator_employee_id=operator_employee_id,
            waiver_args=waiver_args,
        )
