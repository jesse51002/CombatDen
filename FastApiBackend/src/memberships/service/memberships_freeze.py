"""Freeze and unfreeze a MEMBER's billing (subject-keyed, DB-first)."""

import asyncio
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
    """Freeze/unfreeze a member's billing (subject-keyed, DB-first).

    Writes the freeze window to the member's own row first, then re-converges
    each affected payer. Per-payer converge failures are best-effort and self-heal.
    """

    async def freeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_months: int,
        idempotency_key: UUID,
        payer_ids: list[UUID],
    ) -> None:
        """Write the freeze window, then re-converge each payer (DB-first)."""
        if freeze_months <= 0:
            raise ValueError("freeze_months must be positive")

        async with self._db_pool.session() as session:
            timezone = await get_gym_timezone(session, gym_id)
        today = gym_today(timezone)
        freeze_end_date = today + relativedelta(months=freeze_months)

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
        """Clear the freeze window, then re-converge each payer (DB-first). Idempotent."""
        await self._crm_unfreeze_profile(member_id, gym_id)
        await self._converge_payers(payer_ids, idempotency_key)

    # ── Private ────────────────────────────────────────────────

    async def _converge_payers(
        self,
        payer_ids: list[UUID],
        idempotency_key: UUID,
    ) -> None:
        """Re-converge each payer concurrently, best-effort. Per-payer errors are logged."""
        results = await asyncio.gather(
            *(
                self._payment_sync.update_payments_recurring(
                    payer_id,
                    idempotency_key=uuid5(idempotency_key, str(payer_id)),
                )
                for payer_id in payer_ids
            ),
            return_exceptions=True,
        )
        for payer_id, result in zip(payer_ids, results, strict=True):
            if isinstance(result, Exception):
                logger.error(
                    "Freeze converge failed for payer %s; the reconciler push "
                    "will re-converge it",
                    payer_id,
                    exc_info=result,
                )

    async def _crm_freeze_profile(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_start_date: date,
        freeze_end_date: date,
    ) -> None:
        """Set freeze dates on the member's row.
        Raises ValueError if (member_id, gym_id) not found."""
        sql = load_sql(SQL_DIR / "member_memberships_freeze_profile.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "freeze_start_date": freeze_start_date,
            "freeze_end_date": freeze_end_date,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            if result.rowcount != 1:
                raise ValueError(
                    f"Member not found for gym: member_id={member_id}, "
                    f"gym_id={gym_id}",
                )
            await session.commit()

    async def _crm_unfreeze_profile(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Clear freeze dates on the member's row.
        Raises ValueError if (member_id, gym_id) not found."""
        sql = load_sql(SQL_DIR / "member_memberships_unfreeze_profile.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            if result.rowcount != 1:
                raise ValueError(
                    f"Member not found for gym: member_id={member_id}, "
                    f"gym_id={gym_id}",
                )
            await session.commit()
