"""SubscriptionCancellationAbsorber — record a Stripe-cancelled sub in the CRM.

The inverse of the push sync. When Stripe reports a family's subscription
gone/cancelled (dunning exhaustion, an out-of-band cancel, or a not-found item),
this records that fact in the CRM **only** — it makes NO Stripe calls, because
Stripe already did the cancellation ("Stripe wins; never re-push or re-bill").

For the paying family it (1) marks every live recurring membership cancelled —
sets ``cancel_date`` then stamps ``stripe_sync_status='deleted'`` — and (2) nulls
the parent's ``stripe_sub_id_month`` so the CRM stops pointing at the dead sub.

It deliberately does **not** call ``MemberMembershipsCancel.cancel()``: that path
runs an unguarded pre-sync that pushes to the (already-gone) sub and would raise
``PaymentsResourceNotFoundError`` before recording anything. The sub-id null is
also why this can't just reuse that path — the push writeback is what normally
clears the sub id, and this absorber bypasses it.

Shared by both absorption triggers: the reconciler poll
(``SubscriptionStatusSweep``) and the ``customer.subscription.deleted`` webhook.
Idempotent: an already-cancelled family yields zero cancellable rows and
re-nulling the sub id is a no-op.
"""

import logging
from datetime import date
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.shared.billing_parent_resolver import BillingParentResolver
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class SubscriptionCancellationAbsorber:
    """CRM-only absorption of a Stripe-cancelled family subscription."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        parent_resolver: BillingParentResolver,
    ) -> None:
        self._db_pool = db_pool
        self._parent = parent_resolver

    async def absorb(self, member_id: UUID) -> int:
        """Record a Stripe-cancelled subscription in the CRM; return the count.

        Resolves the paying parent of ``member_id``, marks every live recurring
        membership across the family cancelled (``cancel_date`` + ``deleted``),
        and nulls the parent's ``stripe_sub_id_month``. Makes no Stripe calls.

        Returns:
            The number of memberships marked cancelled (0 if already absorbed).
        """
        parent = await self._parent.resolve_parent(member_id)
        rows = await self._list_cancellable(parent.member_id, parent.gym_id)
        today = gym_today(parent.timezone)

        item_ids: list[str] = []
        for row in rows:
            await self._set_cancel_date(row["item_id"], row["member_id"], today)
            item_ids.append(str(row["item_id"]))
        if item_ids:
            await self._mark_deleted(item_ids)
        await self._clear_parent_sub_id(parent.member_id)

        logger.info(
            "Absorbed Stripe cancellation for family of %s: "
            "%d membership(s) cancelled, sub id cleared",
            parent.member_id,
            len(item_ids),
        )
        return len(item_ids)

    async def _list_cancellable(
        self,
        parent_member_id: UUID,
        gym_id: UUID,
    ) -> list[dict]:
        """The family's live recurring memberships to mark cancelled."""
        sql = load_sql(SQL_DIR / "member_memberships_family_cancellable.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(
                text(sql),
                {
                    "parent_member_id": str(parent_member_id),
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
        sql = load_sql(SQL_DIR / "member_memberships_cancel.sql")
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
        sql = load_sql(SQL_DIR / "payment_sync" / "mark_membership_deleted.sql")
        await self._db_pool.execute_with_retry(sql, {"item_ids": item_ids})

    async def _clear_parent_sub_id(self, parent_member_id: UUID) -> None:
        """Null the parent's ``stripe_sub_id_month`` (dead sub)."""
        sql = load_sql(
            SQL_DIR / "payment_sync" / "update_profile_sub_ids.sql",
        )
        await self._db_pool.execute_with_retry(
            sql,
            {
                "member_id": str(parent_member_id),
                "stripe_sub_id_month": None,
            },
        )
