"""Waiver signature tracking (reads) + the signing-capture write.

Two read views, both gym-scoped: a per-waiver roster (every member + whether
they signed it) and a per-member status list. Plus the ONE signing path:
``sign_waiver`` records an append-only signature in its own committed
transaction, version-locked on the echoed version. It RENDERS the version's
template body (``{{placeholders}}``) from auto-filled account/gym/clock values
plus the caller's ``waiver_args`` (e.g. the link flow passes ``payee_name``),
and freezes the full rendered text on the row. The standalone signing endpoint
and the authorize-payer link flow both call it. ``get_payer_auth_waiver_for_member``
resolves the gym's payer-auth waiver for display.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from schema.esign_disclosure import ESIGN_DISCLOSURE_VERSION
from schema.waiver_parameters import WaiverParameter
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401
from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    MemberWaiverStatusRow,
    WaiverPayerAuthInfo,
    WaiverSignatoryRow,
    WaiverSignatureResponse,
)
from src.waivers.service.waivers_base import WaiversBase
from src.waivers.waivers_exceptions import (
    WaiverNotFoundError,
    WaiverPayerAuthMissingError,
    WaiverSignerNotInGymError,
    WaiverVersionNotFoundError,
    WaiverVersionStaleError,
)

# A waiver token as a markdown serializer may store it: each brace and the
# underscores optionally backslash-escaped (e.g. ``\{\{member\_name\}\}``).
_ESCAPED_TOKEN = re.compile(r"\\?\{\\?\{((?:\w|\\_)+)\\?\}\\?\}")


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

    async def get_payer_auth_waiver_for_member(
        self,
        member_id: UUID,
    ) -> WaiverPayerAuthInfo:
        """Resolve a member's gym payer-auth waiver + version.

        Raises:
            WaiverPayerAuthMissingError: The member's gym has no payer-auth
                waiver, so the authorized-payer gate cannot proceed. 404 on
                EVERY caller — see ``waivers_exceptions``.
        """
        sql = load_sql(SQL_DIR / "waiver_payer_auth_for_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if row is None:
            raise WaiverPayerAuthMissingError(
                f"No payer-auth waiver for member {member_id}'s gym",
            )
        return WaiverPayerAuthInfo(**dict(row))

    @staticmethod
    def _render(template: str, args: dict[str, str]) -> str:
        """Substitute ``{{key}}`` tokens in a waiver template with ``args``.

        Only known keys are replaced; an unknown ``{{...}}`` token renders
        literally (the CRM editor surfaces the available placeholders so authors
        only use real ones — see ``schema/waiver_parameters.py``).

        The template is MARKDOWN, and a markdown serializer may
        backslash-escape literal braces/underscores — storing a token as
        ``\\{\\{member\\_name\\}\\}`` (displays identically in the editor, but a
        plain string match never sees it; this silently broke rendering in
        live testing). The token regex matches both forms.

        Substitution is a SINGLE pass over the template — a substituted
        value is never re-scanned, so a signer typing a literal
        ``{{gym_name}}`` into the free-text name field lands verbatim in
        the frozen legal ``rendered_body`` instead of being expanded by a
        later key (placeholder injection). Mirrors the CRM preview's
        single-pass ``replaceAllMapped``.
        """

        def _substitute(match: re.Match[str]) -> str:
            key = match.group(1).replace("\\_", "_")
            if key in args:
                return args[key]
            return "{{" + key + "}}"

        return _ESCAPED_TOKEN.sub(_substitute, template)

    async def _insert_signature_row(
        self,
        session: AsyncSession,
        *,
        gym_id: UUID,
        signer_member_id: UUID,
        waiver_id: UUID,
        waiver_version_id: UUID,
        signer_name: str,
        consent_acknowledged: bool,
        rendered_body: str,
        content_hash: str,
        ip_address: str | None,
        user_agent: str | None,
        operator_employee_id: UUID | None,
        esign_disclosure_version: str,
    ) -> Mapping[str, Any]:
        """Execute the append-only signature INSERT; return its RETURNING row.

        The shared insert used by ``sign_waiver``; runs in the given session and
        does NOT commit (the caller owns the transaction).
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
                "rendered_body": rendered_body,
                "content_hash": content_hash,
                "ip_address": ip_address,
                "user_agent": user_agent,
                "esign_disclosure_version": esign_disclosure_version,
                "operator_employee_id": (
                    str(operator_employee_id)
                    if operator_employee_id is not None
                    else None
                ),
            },
        )
        return result.mappings().one()

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
        """Record one member's signature on a waiver in its OWN committed txn.

        The ONE signing path (any member, any waiver). The client echoes the
        ``waiver_version_id`` it displayed; this version-locks on the waiver's
        CURRENT version (rejecting a stale echo) before signing, so the signed
        version is always the one the signer saw.

        The version's template body is RENDERED with the auto-filled placeholders
        (``member_name`` = ``member_id``'s account name, ``signer_name`` = the
        typed name, ``gym_name``, ``date``) plus the caller's ``waiver_args``
        (e.g. the link flow passes ``payee_name``); the full rendered text and its
        sha256 are frozen on the row.

        Raises:
            WaiverNotFoundError: The waiver is missing or archived (→ 404).
            WaiverVersionNotFoundError: The waiver has no current version to
                sign (→ 404).
            WaiverVersionStaleError: The echoed version is not the current
                one (→ 409).
            WaiverSignerNotInGymError: The member is not in this gym (→ 404).
        """
        sql = load_sql(SQL_DIR / "waiver_current_version_for_sign.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "waiver_id": str(waiver_id),
                    "gym_id": str(gym_id),
                    "member_id": str(member_id),
                },
            )
            waiver = result.mappings().fetchone()

            if waiver is None or waiver["is_deleted"]:
                raise WaiverNotFoundError(
                    f"Waiver {waiver_id} not found in gym {gym_id}",
                )
            current_version_id = waiver["current_version_id"]
            if current_version_id is None:
                raise WaiverVersionNotFoundError(
                    f"Waiver {waiver_id} has no current version to sign",
                )
            if str(waiver_version_id) != str(current_version_id):
                raise WaiverVersionStaleError(
                    "Waiver was updated since it was displayed — reload and "
                    "sign the current version",
                )

            rendered_body = self._render(
                waiver["template_body"],
                self._build_args(waiver, signer_name, waiver_args),
            )
            content_hash = self._compute_content_hash(rendered_body)

            try:
                row = await self._insert_signature_row(
                    session,
                    gym_id=gym_id,
                    signer_member_id=member_id,
                    waiver_id=waiver_id,
                    waiver_version_id=waiver_version_id,
                    signer_name=signer_name,
                    consent_acknowledged=consent_acknowledged,
                    rendered_body=rendered_body,
                    content_hash=content_hash,
                    ip_address=ip_address,
                    user_agent=user_agent,
                    operator_employee_id=operator_employee_id,
                    esign_disclosure_version=ESIGN_DISCLOSURE_VERSION,
                )
                await session.commit()
            except IntegrityError as exc:
                # The waiver + version are pre-validated above and the operator
                # is auth-verified, so the only FK left to trip is the member's
                # (member_id, gym_id) — i.e. the member is not in this gym.
                raise WaiverSignerNotInGymError(
                    f"Member {member_id} not found in gym {gym_id}",
                ) from exc

        return WaiverSignatureResponse(
            signature_id=row["signature_id"],
            waiver_id=waiver_id,
            waiver_version_id=waiver_version_id,
            member_id=member_id,
            gym_id=gym_id,
            signed_at=row["signed_at"],
            signer_name=signer_name,
            signature_type=row["signature_type"],
        )

    @staticmethod
    def _build_args(
        waiver: Mapping[str, Any],
        signer_name: str,
        waiver_args: dict[str, str] | None,
    ) -> dict[str, str]:
        """Assemble the placeholder values: auto-filled fields + caller extras.

        ``member_name`` is the signing member's account name (falling back to the
        typed ``signer_name`` if the member row is absent — the insert FK then
        surfaces the real "not in gym" error). Caller ``waiver_args`` (e.g.
        ``payee_name``) override / extend the auto-filled set.
        """
        member_name = signer_name
        if waiver["member_first_name"] is not None:
            member_name = (
                f"{waiver['member_first_name']} "
                f"{waiver['member_last_name']}"
            )
        args = {
            WaiverParameter.member_name: member_name,
            WaiverParameter.signer_name: signer_name,
            WaiverParameter.gym_name: waiver["gym_name"],
            WaiverParameter.date: datetime.now(UTC).date().isoformat(),
        }
        if waiver_args:
            args.update(waiver_args)
        return args
