"""PaymentSyncCancel — record a Stripe-gone subscription as cancelled in the CRM.

The inverse half of the sync. When the converge finds the PAYER's monthly
subscription gone on Stripe (dunning exhaustion, an out-of-band cancel, a
``canceled`` status), the sync must NOT recreate it — that would re-bill a member
Stripe already let go ("Stripe wins; never re-push or re-bill"). Instead it
records the cancellation in the CRM: mark every live recurring membership the
payer was billing (``paid_by_member_id`` = the payer) cancelled (set
``cancel_date`` then stamp ``stripe_sync_status='deleted'``) and null the payer's
``stripe_sub_id_month`` so the CRM stops pointing at the dead sub. Rows paid by
OTHER payers in the same family are untouched — their subscriptions are alive.
No Stripe calls — Stripe already cancelled.

The payer is already resolved by the caller (the sync resolves it up front), so
this takes the ``PayerProfile`` directly and re-resolves nothing. Idempotent: an
already-cancelled payer yields zero cancellable rows and re-nulling the sub id is
a no-op.
"""

import logging
from datetime import date
from uuid import UUID

from sqlalchemy import text

from src.memberships import SQL_DIR as MEMBERSHIPS_SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.payer_profile import PayerProfile
from src.shared.sql_loader import load_sql
from src.sync import SQL_DIR

logger = logging.getLogger(__name__)


class PaymentSyncCancel:
    """Record a Stripe-gone payer subscription as cancelled in the CRM."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def cancel_dead_subscription(self, payer: PayerProfile) -> int:
        """Cancel the payer's live recurring memberships; return the count.

        For the already-resolved ``payer``: mark every live recurring
        membership they bill cancelled (``cancel_date`` + ``deleted``) and null
        the payer's ``stripe_sub_id_month``. Makes no Stripe calls (Stripe
        already cancelled the subscription).

        Returns:
            The number of memberships marked cancelled (0 if already cancelled).
        """
        rows = await self._list_cancellable(payer.member_id, payer.gym_id)
        today = gym_today(payer.timezone)

        item_ids: list[str] = []
        for row in rows:
            await self._set_cancel_date(row["item_id"], row["member_id"], today)
            item_ids.append(str(row["item_id"]))
        if item_ids:
            await self._mark_deleted(item_ids)
        await self._clear_payer_sub_id(payer.member_id)

        logger.info(
            "Payment sync cancel: Stripe sub gone for payer %s; "
            "%d membership(s) cancelled, sub id cleared",
            payer.member_id,
            len(item_ids),
        )
        return len(item_ids)

    async def _list_cancellable(
        self,
        payer_member_id: UUID,
        gym_id: UUID,
    ) -> list[dict]:
        """The payer's live recurring memberships to mark cancelled."""
        sql = load_sql(MEMBERSHIPS_SQL_DIR / "member_memberships_payer_cancellable.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(
                text(sql),
                {
                    "payer_member_id": str(payer_member_id),
                    "gym_id": str(gym_id),
                },
            )
            return [dict(row) for row in res.mappings().all()]

    async def _set_cancel_date(
        self,
        item_id: UUID,
        member_id: UUID,
        today: date,
    ) -> None:
        """Set ``cancel_date`` on one membership (reuses the cancel SQL)."""
        sql = load_sql(MEMBERSHIPS_SQL_DIR / "member_memberships_cancel.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "item_id": str(item_id),
                "member_id": str(member_id),
                "gym_today": today,
            },
        )

    async def _mark_deleted(self, item_ids: list[str]) -> None:
        """Stamp ``stripe_sync_status='deleted'`` on the cancelled rows."""
        sql = load_sql(SQL_DIR / "mark_membership_deleted.sql")
        await self._db_pool.execute_with_retry(sql, {"item_ids": item_ids})

    async def _clear_payer_sub_id(self, payer_member_id: UUID) -> None:
        """Null the payer's ``stripe_sub_id_month`` (dead sub)."""
        sql = load_sql(
            SQL_DIR / "update_profile_sub_ids.sql",
        )
        await self._db_pool.execute_with_retry(
            sql,
            {
                "member_id": str(payer_member_id),
                "stripe_sub_id_month": None,
            },
        )
