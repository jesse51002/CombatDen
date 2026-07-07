"""OrphanCleanupSweep — delete stranded ``not_added`` membership rows safely.

A membership-start writes a pending row (NULL ``stripe_item_id``,
``stripe_sync_status='not_added'``) then converges Stripe under the payer lock,
deleting the row if the sync does not confirm. A crash mid-op can strand the
pending row. This sweep removes such rows — but only after a **non-blocking**
acquire of that row's PAYER lock (its ``paid_by_member_id``): if the lock is
held an op is in flight (leave it), if free it is a genuine orphan (delete it).
The delete itself still guards ``stripe_item_id IS NULL`` so a row confirmed in
the gap is never removed.

An orphan may carry its own ``not_added`` applied-discount children (the
discount snapshot never got its coupon resolved either); those rows FK-reference
the membership item (``fk_applied_discount_membership_gym``), so they are
deleted first, in the same transaction as the item row, mirroring the
reprice-revert precedent (``applied_discounts/delete_copied_discounts.sql``).
"""

import logging
from uuid import UUID

from sqlalchemy import text

from src.core.config import settings
from src.memberships import SQL_DIR as MEMBERSHIPS_SQL_DIR
from src.reconciler import SQL_DIR
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.shared.resource_lock import ResourceLock
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SWEEP_NAME = "orphan_cleanup"


class OrphanCleanupSweep:
    """Delete orphaned ``not_added`` memberships when their payer is idle."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        resource_lock: ResourceLock,
    ) -> None:
        self._db_pool = db_pool
        self._resource_lock = resource_lock

    async def run(self) -> SweepResult:
        """Sweep every orphaned ``not_added`` row; skip any payer in flight."""
        orphans = await self._list_orphans()
        result = SweepResult(name=SWEEP_NAME, processed=len(orphans))
        for orphan in orphans:
            await self._try_cleanup_one(orphan, result)
        logger.info(
            "Orphan cleanup: processed=%d deleted=%d skipped=%d errors=%d",
            result.processed,
            result.changed,
            result.skipped,
            result.errors,
        )
        return result

    async def _list_orphans(self) -> list[dict]:
        """Return all orphaned pending rows (item_id, paid_by_member_id, ...)."""
        sql = load_sql(SQL_DIR / "reconciler_orphan_memberships.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return [dict(row) for row in res.mappings().all()]

    async def _try_cleanup_one(
        self,
        orphan: dict,
        result: SweepResult,
    ) -> None:
        """Delete one orphan under its payer lock, isolating any failure.

        A held lock means an op is in flight (``skipped``, not a failure).
        A free lock attempts the delete; any exception is caught here so one
        orphan's failure can't abort the rest of the sweep (or the reconciler
        steps that run after it) — mirrors ``SubscriptionOrphanSweep._cancel_orphan``.
        """
        key = (
            f"{settings.paying_member_lock_prefix}:"
            f"{orphan['paid_by_member_id']}"
        )
        async with self._resource_lock.try_lock(key) as acquired:
            if not acquired:
                result.skipped += 1
                return
            try:
                await self._delete_orphan(orphan["item_id"])
                result.changed += 1
            except Exception:
                logger.error(
                    "Failed to delete orphan membership %s; continuing",
                    orphan["item_id"],
                    exc_info=True,
                )
                result.errors += 1

    async def _delete_orphan(self, item_id: UUID) -> None:
        """Delete one orphan's applied-discount children, then its item row.

        Both deletes run on one shared session / one transaction: the
        discount children must go first, or ``fk_applied_discount_membership_gym``
        blocks the item delete (an orphan with applied-discount children would
        otherwise never be cleaned).
        """
        discounts_sql = load_sql(
            SQL_DIR / "reconciler_orphan_applied_discounts.sql",
        )
        item_sql = load_sql(
            MEMBERSHIPS_SQL_DIR / "member_memberships_delete_pending.sql",
        )
        async with self._db_pool.session() as session:
            await session.execute(
                text(discounts_sql), {"item_id": str(item_id)}
            )
            await session.execute(
                text(item_sql), {"item_ids": [str(item_id)]}
            )
            await session.commit()
