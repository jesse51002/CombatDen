"""Authorize / de-authorize a payer for a member (the authorization layer).

Adding an authorized payer is **gated by a signed waiver** and happens in ONE
op: it calls the shared signing service (``WaiversService.sign_waiver`` — the one
signing path) to sign the gym's payer-auth waiver, rendering the
payer's name and the member-being-paid-for's name into it, then records the
``member_authorized_payers`` row referencing the new signature. Signing commits
its own txn and the authorization insert is separate (NOT atomic) — a retry after
a failed insert leaves a harmless extra append-only signature. A member may have
MANY authorized payers, and a member may be an authorized payer for others — the
relationship is many-to-many. This is the AUTHORIZATION layer only (who is
*allowed* to pay for whom); billing is per payer via
``member_memberships.paid_by_member_id``.

These are **pure DB changes — no Stripe sync** and **no billing-state guard**:
the authorization row never contributes a membership line or discount, and the
engine derives each membership's bill from that membership's own payer only, so
adding/removing an authorization never changes anyone's bill (no
no-active-recurring precondition).

The two-family ``PayingMemberLock`` is held across each op so the
check-then-write cannot race a concurrent membership start on either account.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.waiver_parameters import WaiverParameter
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MembersBillingLinkCheckResponse,
)
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.shared.database import DirectDatabasePool
    from src.shared.paying_member_lock import PayingMemberLock
    from src.waivers.service.waivers_service import WaiversService

logger = logging.getLogger(__name__)


class MemberMembershipsLinked:
    """Authorize / de-authorize a payer for a member (many-to-many).

    Self-contained (does not share ``MemberMembershipsBase``): authorization is
    member-keyed and writes ``member_authorized_payers`` (+ a signature), so the
    base's item-keyed membership-row helpers do not apply.

    Owns its OWN concurrency locking: each op locks TWO accounts (the member and
    the payer), so — unlike the single-family lifecycle ops — the facade must NOT
    wrap these in ``lock([member_id])``.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        paying_lock: PayingMemberLock,
        waivers_service: WaiversService,
    ) -> None:
        self._db_pool = db_pool
        self._paying_lock = paying_lock
        self._waivers = waivers_service

    # ── Authorize (link) ───────────────────────────────────────

    async def link_account(
        self,
        member_id: UUID,
        payer_member_id: UUID,
        *,
        waiver_version_id: UUID,
        signer_name: str,
        consent_acknowledged: bool,
        ip_address: str,
        user_agent: str,
        operator_employee_id: UUID,
    ) -> None:
        """Authorize ``payer_member_id`` to pay for ``member_id`` (sign + record).

        Calls the shared signing service to sign the gym's payer-auth
        waiver as the payer (rendering ``{{member_name}}`` = the
        payer's account name and ``{{payee_name}}`` = the member being paid for),
        then records the ``member_authorized_payers`` row referencing the new
        signature.

        Args:
            member_id: The member being paid for.
            payer_member_id: The payer to authorize (the signer).
            waiver_version_id: The payer-auth waiver version the client displayed
                (version-locked by the signing service before signing).
            signer_name: The payer's typed legal name at signing.
            consent_acknowledged: Must be True (a valid e-signature).
            ip_address / user_agent: Signing-context audit fields.
            operator_employee_id: The staff member capturing the signature.

        Raises:
            ValueError: If the member is not found, the payer is missing / in a
                different gym, the payer is the member, the displayed version is
                stale (reload), consent is False, or the pair is already
                authorized.
        """
        if member_id == payer_member_id:
            raise ValueError(
                "A member cannot be an authorized payer for themselves",
            )
        if not consent_acknowledged:
            raise ValueError("consent_acknowledged must be true to sign")

        # Lock BOTH accounts — the member's and the payer's — so the
        # check-then-write can't race a concurrent op on either.
        async with self._paying_lock.lock([member_id, payer_member_id]):
            row = await self._run_link_check(member_id, payer_member_id)
            blocked = self._link_block_reason(row)
            if blocked is not None:
                raise ValueError(blocked)

            gym_id = row["candidate_gym_id"]
            payee_name = (
                f"{row['candidate_first_name']} {row['candidate_last_name']}"
            )
            payer_auth = await self._waivers.get_payer_auth_waiver_for_member(
                member_id,
            )

            # Sign via the ONE signing service: it renders the payer's name as
            # {{member_name}} and the member-being-paid-for as {{payee_name}},
            # version-locks on the echoed version, and commits its own txn. The
            # authorization insert below is separate — a retry after a failed
            # insert leaves a harmless extra append-only signature.
            signature = await self._waivers.sign_waiver(
                gym_id=gym_id,
                member_id=payer_member_id,
                waiver_id=payer_auth.waiver_id,
                waiver_version_id=waiver_version_id,
                signer_name=signer_name,
                consent_acknowledged=consent_acknowledged,
                ip_address=ip_address,
                user_agent=user_agent,
                operator_employee_id=operator_employee_id,
                waiver_args={WaiverParameter.payee_name: payee_name},
            )

            insert_sql = load_sql(
                SQL_DIR / "member_authorized_payers_insert.sql",
            )
            try:
                async with self._db_pool.session() as session:
                    await session.execute(
                        text(insert_sql),
                        {
                            "member_id": str(member_id),
                            "payer_member_id": str(payer_member_id),
                            "gym_id": str(gym_id),
                            "signature_id": str(signature.signature_id),
                        },
                    )
                    await session.commit()
            except IntegrityError as exc:
                # Backstop: the pair lock serializes same-pair link calls, so the
                # _link_block_reason check above normally catches a duplicate. If
                # two ever race past it, the second INSERT trips the
                # member_authorized_payers PK — translate that to the same
                # user-facing "already authorized" error (a 400) instead of an
                # unhandled 500.
                raise ValueError(
                    f"Payer {payer_member_id} is already an authorized payer "
                    f"for member {member_id}",
                ) from exc

    # ── Check ──────────────────────────────────────────────────

    async def check_link_account(
        self,
        member_id: UUID,
        payer_member_id: UUID,
    ) -> MembersBillingLinkCheckResponse:
        """Check whether ``payer_member_id`` can be authorized for ``member_id``.

        Read-only. Returns a structured result with a user-facing ``error``
        string when the authorization is blocked.

        Raises:
            ValueError: If the member does not exist (→ 404).
        """
        if member_id == payer_member_id:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error=(
                    "You can't authorize an account to pay for itself. "
                    "Pick a different payer."
                ),
            )

        row = await self._run_link_check(member_id, payer_member_id)
        blocked = self._link_block_reason(row)
        if blocked is not None:
            return MembersBillingLinkCheckResponse(
                can_link=False,
                error=blocked,
            )
        return MembersBillingLinkCheckResponse(can_link=True, error=None)

    # ── Private ────────────────────────────────────────────────

    async def _run_link_check(
        self,
        member_id: UUID,
        payer_member_id: UUID,
    ) -> dict:
        """Run the link-check read; raise if the member does not exist."""
        sql = load_sql(SQL_DIR / "member_authorized_payers_link_check.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_id": str(member_id),
                    "payer_member_id": str(payer_member_id),
                },
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {member_id} not found")
        return dict(row)

    @staticmethod
    def _link_block_reason(row: dict) -> str | None:
        """Return a user-facing reason the authorization is blocked, or None."""
        if row["payer_member_id"] is None:
            return (
                "The selected payer account could not be found. "
                "Pick a different payer."
            )
        if row["candidate_gym_id"] != row["payer_gym_id"]:
            return (
                "The selected payer is in a different gym. "
                "Pick a payer from the same gym."
            )
        if row["already_authorized"]:
            return "That payer is already authorized to pay for this member."
        return None
