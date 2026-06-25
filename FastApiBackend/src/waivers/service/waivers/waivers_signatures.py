"""Waiver signature tracking (reads) + the signing-capture write.

Two read views, both gym-scoped: a per-waiver roster (every member + whether
they signed it) and a per-member status list. Plus the signing-capture path:
``get_default_waiver_for_member`` resolves the gym's default authorized-payer
waiver, and ``record_signature`` inserts an append-only signature row in the
CALLER's transaction (the authorized-payer link flow records the signature +
the ``member_authorized_payers`` row atomically).
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    MemberWaiverStatusRow,
    WaiverDefaultInfo,
    WaiverSignatoryRow,
)
from src.waivers.service.waivers.waivers_base import WaiversBase


class WaiversSignatures(WaiversBase):
    """Signature tracking (reads) + the signing-capture write."""

    async def list_signatories(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> list[WaiverSignatoryRow]:
        """Return every gym member and their latest sign status for a waiver."""
        sql = load_sql(SQL_DIR / "waiver_signatures_roster.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [WaiverSignatoryRow(**dict(row)) for row in rows]

    async def list_member_status(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> list[MemberWaiverStatusRow]:
        """Return every gym waiver and this member's latest sign status for it."""
        sql = load_sql(SQL_DIR / "waiver_signatures_by_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id), "gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [MemberWaiverStatusRow(**dict(row)) for row in rows]

    # ── Signing capture ────────────────────────────────────────

    async def get_default_waiver_for_member(
        self,
        member_id: UUID,
    ) -> WaiverDefaultInfo:
        """Resolve a member's gym default authorized-payer waiver + version.

        Raises:
            ValueError: If the member's gym has no default waiver (the
                authorized-payer gate cannot proceed).
        """
        sql = load_sql(SQL_DIR / "waiver_default_for_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if row is None:
            raise ValueError(
                f"No default authorized-payer waiver for member {member_id}'s gym",
            )
        return WaiverDefaultInfo(**dict(row))

    async def record_signature(
        self,
        session: AsyncSession,
        *,
        gym_id: UUID,
        signer_member_id: UUID,
        waiver_id: UUID,
        waiver_version_id: UUID,
        signer_name: str,
        consent_acknowledged: bool,
        content_hash: str,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> UUID:
        """Insert an e-signature in the CALLER's transaction; return its id.

        Append-only. Does NOT commit — the caller (the link flow) owns the
        transaction so the signature + the ``member_authorized_payers`` row land
        atomically (no orphan signatures).
        """
        sql = load_sql(SQL_DIR / "member_waiver_signatures_insert.sql")
        result = await session.execute(
            text(sql),
            {
                "gym_id": str(gym_id),
                "signer_member_id": str(signer_member_id),
                "waiver_id": str(waiver_id),
                "waiver_version_id": str(waiver_version_id),
                "signer_name": signer_name,
                "consent_acknowledged": consent_acknowledged,
                "content_hash": content_hash,
                "ip_address": ip_address,
                "user_agent": user_agent,
            },
        )
        return result.mappings().one()["signature_id"]
