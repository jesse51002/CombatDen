"""Freeze and unfreeze a MEMBER's billing (subject-keyed, DB-first)."""

import logging
from datetime import date
from uuid import UUID, uuid5

from dateutil.relativedelta import relativedelta
from sqlalchemy import text

from src.memberships import SQL_DIR
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.gym_timezone import get_gym_timezone, gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsFreeze(MemberMembershipsBase):
    """Freeze and unfreeze a member's billing (subject-keyed, DB-first).

    Freeze is per SUBJECT MEMBER: the window is written to the target member's
    OWN row FIRST, then every distinct payer that bills any of that member's
    memberships is re-converged through the regular
    ``update_payments_recurring`` — the frozen member's lines drop from each
    payer's subscription, or the payer's sub pauses if every membership it bills
    is now frozen (the engine's pause-vs-cancel branch). Freezing a member
    therefore pauses only that member's own memberships, regardless of who pays;
    a payer's freeze no longer sweeps up everyone they bill. Unfreeze clears the
    window and re-converges the same payers, which re-adds the lines / clears the
    pause.

    The freeze window is the source of truth; the per-payer converges are
    best-effort — a transient payer failure is logged and self-heals on the next
    reconciler push, so the freeze is never left half-recorded.
    """

    async def freeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_months: int,
        idempotency_key: UUID,
        payer_ids: list[UUID],
    ) -> None:
        """Freeze a member's billing, DB-first.

        Writes the freeze window to the member's OWN row, then re-converges every
        payer that bills any of the member's memberships.

        Args:
            member_id: The member to freeze (their own memberships, regardless
                of who pays).
            gym_id: The gym.
            freeze_months: Number of months to freeze.
            idempotency_key: Caller-supplied key scoped to this freeze.
            payer_ids: The distinct payers billing the member's memberships
                (discovered + locked by the facade) to re-converge.

        Raises:
            ValueError: If freeze_months is not positive.
        """
        if freeze_months <= 0:
            raise ValueError("freeze_months must be positive")

        async with self._db_pool.session() as session:
            timezone = await get_gym_timezone(session, gym_id)
        today = gym_today(timezone)
        freeze_end_date = today + relativedelta(months=freeze_months)

        # ── DB-first: write the member's freeze window, THEN converge ──
        await self._crm_freeze_profile(
            member_id,
            gym_id,
            today,
            freeze_end_date,
        )
        await self._converge_payers(payer_ids, idempotency_key)

    async def unfreeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        idempotency_key: UUID,
        payer_ids: list[UUID],
    ) -> None:
        """Unfreeze a member's billing, DB-first.

        Clears the freeze window on the member's OWN row, then re-converges every
        payer that bills any of the member's memberships — re-adding the lines or
        clearing the pause. Idempotent: clearing an already-clear window is a
        no-op and the converges simply confirm the live state.

        Args:
            member_id: The member to unfreeze.
            gym_id: The gym.
            idempotency_key: Caller-supplied key scoped to this unfreeze.
            payer_ids: The distinct payers billing the member's memberships to
                re-converge.
        """
        await self._crm_unfreeze_profile(member_id, gym_id)
        await self._converge_payers(payer_ids, idempotency_key)

    # ── Private ────────────────────────────────────────────────

    async def _converge_payers(
        self,
        payer_ids: list[UUID],
        idempotency_key: UUID,
    ) -> None:
        """Re-converge each affected payer's subscription, best-effort.

        The freeze window is already written (the source of truth), so each
        converge just drives Stripe toward it. A per-payer key is derived off the
        caller's key so a client retry dedups at Stripe. A failed payer is logged
        and left for the reconciler push to re-converge — one transient error
        must not abort the others or undo the freeze. The facade holds the lock
        over every payer, so the converge runs unguarded here (no re-lock).
        """
        for payer_id in payer_ids:
            try:
                await self._payment_sync.update_payments_recurring(
                    payer_id,
                    idempotency_key=uuid5(idempotency_key, str(payer_id)),
                )
            except Exception:
                logger.error(
                    "Freeze converge failed for payer %s; the reconciler push "
                    "will re-converge it",
                    payer_id,
                    exc_info=True,
                )

    async def _crm_freeze_profile(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_start_date: date,
        freeze_end_date: date,
    ) -> None:
        """Set freeze dates on the member's OWN row."""
        sql = load_sql(SQL_DIR / "member_memberships_freeze_profile.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "freeze_start_date": freeze_start_date,
            "freeze_end_date": freeze_end_date,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()

    async def _crm_unfreeze_profile(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Clear freeze dates on the member's OWN row."""
        sql = load_sql(SQL_DIR / "member_memberships_unfreeze_profile.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
