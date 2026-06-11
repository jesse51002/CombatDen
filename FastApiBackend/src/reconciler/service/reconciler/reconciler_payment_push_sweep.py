"""PaymentPushSweep — converge each idle billing family CRM -> Stripe.

The CRM owns config/intent; the engine self-heals drift only when a member is
touched. This sweep is the "touch on a clock" for idle members: it lists the
distinct paying parents with an active recurring membership and hands them to the
existing ``PaymentSyncService.bulk_payment_sync``, which mints a fresh key per
family, locks the family, and runs ``update_payments_recurring`` with
``proration_behavior='none'`` (billing = none -> no charges). This is what
enforces an ongoing discount's ``end_date`` and backstops a missed once-discount
settle on an idle member.

Accepted, documented gap (not built here): ``execute_sync`` issues a Stripe
``update`` every run with no skip-if-equal diff guard, so an in-sync family still
gets a (no-op, no-proration) write each sweep. ``bulk_payment_sync`` returns
``None`` and logs its own per-member failures, so this sweep reports only how
many families it submitted, not per-family outcomes.
"""

import logging
from uuid import UUID

from sqlalchemy import text

from src.reconciler import SQL_DIR
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.sync.service.sync_service import (
    PaymentSyncService,
)

logger = logging.getLogger(__name__)

SWEEP_NAME = "payment_push"


class PaymentPushSweep:
    """Push CRM-derived desired state onto Stripe for idle billing families."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
    ) -> None:
        self._db_pool = db_pool
        self._payment_sync = payment_sync_service

    async def run(self) -> SweepResult:
        """Submit every active billing family to the bulk payment sync."""
        member_ids = await self._list_paying_parent_ids()
        result = SweepResult(name=SWEEP_NAME, processed=len(member_ids))
        if member_ids:
            await self._payment_sync.bulk_payment_sync(member_ids)
        logger.info(
            "Payment push: submitted %d billing family/families to bulk sync",
            len(member_ids),
        )
        return result

    async def _list_paying_parent_ids(self) -> list[UUID]:
        """Distinct paying parents with an active recurring membership."""
        sql = load_sql(SQL_DIR / "reconciler_active_billing_members.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return [row["member_id"] for row in res.mappings().all()]
